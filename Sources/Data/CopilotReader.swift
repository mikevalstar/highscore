import Foundation

/// Reads GitHub Copilot CLI token usage from session event JSONL files.
///
/// Copilot CLI stores sessions at `~/.copilot/session-state/<uuid>/events.jsonl`.
/// Each file contains an event stream. The canonical per-session totals live in
/// the final `session.shutdown` event under `data.modelMetrics.*.usage`:
/// ```json
/// { "type": "session.shutdown", "data": { "modelMetrics": {
///     "claude-sonnet-4.6": { "usage": {
///         "inputTokens": N, "outputTokens": N,
///         "cacheReadTokens": N, "cacheWriteTokens": N,
///         "reasoningTokens": N
///     }}
/// }}}
/// ```
///
/// We use `session.shutdown` totals when available because they already include
/// the `assistant.message.outputTokens` counts. Falling back to summing message
/// events is only safe when shutdown totals are missing.
/// The state DB (path: `copilot:<session-uuid>`) caches results using file size +
/// mtime for change detection, following the same pattern as other readers.
final class CopilotReader: TokenReader, Sendable {
    let name = "Copilot"

    private let db: ScoreDatabase

    init(db: ScoreDatabase) {
        self.db = db
        Log.copilot.info("CopilotReader initialized")
    }

    var watchPaths: [String] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return [homeDir.appendingPathComponent(".copilot/session-state").path]
    }

    func readUsage(since: Int64 = 0) -> TokenScore {
        let start = CFAbsoluteTimeGetCurrent()

        let dbTotal = db.totalScore(since: since, source: "copilot")

        let sessionStateDir = findSessionStateDirectory()
        guard let sessionStateDir else {
            Log.copilot.debug("No Copilot session-state directory found — returning cached total")
            return dbTotal
        }

        let eventFiles = findEventFiles(in: sessionStateDir)

        var totalFiles = 0
        var parsedFiles = 0
        var skippedFiles = 0
        var deltaScore = TokenScore()

        for file in eventFiles {
            totalFiles += 1
            let path = file.path

            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let fileSize = attrs[.size] as? UInt64,
                  let modDate = attrs[.modificationDate] as? Date else {
                Log.copilot.debug("Could not stat file: \(path)")
                continue
            }

            let modTimestamp = Int64(modDate.timeIntervalSince1970)

            if modTimestamp < since {
                skippedFiles += 1
                continue
            }

            // Use the parent directory name (session UUID) as the cache key
            let sessionId = file.deletingLastPathComponent().lastPathComponent
            let cachePath = "copilot:\(sessionId)"
            let cached = db.get(cachePath)

            if let cached, cached.fileSize == fileSize, cached.modifiedAt == modTimestamp {
                skippedFiles += 1
            } else {
                let oldScore = cached?.score ?? TokenScore()
                let newScore = parseSessionTotals(from: file)

                db.upsert(
                    path: cachePath,
                    fileSize: fileSize,
                    modifiedAt: modTimestamp,
                    score: newScore,
                    source: "copilot"
                )

                deltaScore = deltaScore.adding(newScore).subtracting(oldScore)
                parsedFiles += 1

                Log.copilot.debug(
                    "\(sessionId, privacy: .public): in=\(newScore.inputTokens), out=\(newScore.outputTokens), cacheRead=\(newScore.cacheReadTokens), cacheWrite=\(newScore.cacheCreationTokens), reasoning=\(newScore.reasoningTokens)"
                )
            }
        }

        let finalScore = dbTotal.adding(deltaScore)

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let elapsedStr = String(format: "%.1f", elapsed)
        Log.copilot.notice(
            "Scan complete: \(totalFiles) files, \(parsedFiles) parsed, \(skippedFiles) cached, \(elapsedStr, privacy: .public)ms elapsed"
        )
        Log.copilot.notice(
            "Totals — in: \(finalScore.inputTokens), out: \(finalScore.outputTokens), cacheRead: \(finalScore.cacheReadTokens), cacheWrite: \(finalScore.cacheCreationTokens), reasoning: \(finalScore.reasoningTokens)"
        )

        return finalScore
    }

    // MARK: - Private

    /// Locates the Copilot session-state directory at `~/.copilot/session-state/`.
    private func findSessionStateDirectory() -> URL? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let sessionDir = homeDir.appendingPathComponent(".copilot/session-state")

        if FileManager.default.fileExists(atPath: sessionDir.path) {
            Log.copilot.debug("Found Copilot sessions at \(sessionDir.path, privacy: .public)")
            return sessionDir
        }

        Log.copilot.debug("No Copilot session-state directory at \(sessionDir.path, privacy: .public)")
        return nil
    }

    /// Finds all `events.jsonl` files under session-state subdirectories.
    private func findEventFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            Log.copilot.warning("Failed to enumerate Copilot session-state directory")
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "events.jsonl" {
                files.append(fileURL)
            }
        }

        Log.copilot.debug("Found \(files.count) events.jsonl files")
        return files
    }

    /// Parses a session's token totals.
    ///
    /// We prefer the aggregate `session.shutdown` totals because they already
    /// include message-level output counts. Summing `assistant.message` outputs
    /// on top of shutdown totals would double count output tokens.
    private func parseSessionTotals(from fileURL: URL) -> TokenScore {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            Log.copilot.warning("Failed to read file: \(fileURL.lastPathComponent)")
            return TokenScore()
        }

        var shutdownScore: TokenScore?
        var fallbackOutput = 0
        var linesProcessed = 0
        var shutdownEvents = 0
        var messageEvents = 0

        content.enumerateLines { line, _ in
            guard !line.isEmpty else { return }
            linesProcessed += 1

            // Fast pre-filter: skip lines that can't contain token data we use.
            guard line.contains("session.shutdown") || line.contains("outputTokens") else { return }

            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                return
            }

            guard let type = json["type"] as? String,
                  let data = json["data"] as? [String: Any] else {
                return
            }

            switch type {
            case "session.shutdown":
                shutdownEvents += 1
                if let modelMetrics = data["modelMetrics"] as? [String: Any] {
                    shutdownScore = self.sumModelMetrics(modelMetrics)
                }
            case "assistant.message":
                if let outputTokens = self.intValue(data["outputTokens"]) {
                    fallbackOutput += outputTokens
                    messageEvents += 1
                }
            default:
                break
            }
        }

        if let shutdownScore {
            Log.copilot.debug(
                "\(fileURL.deletingLastPathComponent().lastPathComponent, privacy: .public): \(linesProcessed) lines, \(shutdownEvents) shutdown events, using aggregate totals"
            )
            return shutdownScore
        }

        let score = TokenScore(outputTokens: fallbackOutput)

        Log.copilot.debug(
            "\(fileURL.deletingLastPathComponent().lastPathComponent, privacy: .public): \(linesProcessed) lines, no shutdown totals, fell back to \(messageEvents) assistant.message events"
        )

        return score
    }

    /// Sums usage across all models recorded in the shutdown event.
    private func sumModelMetrics(_ modelMetrics: [String: Any]) -> TokenScore {
        var total = TokenScore()

        for metricValue in modelMetrics.values {
            guard let metric = metricValue as? [String: Any],
                  let usage = metric["usage"] as? [String: Any] else {
                continue
            }

            total = total.adding(TokenScore(
                inputTokens: intValue(usage["inputTokens"]) ?? 0,
                outputTokens: intValue(usage["outputTokens"]) ?? 0,
                cacheReadTokens: intValue(usage["cacheReadTokens"]) ?? 0,
                cacheCreationTokens: intValue(usage["cacheWriteTokens"]) ?? 0,
                reasoningTokens: intValue(usage["reasoningTokens"]) ?? 0
            ))
        }

        return total
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let int64 as Int64:
            return Int(int64)
        case let double as Double:
            return Int(double)
        case let number as NSNumber:
            return number.intValue
        default:
            return nil
        }
    }
}
