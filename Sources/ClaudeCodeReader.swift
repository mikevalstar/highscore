import Foundation

/// Reads Claude Code token usage from conversation JSONL files.
///
/// Uses a SQLite database to persist file state across app launches.
/// Only re-parses files whose size or mtime has changed.
/// All public methods are safe to call from any thread.
final class ClaudeCodeReader: Sendable {
    private let db: ScoreDatabase

    init(db: ScoreDatabase) {
        self.db = db
    }

    /// Reads usage, only parsing files that have changed since last scan.
    /// On a warm start (DB populated), this returns near-instantly.
    func readUsage() -> TokenScore {
        let start = CFAbsoluteTimeGetCurrent()

        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = homeDir.appendingPathComponent(".claude/projects")

        // Start with all scores from the DB (includes deleted files — running total)
        let dbTotal = db.totalScore()

        guard FileManager.default.fileExists(atPath: claudeDir.path) else {
            Log.reader.debug("Claude projects directory not found at \(claudeDir.path)")
            return dbTotal
        }

        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: claudeDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            Log.reader.warning("Failed to list project directories")
            return dbTotal
        }

        var totalFiles = 0
        var parsedFiles = 0
        var skippedFiles = 0
        var deltaScore = TokenScore() // net change from files we re-parsed

        for projectDir in projectDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for file in files where file.pathExtension == "jsonl" {
                totalFiles += 1
                let path = file.path

                guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                      let fileSize = attrs[.size] as? UInt64,
                      let modDate = attrs[.modificationDate] as? Date else {
                    Log.reader.debug("Could not stat file: \(path)")
                    continue
                }

                // Truncate to seconds for reliable comparison (avoids sub-second precision drift)
                let modTimestamp = Int64(modDate.timeIntervalSince1970)
                let cached = db.get(path)

                if let cached, cached.fileSize == fileSize, cached.modifiedAt == modTimestamp {
                    // File unchanged — already counted in dbTotal
                    skippedFiles += 1
                } else {
                    // File is new or changed — parse it
                    let oldScore = cached?.score ?? TokenScore()
                    let newScore: TokenScore

                    if let cached, fileSize > cached.fileSize {
                        // File grew — only parse the appended bytes
                        newScore = parseAppendedTokens(
                            from: file,
                            startingAt: cached.fileSize,
                            existingScore: cached.score
                        )
                    } else {
                        // New file or file was rewritten — full parse
                        newScore = parseAllTokens(from: file)
                    }

                    db.upsert(path: path, fileSize: fileSize, modifiedAt: modTimestamp, score: newScore)

                    // Track the delta: new score minus what the DB had before
                    deltaScore = deltaScore.adding(newScore).subtracting(oldScore)
                    parsedFiles += 1
                }
            }
        }

        let finalScore = dbTotal.adding(deltaScore)

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let elapsedStr = String(format: "%.1f", elapsed)
        Log.reader.notice(
            "Scan complete: \(totalFiles) files, \(parsedFiles) parsed, \(skippedFiles) cached, \(elapsedStr, privacy: .public)ms elapsed — db has \(self.db.count()) entries"
        )
        Log.reader.notice(
            "Totals — in: \(finalScore.inputTokens), out: \(finalScore.outputTokens), cacheRead: \(finalScore.cacheReadTokens), cacheCreate: \(finalScore.cacheCreationTokens)"
        )

        return finalScore
    }

    private func parseAllTokens(from fileURL: URL) -> TokenScore {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            Log.reader.warning("Failed to read file: \(fileURL.lastPathComponent)")
            return TokenScore()
        }
        return parseTokens(from: content, fileName: fileURL.lastPathComponent)
    }

    private func parseAppendedTokens(from fileURL: URL, startingAt offset: UInt64, existingScore: TokenScore) -> TokenScore {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            Log.reader.warning("Failed to open file handle: \(fileURL.lastPathComponent)")
            return existingScore
        }
        defer { try? handle.close() }

        handle.seek(toFileOffset: offset)
        let newData = handle.readDataToEndOfFile()

        guard !newData.isEmpty,
              let newContent = String(data: newData, encoding: .utf8) else {
            return existingScore
        }

        Log.reader.debug(
            "Incremental read of \(fileURL.lastPathComponent): \(newData.count) new bytes from offset \(offset)"
        )

        let newScore = parseTokens(from: newContent, fileName: fileURL.lastPathComponent)
        return existingScore.adding(newScore)
    }

    /// Parse token usage from JSONL string content.
    /// Uses a fast pre-filter: only JSON-parse lines containing "input_tokens".
    private func parseTokens(from content: String, fileName: String) -> TokenScore {
        var score = TokenScore()
        var linesProcessed = 0
        var usageFound = 0

        content.enumerateLines { line, _ in
            guard !line.isEmpty else { return }
            linesProcessed += 1

            // Fast pre-filter: skip lines that can't contain usage data
            guard line.contains("input_tokens") else { return }

            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                return
            }

            let usage: [String: Any]?
            if let topLevel = json["usage"] as? [String: Any] {
                usage = topLevel
            } else if let message = json["message"] as? [String: Any],
                      let msgUsage = message["usage"] as? [String: Any] {
                usage = msgUsage
            } else {
                usage = nil
            }

            if let usage {
                usageFound += 1
                if let v = usage["input_tokens"] as? Int { score.inputTokens += v }
                if let v = usage["output_tokens"] as? Int { score.outputTokens += v }
                if let v = usage["cache_read_input_tokens"] as? Int { score.cacheReadTokens += v }
                if let v = usage["cache_creation_input_tokens"] as? Int { score.cacheCreationTokens += v }
            }
        }

        Log.reader.debug(
            "\(fileName): \(linesProcessed) lines, \(usageFound) usage records"
        )

        return score
    }
}
