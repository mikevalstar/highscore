import Foundation

/// Reads GitHub Copilot CLI token usage from session event JSONL files.
///
/// Copilot CLI stores sessions at `~/.copilot/session-state/<uuid>/events.jsonl`.
/// Each file contains an event stream; `assistant.message` events carry an
/// `outputTokens` count:
/// ```json
/// { "type": "assistant.message", "data": { "outputTokens": N, ... } }
/// ```
///
/// We sum all `outputTokens` values per file for the session's total output usage.
/// Input token counts are not available in Copilot CLI's event format.
/// The state DB (path: `copilot:<session-uuid>`) caches results using file size +
/// mtime for change detection, following the same pattern as other readers.
final class CopilotReader: TokenReader, Sendable {
    let name = "Copilot"

    private let db: ScoreDatabase

    init(db: ScoreDatabase) {
        self.db = db
        Log.copilot.info("CopilotReader initialized")
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
                let newScore = parseOutputTokens(from: file)

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
                    "\(sessionId, privacy: .public): out=\(newScore.outputTokens)"
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
            "Totals — out: \(finalScore.outputTokens)"
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

    /// Sums `outputTokens` from all `assistant.message` events in an events.jsonl file.
    private func parseOutputTokens(from fileURL: URL) -> TokenScore {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            Log.copilot.warning("Failed to read file: \(fileURL.lastPathComponent)")
            return TokenScore()
        }

        var totalOutput = 0
        var linesProcessed = 0

        content.enumerateLines { line, _ in
            guard !line.isEmpty else { return }
            linesProcessed += 1

            // Fast pre-filter: skip lines that can't contain output token data
            guard line.contains("outputTokens") else { return }

            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                return
            }

            // assistant.message events contain outputTokens in data:
            // { "type": "assistant.message", "data": { "outputTokens": N, ... } }
            guard let type = json["type"] as? String, type == "assistant.message",
                  let data = json["data"] as? [String: Any],
                  let outputTokens = data["outputTokens"] as? Int else {
                return
            }

            totalOutput += outputTokens
        }

        let score = TokenScore(
            inputTokens: 0,
            outputTokens: totalOutput,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0
        )

        Log.copilot.debug(
            "\(fileURL.deletingLastPathComponent().lastPathComponent, privacy: .public): \(linesProcessed) lines, out=\(totalOutput)"
        )

        return score
    }
}
