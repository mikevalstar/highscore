import Foundation
import SwiftUI
import Combine

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

struct TokenScore: Sendable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var reasoningTokens: Int = 0

    var total: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens + reasoningTokens
    }

    func adding(_ other: TokenScore) -> TokenScore {
        TokenScore(
            inputTokens: inputTokens + other.inputTokens,
            outputTokens: outputTokens + other.outputTokens,
            cacheReadTokens: cacheReadTokens + other.cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens + other.cacheCreationTokens,
            reasoningTokens: reasoningTokens + other.reasoningTokens
        )
    }

    func subtracting(_ other: TokenScore) -> TokenScore {
        TokenScore(
            inputTokens: inputTokens - other.inputTokens,
            outputTokens: outputTokens - other.outputTokens,
            cacheReadTokens: cacheReadTokens - other.cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens - other.cacheCreationTokens,
            reasoningTokens: reasoningTokens - other.reasoningTokens
        )
    }
}

@MainActor
class ScoreManager: ObservableObject {
    @Published var combinedScore = TokenScore()

    /// Per-reader score breakdown: reader name → score
    @Published var readerScores: [(name: String, score: TokenScore)] = []

    /// The actual target score from data
    @Published var totalScore: Int = 0

    /// The displayed score that animates/ticks toward totalScore
    @Published var displayScore: Int = 0

    /// Today's token usage (current total minus start-of-day snapshot)
    @Published var todayScore: Int = 0
    @Published var displayTodayScore: Int = 0

    /// This week's token usage (current total minus start-of-week snapshot)
    @Published var weekScore: Int = 0
    @Published var displayWeekScore: Int = 0

    private var refreshTimer: Timer?
    private var tickTimer: Timer?
    private var isRefreshing = false
    private var startDateObserver: NSObjectProtocol?
    private var lastRefreshInterval: Double = 0

    private let db = ScoreDatabase()
    private lazy var readers: [TokenReader] = [
        ClaudeCodeReader(db: db),
        OpenCodeReader(db: db),
        CodexReader(db: db),
        CopilotReader(db: db),
        CursorReader(db: db),
    ]

    /// Returns the startDate setting as a Unix timestamp in seconds.
    private var startTimestamp: Int64 {
        Int64(UserDefaults.standard.double(forKey: "startDate"))
    }

    /// Today's date as YYYY-MM-DD
    private static var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// Start of the current week (Monday) as YYYY-MM-DD
    private static var weekStartDateString: String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        // .weekday: 1=Sunday, 2=Monday, ..., 7=Saturday → shift to Monday-start
        let daysFromMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: monday)
    }

    init() {
        Log.scores.info("ScoreManager initializing")

        // Load cached total from DB immediately so the UI shows a score right away
        let since = startTimestamp
        let cachedTotal = db.totalScore(since: since)
        if cachedTotal.total > 0 {
            combinedScore = cachedTotal
            totalScore = cachedTotal.total
            displayScore = cachedTotal.total
            Log.scores.info("Loaded cached score from DB: \(cachedTotal.total) (since: \(since))")
        }

        updatePeriodScores(currentTotal: cachedTotal)

        refresh()
        startTimers()
        observeStartDateChanges()
    }

    func refresh() {
        guard !isRefreshing else {
            Log.scores.debug("Refresh skipped — already in progress")
            return
        }
        isRefreshing = true
        Log.scores.debug("Starting background refresh with \(self.readers.count) reader(s)")

        let readers = self.readers
        let since = startTimestamp
        Task.detached(priority: .utility) {
            let startTime = CFAbsoluteTimeGetCurrent()

            var combined = TokenScore()
            var perReader: [(name: String, score: TokenScore)] = []
            for reader in readers {
                let readerStart = CFAbsoluteTimeGetCurrent()
                let score = reader.readUsage(since: since)
                let readerElapsed = (CFAbsoluteTimeGetCurrent() - readerStart) * 1000
                Log.scores.notice(
                    "\(reader.name, privacy: .public) read completed in \(String(format: "%.0f", readerElapsed), privacy: .public)ms — total: \(score.total)"
                )
                combined = combined.adding(score)
                perReader.append((name: reader.name, score: score))
            }

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            let finalScore = combined
            let finalPerReader = perReader
            Log.scores.notice("All readers completed in \(String(format: "%.0f", elapsed), privacy: .public)ms — combined total: \(finalScore.total)")

            await MainActor.run {
                self.combinedScore = finalScore
                self.readerScores = finalPerReader
                let oldTotal = self.totalScore
                self.totalScore = finalScore.total
                self.isRefreshing = false

                self.updatePeriodScores(currentTotal: finalScore)

                if oldTotal != finalScore.total {
                    Log.scores.notice("Score updated: \(oldTotal) → \(finalScore.total) (delta: \(finalScore.total - oldTotal))")
                } else {
                    Log.scores.notice("Score unchanged at \(finalScore.total)")
                }
            }
        }
    }

    /// Saves start-of-day/week snapshots if needed and computes period scores.
    private func updatePeriodScores(currentTotal: TokenScore) {
        let todayDate = Self.todayDateString
        let weekDate = Self.weekStartDateString

        // Save snapshot for today if this is the first refresh of the day
        db.saveSnapshotIfNeeded(date: todayDate, score: currentTotal)

        // Save snapshot for start of week if this is the first refresh of the week
        db.saveSnapshotIfNeeded(date: weekDate, score: currentTotal)

        // Compute period scores
        if let todaySnapshot = db.getSnapshot(date: todayDate) {
            let today = max(0, currentTotal.total - todaySnapshot.total)
            if today != todayScore {
                Log.scores.debug("Today score: \(today) (total: \(currentTotal.total), snapshot: \(todaySnapshot.total))")
            }
            todayScore = today
        }

        if let weekSnapshot = db.getSnapshot(date: weekDate) {
            let week = max(0, currentTotal.total - weekSnapshot.total)
            if week != weekScore {
                Log.scores.debug("Week score: \(week) (total: \(currentTotal.total), snapshot: \(weekSnapshot.total))")
            }
            weekScore = week
        }
    }

    /// Returns the refresh interval setting in seconds.
    private var refreshInterval: Double {
        UserDefaults.standard.double(forKey: "refreshInterval").clamped(to: 1...60)
    }

    private func startTimers() {
        let interval = refreshInterval
        lastRefreshInterval = interval
        Log.scores.info("Starting timers: refresh=\(String(format: "%.0f", interval))s, tick=30fps")

        // Refresh from disk at the configured interval
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }

        // Tick the display score toward actual score ~30fps
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickDisplayScore()
            }
        }
    }

    /// Restarts the refresh timer if the interval setting changed.
    private func restartRefreshTimerIfNeeded() {
        let interval = refreshInterval
        guard interval != lastRefreshInterval else { return }
        lastRefreshInterval = interval
        refreshTimer?.invalidate()
        Log.scores.info("Refresh interval changed to \(String(format: "%.0f", interval))s — restarting timer")
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func tickDisplayScore() {
        displayScore = Self.tickValue(current: displayScore, toward: totalScore)
        displayTodayScore = Self.tickValue(current: displayTodayScore, toward: todayScore)
        displayWeekScore = Self.tickValue(current: displayWeekScore, toward: weekScore)
    }

    private static func tickValue(current: Int, toward target: Int) -> Int {
        guard current != target else { return current }

        let diff = target - current
        let absDiff = abs(diff)
        let step: Int
        if absDiff > 100_000 {
            step = absDiff / 10
        } else if absDiff > 10_000 {
            step = absDiff / 20
        } else if absDiff > 1_000 {
            step = absDiff / 30
        } else if absDiff > 100 {
            step = max(absDiff / 15, 1)
        } else {
            step = 1
        }

        if diff > 0 {
            return min(current + step, target)
        } else {
            return max(current - step, target)
        }
    }

    /// When startDate changes in UserDefaults, force a full refresh so the score
    /// immediately reflects the new filter.
    private func observeStartDateChanges() {
        startDateObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // Re-read the cached total with the new filter and force refresh
                let since = self.startTimestamp
                let cachedTotal = self.db.totalScore(since: since)
                self.combinedScore = cachedTotal
                self.totalScore = cachedTotal.total
                self.displayScore = cachedTotal.total
                self.updatePeriodScores(currentTotal: cachedTotal)
                self.restartRefreshTimerIfNeeded()
                Log.scores.notice("startDate changed — recalculated cached total: \(cachedTotal.total) (since: \(since))")
                self.isRefreshing = false
                self.refresh()
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
        tickTimer?.invalidate()
        if let startDateObserver {
            NotificationCenter.default.removeObserver(startDateObserver)
        }
    }
}
