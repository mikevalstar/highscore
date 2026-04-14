import Foundation
import SQLite3

/// Reads Cursor token usage from the global state database.
///
/// Cursor stores conversation data in its VS Code state database at
/// `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`.
/// The `cursorDiskKV` table holds two relevant key prefixes:
///
/// - `composerData:<uuid>` — conversation metadata (timestamps, inline conversation
///   for older format, or `fullConversationHeadersOnly` for newer format)
/// - `bubbleId:<composerId>:<bubbleId>` — individual message data with per-bubble
///   `tokenCount: { inputTokens, outputTokens }` (newer Cursor versions)
///
/// The reader handles both formats:
/// - **Old format**: `conversation` array inline with `tokenCount` (int) for context tokens,
///   output estimated from assistant text (~4 chars/token)
/// - **New format (v14+)**: token counts from `bubbleId:` entries with exact
///   `inputTokens` / `outputTokens` per bubble
///
/// **Note**: Cursor's basic chat mode may record 0 tokens in bubbles — only
/// agent/composer workflows reliably populate token counts.
/// To avoid double counting, each composer uses exactly one representation:
/// bubble totals when available, otherwise inline conversation data.
///
/// Per-conversation totals are cached in the shared `ScoreDatabase` with
/// path `cursor:<composerId>`. Change detection uses `lastUpdatedAt`.
final class CursorReader: TokenReader, Sendable {
    let name = "Cursor"

    private let db: ScoreDatabase

    init(db: ScoreDatabase) {
        self.db = db
        Log.cursor.info("CursorReader initialized")
    }

    /// Watch the containing directory — SQLite WAL/SHM sidecars churn on writes
    /// while the main state.vscdb mtime may lag.
    var watchPaths: [String] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let dir = homeDir
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage")
            .path
        return [dir]
    }

    func readUsage(since: Int64 = 0) -> TokenScore {
        let start = CFAbsoluteTimeGetCurrent()

        let dbTotal = db.totalScore(since: since, source: "cursor")

        guard let stateDbPath = findStateDatabase() else {
            Log.cursor.debug("No Cursor state database found — returning cached total")
            return dbTotal
        }

        let result = syncConversations(from: stateDbPath, since: since)
        let finalScore = dbTotal.adding(result.delta)

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let elapsedStr = String(format: "%.1f", elapsed)
        Log.cursor.notice(
            "Scan complete: \(result.total) conversations, \(result.parsed) parsed, \(result.skipped) cached, \(elapsedStr, privacy: .public)ms elapsed"
        )
        Log.cursor.notice(
            "Totals — in: \(finalScore.inputTokens), out: \(finalScore.outputTokens)"
        )

        return finalScore
    }

    // MARK: - Private

    private struct SyncResult {
        var parsed: Int = 0
        var skipped: Int = 0
        var total: Int = 0
        var delta: TokenScore = TokenScore()
    }

    /// Locates the Cursor state database.
    private func findStateDatabase() -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let dbPath = homeDir
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
            .path

        if FileManager.default.fileExists(atPath: dbPath) {
            Log.cursor.debug("Found Cursor state DB at \(dbPath, privacy: .public)")
            return dbPath
        }

        Log.cursor.debug("No Cursor state DB found at \(dbPath, privacy: .public)")
        return nil
    }

    /// Syncs conversation token totals from the Cursor state DB into our ScoreDatabase.
    private func syncConversations(from stateDbPath: String, since: Int64) -> SyncResult {
        var cursorDb: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(stateDbPath, &cursorDb, flags, nil) == SQLITE_OK else {
            let err = cursorDb.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            Log.cursor.warning("Failed to open Cursor state DB: \(err, privacy: .public)")
            return SyncResult()
        }
        defer { sqlite3_close(cursorDb) }

        // Query all composerData entries
        let sql = "SELECT key, value FROM cursorDiskKV WHERE key LIKE 'composerData:%'"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(cursorDb, sql, -1, &stmt, nil) == SQLITE_OK else {
            let err = String(cString: sqlite3_errmsg(cursorDb!))
            Log.cursor.warning("Failed to query composerData: \(err, privacy: .public)")
            return SyncResult()
        }
        defer { sqlite3_finalize(stmt) }

        var result = SyncResult()

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let keyPtr = sqlite3_column_text(stmt, 0) else { continue }
            let key = String(cString: keyPtr)

            // Extract composerId from key "composerData:<uuid>"
            let composerId = String(key.dropFirst("composerData:".count))

            // Read the blob/text value
            guard let valueBytes = sqlite3_column_blob(stmt, 1) else { continue }
            let valueLength = Int(sqlite3_column_bytes(stmt, 1))
            let valueData = Data(bytes: valueBytes, count: valueLength)

            guard let json = try? JSONSerialization.jsonObject(with: valueData) as? [String: Any] else {
                continue
            }

            result.total += 1

            // Extract timestamps (milliseconds → seconds)
            let createdAtMs = (json["createdAt"] as? Int64) ?? Int64(json["createdAt"] as? Double ?? 0)
            let lastUpdatedAtMs = (json["lastUpdatedAt"] as? Int64) ?? Int64(json["lastUpdatedAt"] as? Double ?? 0)
            let createdAtSec = createdAtMs / 1000
            let lastUpdatedAtSec = lastUpdatedAtMs / 1000

            // Skip conversations created before the start date
            if createdAtSec < since {
                result.skipped += 1
                continue
            }

            let cachePath = "cursor:\(composerId)"
            let cached = db.get(cachePath)

            // Use lastUpdatedAt (seconds) for change detection via fileSize field
            if let cached, cached.fileSize == UInt64(lastUpdatedAtSec) {
                result.skipped += 1
                continue
            }

            let oldScore = cached?.score ?? TokenScore()

            // Use one representation per composer to avoid double counting.
            // Newer Cursor builds store totals on bubble rows; older builds keep
            // the conversation inline on the composerData record.
            let hasHeaders = (json["fullConversationHeadersOnly"] as? [[String: Any]])?.isEmpty == false
            let hasInlineConv = (json["conversation"] as? [[String: Any]])?.isEmpty == false

            let newScore: TokenScore
            if hasHeaders {
                newScore = sumBubbleTokens(cursorDb: cursorDb!, composerId: composerId)
            } else if hasInlineConv {
                newScore = extractInlineTokens(from: json)
            } else {
                // Empty conversation — try bubbles as fallback
                newScore = sumBubbleTokens(cursorDb: cursorDb!, composerId: composerId)
            }

            db.upsert(
                path: cachePath,
                fileSize: UInt64(lastUpdatedAtSec),
                modifiedAt: createdAtSec,
                score: newScore,
                source: "cursor"
            )

            result.delta = result.delta.adding(newScore).subtracting(oldScore)
            result.parsed += 1

            Log.cursor.debug(
                "\(composerId.prefix(8), privacy: .public): in=\(newScore.inputTokens), out=\(newScore.outputTokens)"
            )
        }

        return result
    }

    /// Sums token usage from `bubbleId:<composerId>:*` entries (new format).
    ///
    /// Each bubble stores `tokenCount: { inputTokens: N, outputTokens: N }`.
    /// We sum across all bubbles for the conversation total.
    private func sumBubbleTokens(cursorDb: OpaquePointer, composerId: String) -> TokenScore {
        let pattern = "bubbleId:\(composerId):%"
        let sql = "SELECT value FROM cursorDiskKV WHERE key LIKE ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(cursorDb, sql, -1, &stmt, nil) == SQLITE_OK else {
            let err = String(cString: sqlite3_errmsg(cursorDb))
            Log.cursor.warning("Failed to query bubbles for \(composerId.prefix(8), privacy: .public): \(err, privacy: .public)")
            return TokenScore()
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)

        var totalInput = 0
        var totalOutput = 0
        var bubbleCount = 0

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let valueBytes = sqlite3_column_blob(stmt, 0) else { continue }
            let valueLength = Int(sqlite3_column_bytes(stmt, 0))
            let valueData = Data(bytes: valueBytes, count: valueLength)

            guard let json = try? JSONSerialization.jsonObject(with: valueData) as? [String: Any] else {
                continue
            }

            bubbleCount += 1

            if let tokenCount = json["tokenCount"] as? [String: Any] {
                totalInput += tokenCount["inputTokens"] as? Int ?? 0
                totalOutput += tokenCount["outputTokens"] as? Int ?? 0
            }
        }

        Log.cursor.debug(
            "\(composerId.prefix(8), privacy: .public): summed \(bubbleCount) bubbles — in=\(totalInput), out=\(totalOutput)"
        )

        return TokenScore(
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0
        )
    }

    /// Extracts token usage from old-format composerData with inline conversation.
    ///
    /// - `tokenCount` (int) provides approximate input/context tokens
    /// - Output tokens are estimated from assistant message text (~4 chars per token)
    private func extractInlineTokens(from json: [String: Any]) -> TokenScore {
        let inputTokens = json["tokenCount"] as? Int ?? 0

        var estimatedOutputTokens = 0
        if let conversation = json["conversation"] as? [[String: Any]] {
            for bubble in conversation {
                // type 2 = assistant message
                guard let type = bubble["type"] as? Int, type == 2 else { continue }

                // Check for per-bubble tokenCount dict (newer inline format)
                if let tokenCount = bubble["tokenCount"] as? [String: Any] {
                    let bubbleOutput = tokenCount["outputTokens"] as? Int ?? 0
                    if bubbleOutput > 0 {
                        estimatedOutputTokens += bubbleOutput
                        continue
                    }
                }

                // Fall back to text estimation
                if let text = bubble["text"] as? String, !text.isEmpty {
                    estimatedOutputTokens += text.count / 4
                }
            }
        }

        return TokenScore(
            inputTokens: inputTokens,
            outputTokens: estimatedOutputTokens,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            reasoningTokens: 0
        )
    }
}
