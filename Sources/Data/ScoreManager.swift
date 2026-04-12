import Foundation
import SwiftUI
import Combine

struct TokenScore: Sendable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0

    var total: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    func adding(_ other: TokenScore) -> TokenScore {
        TokenScore(
            inputTokens: inputTokens + other.inputTokens,
            outputTokens: outputTokens + other.outputTokens,
            cacheReadTokens: cacheReadTokens + other.cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens + other.cacheCreationTokens
        )
    }

    func subtracting(_ other: TokenScore) -> TokenScore {
        TokenScore(
            inputTokens: inputTokens - other.inputTokens,
            outputTokens: outputTokens - other.outputTokens,
            cacheReadTokens: cacheReadTokens - other.cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens - other.cacheCreationTokens
        )
    }
}

@MainActor
class ScoreManager: ObservableObject {
    @Published var claudeCodeScore = TokenScore()

    /// The actual target score from data
    @Published var totalScore: Int = 0

    /// The displayed score that animates/ticks toward totalScore
    @Published var displayScore: Int = 0

    private var refreshTimer: Timer?
    private var tickTimer: Timer?
    private var isRefreshing = false
    private var startDateObserver: NSObjectProtocol?

    private let db = ScoreDatabase()
    private lazy var reader = ClaudeCodeReader(db: db)

    /// Returns the startDate setting as a Unix timestamp in seconds.
    private var startTimestamp: Int64 {
        Int64(UserDefaults.standard.double(forKey: "startDate"))
    }

    init() {
        Log.scores.info("ScoreManager initializing")

        // Load cached total from DB immediately so the UI shows a score right away
        let since = startTimestamp
        let cachedTotal = db.totalScore(since: since)
        if cachedTotal.total > 0 {
            claudeCodeScore = cachedTotal
            totalScore = cachedTotal.total
            displayScore = cachedTotal.total
            Log.scores.info("Loaded cached score from DB: \(cachedTotal.total) (since: \(since))")
        }

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
        Log.scores.debug("Starting background refresh")

        let reader = self.reader
        let since = startTimestamp
        Task.detached(priority: .utility) {
            let startTime = CFAbsoluteTimeGetCurrent()
            let score = reader.readUsage(since: since)
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            Log.scores.notice("Background read completed in \(String(format: "%.0f", elapsed), privacy: .public)ms")
            await MainActor.run {
                self.claudeCodeScore = score
                let oldTotal = self.totalScore
                self.totalScore = score.total
                self.isRefreshing = false

                if oldTotal != score.total {
                    Log.scores.notice("Score updated: \(oldTotal) → \(score.total) (delta: \(score.total - oldTotal))")
                } else {
                    Log.scores.notice("Score unchanged at \(score.total)")
                }
            }
        }
    }

    private func startTimers() {
        Log.scores.info("Starting timers: refresh=5s, tick=30fps")

        // Refresh from disk every 5 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
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

    private func tickDisplayScore() {
        guard displayScore != totalScore else { return }

        let diff = totalScore - displayScore
        let step: Int
        let absDiff = abs(diff)
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
            displayScore = min(displayScore + step, totalScore)
        } else {
            displayScore = max(displayScore - step, totalScore)
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
                self.claudeCodeScore = cachedTotal
                self.totalScore = cachedTotal.total
                self.displayScore = cachedTotal.total
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
