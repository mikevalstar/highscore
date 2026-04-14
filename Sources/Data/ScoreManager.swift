import Foundation
import SwiftUI
import Combine

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

struct XPGain: Equatable, Sendable {
    let amount: Int
    let id: Int
}

struct TokenScore: Sendable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var reasoningTokens: Int = 0

    /// Total tokens. Honors the "includeCachedTokens" user setting — when that
    /// toggle is off, cache read/creation tokens are excluded from the total.
    /// Setting defaults to on (included) when the key is absent.
    var total: Int {
        let raw = inputTokens + outputTokens + reasoningTokens
        let includeCached = (UserDefaults.standard.object(forKey: "includeCachedTokens") as? Bool) ?? true
        return includeCached ? raw + cacheReadTokens + cacheCreationTokens : raw
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

    /// Emitted when a refresh detects a score increase — used for XP popup display
    @Published var lastXPGain: XPGain?
    private var xpGainCounter: Int = 0
    private var hasCompletedFirstRefresh: Bool = false

    private var refreshTimer: Timer?
    private var tickTimer: Timer?
    private var isRefreshing = false
    private var startDateObserver: NSObjectProtocol?
    private var lastRefreshInterval: Double = 0
    private var lastStartTimestamp: Int64 = 0
    private var lastIncludeCachedTokens: Bool = true

    /// FSEvents-backed watcher for all reader source directories. Events are
    /// run through a leading-edge throttle (see `handleFileChange`).
    private var fileWatcher: FileWatcher?
    /// Throttle window. The first event fires a refresh immediately; any events
    /// arriving during the window are suppressed but remembered, and if at least
    /// one arrived, a single trailing refresh fires when the window closes.
    private let fileChangeThrottle: TimeInterval = 5.0
    private var lastFileTriggeredRefresh: Date?
    private var trailingRefreshScheduled: Bool = false

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
        lastStartTimestamp = since
        lastIncludeCachedTokens = (UserDefaults.standard.object(forKey: "includeCachedTokens") as? Bool) ?? true
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
        startFileWatcher()
        observeStartDateChanges()
    }

    func refresh() {
        guard !isRefreshing else {
            Log.scores.debug("Refresh skipped — already in progress")
            return
        }
        isRefreshing = true
        Log.scores.notice("Refresh starting with \(self.readers.count) reader(s), tickTimer=\(self.tickTimer != nil ? "running" : "stopped")")

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
                let oldTotal = self.totalScore
                self.isRefreshing = false

                // Only publish changes to avoid unnecessary SwiftUI redraws
                if finalScore.total != oldTotal {
                    let delta = finalScore.total - oldTotal
                    self.combinedScore = finalScore
                    self.totalScore = finalScore.total
                    Log.scores.notice("Score updated: \(oldTotal) → \(finalScore.total) (delta: \(delta))")
                    if delta > 0 && self.hasCompletedFirstRefresh {
                        self.xpGainCounter += 1
                        self.lastXPGain = XPGain(amount: delta, id: self.xpGainCounter)
                        Log.scores.notice("XP gain emitted: +\(delta) (id: \(self.xpGainCounter))")
                    } else if !self.hasCompletedFirstRefresh {
                        Log.scores.notice("Skipping XP popup for initial catch-up (delta: \(delta))")
                    }
                    self.startTickTimerIfNeeded()
                } else {
                    Log.scores.notice("Score unchanged at \(finalScore.total)")
                }

                // Only update readerScores if the breakdown changed
                let oldScores = self.readerScores
                let scoresChanged = oldScores.count != finalPerReader.count
                    || zip(oldScores, finalPerReader).contains { $0.0.name != $0.1.name || $0.0.score.total != $0.1.score.total }
                if scoresChanged {
                    self.readerScores = finalPerReader
                }

                self.hasCompletedFirstRefresh = true
                self.updatePeriodScores(currentTotal: finalScore)
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
        var periodChanged = false
        if let todaySnapshot = db.getSnapshot(date: todayDate) {
            let today = max(0, currentTotal.total - todaySnapshot.total)
            if today != todayScore {
                Log.scores.debug("Today score: \(today) (total: \(currentTotal.total), snapshot: \(todaySnapshot.total))")
                todayScore = today
                periodChanged = true
            }
        }

        if let weekSnapshot = db.getSnapshot(date: weekDate) {
            let week = max(0, currentTotal.total - weekSnapshot.total)
            if week != weekScore {
                Log.scores.debug("Week score: \(week) (total: \(currentTotal.total), snapshot: \(weekSnapshot.total))")
                weekScore = week
                periodChanged = true
            }
        }

        if periodChanged {
            startTickTimerIfNeeded()
        }
    }

    /// Returns the refresh interval setting in seconds.
    /// Note: `@AppStorage` defaults don't apply to raw `UserDefaults.double(forKey:)`,
    /// which returns 0 when the key is absent. We default to 5s in that case.
    private var refreshInterval: Double {
        let raw = UserDefaults.standard.double(forKey: "refreshInterval")
        return (raw > 0 ? raw : 5).clamped(to: 1...60)
    }

    private func startTimers() {
        let interval = refreshInterval
        lastRefreshInterval = interval
        Log.scores.info("Starting timers: refresh=\(String(format: "%.0f", interval))s, tick=on-demand")

        // Refresh from disk at the configured interval
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    /// Starts an FSEvents-backed watcher across every reader's declared source
    /// directories. File events feed `handleFileChange`, which implements a
    /// leading-edge throttle — first event fires refresh immediately; further
    /// events inside the window are collapsed into a single trailing refresh.
    ///
    /// The periodic `refreshTimer` still runs as a safety net to catch anything
    /// FSEvents drops (sleep/wake, permission hiccups, filesystem edge cases).
    private func startFileWatcher() {
        let paths = readers.flatMap(\.watchPaths)
        guard !paths.isEmpty else {
            Log.scores.info("No reader declared watchPaths — file watching disabled, polling only")
            return
        }

        Log.scores.info("Wiring file watcher across \(paths.count) reader path(s), throttle=\(String(format: "%.1f", self.fileChangeThrottle))s leading-edge")
        fileWatcher = FileWatcher(paths: paths, latency: 0.5) { [weak self] in
            // Fires on watcher's utility queue; hop to main for state mutation.
            guard let self else { return }
            Task { @MainActor in
                self.handleFileChange()
            }
        }
        fileWatcher?.start()
    }

    /// Leading-edge throttle. The first event in a quiet period fires refresh
    /// immediately so the UI reacts without waiting. Subsequent events inside
    /// the `fileChangeThrottle` window are suppressed but remembered — one
    /// trailing refresh fires at the end of the window to catch anything that
    /// arrived after the initial fire but before the throttle expired.
    private func handleFileChange() {
        let now = Date()

        if let last = lastFileTriggeredRefresh,
           now.timeIntervalSince(last) < fileChangeThrottle {
            // Inside the throttle window — schedule a single trailing refresh.
            if trailingRefreshScheduled {
                Log.scores.debug("File event in throttle window — trailing refresh already scheduled")
                return
            }
            trailingRefreshScheduled = true
            let remaining = fileChangeThrottle - now.timeIntervalSince(last)
            Log.scores.debug("File event in throttle window — scheduling trailing refresh in \(String(format: "%.2f", remaining))s")
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
                guard let self else { return }
                self.trailingRefreshScheduled = false
                self.lastFileTriggeredRefresh = Date()
                Log.scores.notice("Trailing refresh firing (throttle window closed)")
                self.refresh()
            }
        } else {
            // Leading edge — fire immediately.
            lastFileTriggeredRefresh = now
            Log.scores.notice("Leading-edge refresh on file change")
            refresh()
        }
    }

    /// Starts the 30fps tick timer if not already running. The timer stops itself
    /// once all display scores reach their targets, so it only consumes CPU while
    /// an animation is in progress.
    private func startTickTimerIfNeeded() {
        guard tickTimer == nil else { return }
        Log.scores.debug("Starting tick timer (animation in progress)")
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickDisplayScore()
            }
        }
    }

    private func stopTickTimer() {
        guard tickTimer != nil else { return }
        tickTimer?.invalidate()
        tickTimer = nil
        Log.scores.debug("Stopped tick timer (animation complete)")
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

    private var tickCount: Int = 0
    private var lastTickLog: CFAbsoluteTime = 0

    private func tickDisplayScore() {
        let now = CFAbsoluteTimeGetCurrent()
        tickCount += 1
        displayScore = Self.tickValue(current: displayScore, toward: totalScore)
        displayTodayScore = Self.tickValue(current: displayTodayScore, toward: todayScore)
        displayWeekScore = Self.tickValue(current: displayWeekScore, toward: weekScore)

        // Log tick activity every 5 seconds to avoid spam
        if now - lastTickLog >= 5.0 {
            Log.scores.notice("Tick timer active: \(self.tickCount) ticks in last 5s, display=\(self.displayScore) target=\(self.totalScore) delta=\(self.totalScore - self.displayScore)")
            tickCount = 0
            lastTickLog = now
        }

        // Stop the timer once all values have caught up — no need to keep ticking
        if displayScore == totalScore
            && displayTodayScore == todayScore
            && displayWeekScore == weekScore
        {
            Log.scores.notice("Tick timer stopping — all display scores reached targets")
            stopTickTimer()
        }
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
                let since = self.startTimestamp
                let includeCached = (UserDefaults.standard.object(forKey: "includeCachedTokens") as? Bool) ?? true
                let includeCachedChanged = includeCached != self.lastIncludeCachedTokens
                let startDateChanged = since != self.lastStartTimestamp

                guard startDateChanged || includeCachedChanged else {
                    Log.scores.debug("UserDefaults changed — startDate & includeCachedTokens unchanged, checking refreshInterval only")
                    self.restartRefreshTimerIfNeeded()
                    return
                }

                self.lastStartTimestamp = since
                self.lastIncludeCachedTokens = includeCached

                // Re-read the cached total. The DB breakdown doesn't change, but
                // `TokenScore.total` now reflects the new filter, so republishing
                // the struct is enough to drive UI updates.
                let cachedTotal = self.db.totalScore(since: since)
                self.combinedScore = cachedTotal
                self.totalScore = cachedTotal.total
                self.displayScore = cachedTotal.total
                self.updatePeriodScores(currentTotal: cachedTotal)
                self.restartRefreshTimerIfNeeded()
                self.startTickTimerIfNeeded()
                Log.scores.notice("Settings changed (startDate=\(startDateChanged), includeCached=\(includeCachedChanged, privacy: .public)) — recalculated total: \(cachedTotal.total) (since: \(since), includeCached: \(includeCached))")
                self.isRefreshing = false
                if startDateChanged {
                    self.refresh()
                }
            }
        }
    }

    deinit {
        refreshTimer?.invalidate()
        tickTimer?.invalidate()
        fileWatcher?.stop()
        if let startDateObserver {
            NotificationCenter.default.removeObserver(startDateObserver)
        }
    }
}
