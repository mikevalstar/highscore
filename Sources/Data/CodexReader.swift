import Foundation

/// Reads Codex CLI token usage from rollout JSONL files.
///
/// Codex stores session files at `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
/// Each file contains an event stream; `token_count` events (nested inside `event_msg`)
/// carry running totals with a breakdown:
/// ```json
/// { "total_token_usage": {
///     "input_tokens": N, "output_tokens": N,
///     "cached_input_tokens": N, "reasoning_output_tokens": N,
///     "total_tokens": N
/// }}
/// ```
///
/// We take the **last** `token_count` event per file for the session's final totals.
/// The state DB (path: `codex:<filename>`) caches results using file size + mtime
/// for change detection, following the same pattern as ClaudeCodeReader.
final class CodexReader: TokenReader, Sendable {
    let name = "Codex"

    private let db: ScoreDatabase

    init(db: ScoreDatabase) {
        self.db = db
        Log.codex.info("CodexReader initialized")
    }

    func readUsage(since: Int64 = 0) -> TokenScore {
        let start = CFAbsoluteTimeGetCurrent()

        let dbTotal = db.totalScore(since: since, source: "codex")

        let sessionsDir = findSessionsDirectory()
        guard let sessionsDir else {
            Log.codex.debug("No Codex sessions directory found — returning cached total")
            return dbTotal
        }

        let rolloutFiles = findRolloutFiles(in: sessionsDir)

        var totalFiles = 0
        var parsedFiles = 0
        var skippedFiles = 0
        var deltaScore = TokenScore()

        for file in rolloutFiles {
            totalFiles += 1
            let path = file.path

            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let fileSize = attrs[.size] as? UInt64,
                  let modDate = attrs[.modificationDate] as? Date else {
                Log.codex.debug("Could not stat file: \(path)")
                continue
            }

            let modTimestamp = Int64(modDate.timeIntervalSince1970)

            if modTimestamp < since {
                skippedFiles += 1
                continue
            }

            let cachePath = "codex:\(file.lastPathComponent)"
            let cached = db.get(cachePath)

            if let cached, cached.fileSize == fileSize, cached.modifiedAt == modTimestamp {
                skippedFiles += 1
            } else {
                let oldScore = cached?.score ?? TokenScore()
                let newScore = parseLastTokenCount(from: file)

                db.upsert(
                    path: cachePath,
                    fileSize: fileSize,
                    modifiedAt: modTimestamp,
                    score: newScore,
                    source: "codex"
                )

                deltaScore = deltaScore.adding(newScore).subtracting(oldScore)
                parsedFiles += 1

                Log.codex.debug(
                    "\(file.lastPathComponent, privacy: .public): in=\(newScore.inputTokens), out=\(newScore.outputTokens), cached=\(newScore.cacheReadTokens), reasoning=\(newScore.reasoningTokens)"
                )
            }
        }

        let finalScore = dbTotal.adding(deltaScore)

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let elapsedStr = String(format: "%.1f", elapsed)
        Log.codex.notice(
            "Scan complete: \(totalFiles) files, \(parsedFiles) parsed, \(skippedFiles) cached, \(elapsedStr, privacy: .public)ms elapsed"
        )
        Log.codex.notice(
            "Totals — in: \(finalScore.inputTokens), out: \(finalScore.outputTokens), cacheRead: \(finalScore.cacheReadTokens), reasoning: \(finalScore.reasoningTokens)"
        )

        return finalScore
    }

    // MARK: - Private

    /// Locates the Codex sessions directory at `~/.codex/sessions/`.
    private func findSessionsDirectory() -> URL? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let sessionsDir = homeDir.appendingPathComponent(".codex/sessions")

        if FileManager.default.fileExists(atPath: sessionsDir.path) {
            Log.codex.debug("Found Codex sessions at \(sessionsDir.path, privacy: .public)")
            return sessionsDir
        }

        Log.codex.debug("No Codex sessions directory at \(sessionsDir.path, privacy: .public)")
        return nil
    }

    /// Recursively finds all `rollout-*.jsonl` files under the sessions directory.
    private func findRolloutFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            Log.codex.warning("Failed to enumerate Codex sessions directory")
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent.hasPrefix("rollout-") && fileURL.pathExtension == "jsonl" {
                files.append(fileURL)
            }
        }

        Log.codex.debug("Found \(files.count) rollout files")
        return files
    }

    /// Parses the last `token_count` event from a rollout JSONL file to get
    /// the session's final accumulated token usage.
    private func parseLastTokenCount(from fileURL: URL) -> TokenScore {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            Log.codex.warning("Failed to read file: \(fileURL.lastPathComponent)")
            return TokenScore()
        }

        var lastUsage: [String: Any]?
        var linesProcessed = 0

        content.enumerateLines { line, _ in
            guard !line.isEmpty else { return }
            linesProcessed += 1

            // Fast pre-filter: skip lines that can't contain token usage data
            guard line.contains("total_token_usage") else { return }

            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                return
            }

            // token_count events are nested inside event_msg:
            // { "type": "event_msg", "payload": { "type": "token_count", "info": { "total_token_usage": {...} } } }
            if let payload = json["payload"] as? [String: Any],
               let info = payload["info"] as? [String: Any],
               let totalUsage = info["total_token_usage"] as? [String: Any] {
                lastUsage = totalUsage
            }
        }

        guard let usage = lastUsage else {
            Log.codex.debug("\(fileURL.lastPathComponent): \(linesProcessed) lines, no token_count events found")
            return TokenScore()
        }

        let score = TokenScore(
            inputTokens: usage["input_tokens"] as? Int ?? 0,
            outputTokens: usage["output_tokens"] as? Int ?? 0,
            cacheReadTokens: usage["cached_input_tokens"] as? Int ?? 0,
            cacheCreationTokens: 0,
            reasoningTokens: usage["reasoning_output_tokens"] as? Int ?? 0
        )

        Log.codex.debug(
            "\(fileURL.lastPathComponent): \(linesProcessed) lines, final totals — in: \(score.inputTokens), out: \(score.outputTokens), cached: \(score.cacheReadTokens), reasoning: \(score.reasoningTokens)"
        )

        return score
    }
}
