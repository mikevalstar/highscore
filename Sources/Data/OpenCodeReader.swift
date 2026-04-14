import Foundation
import SQLite3

/// Reads OpenCode token usage from the global SQLite database.
///
/// OpenCode stores its DB at `~/.local/share/opencode/opencode.db`. Token usage
/// is embedded as JSON in the `message.data` column on assistant messages:
/// ```json
/// { "tokens": { "input": N, "output": N, "cache": { "read": N, "write": N } } }
/// ```
///
/// Each session's token totals are persisted into the shared `ScoreDatabase` with
/// path `opencode:<session_id>`, so data survives even if the user clears their
/// OpenCode database. Change detection uses session `time_updated` — only sessions
/// with new activity get re-summed.
final class OpenCodeReader: TokenReader, Sendable {
    let name = "OpenCode"

    private let db: ScoreDatabase

    init(db: ScoreDatabase) {
        self.db = db
        Log.opencode.info("OpenCodeReader initialized")
    }

    /// Watch the containing directory, not the DB file — SQLite WAL/SHM sidecar
    /// files get all the churn during writes while the main .db may not change
    /// mtime for a while. Directory-level events catch all of them.
    var watchPaths: [String] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
            ?? homeDir.appendingPathComponent(".local/share").path
        return [(xdgDataHome as NSString).appendingPathComponent("opencode")]
    }

    func readUsage(since: Int64 = 0) -> TokenScore {
        let start = CFAbsoluteTimeGetCurrent()

        // Our DB is the durable record — start with its totals
        let dbTotal = db.totalScore(since: since, source: "opencode")

        let opencodeDbs = findOpenCodeDatabases()
        if opencodeDbs.isEmpty {
            Log.opencode.debug("No OpenCode databases found — returning cached total")
            return dbTotal
        }

        var parsedSessions = 0
        var skippedSessions = 0
        var totalSessions = 0
        var deltaScore = TokenScore()

        for dbPath in opencodeDbs {
            let result = syncSessions(from: dbPath, since: since)
            parsedSessions += result.parsed
            skippedSessions += result.skipped
            totalSessions += result.total
            deltaScore = deltaScore.adding(result.delta)
        }

        let finalScore = dbTotal.adding(deltaScore)

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let elapsedStr = String(format: "%.1f", elapsed)
        Log.opencode.notice(
            "Scan complete: \(totalSessions) sessions, \(parsedSessions) parsed, \(skippedSessions) cached, \(elapsedStr, privacy: .public)ms elapsed"
        )
        Log.opencode.notice(
            "Totals — in: \(finalScore.inputTokens), out: \(finalScore.outputTokens), cacheRead: \(finalScore.cacheReadTokens), cacheCreate: \(finalScore.cacheCreationTokens), reasoning: \(finalScore.reasoningTokens)"
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

    /// Returns the path to the OpenCode database if it exists.
    private func findOpenCodeDatabases() -> [String] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let fm = FileManager.default

        let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
            ?? homeDir.appendingPathComponent(".local/share").path
        let dbPath = (xdgDataHome as NSString)
            .appendingPathComponent("opencode/opencode.db")

        if fm.fileExists(atPath: dbPath) {
            Log.opencode.debug("Found OpenCode DB at \(dbPath, privacy: .public)")
            return [dbPath]
        }

        Log.opencode.debug("No OpenCode DB found at \(dbPath, privacy: .public)")
        return []
    }

    /// Syncs session-level token totals from an OpenCode DB into our ScoreDatabase.
    ///
    /// For each session: if `time_updated` hasn't changed, skip it (cached).
    /// Otherwise, sum that session's message tokens and upsert into file_scores
    /// with path `opencode:<session_id>`.
    private func syncSessions(from dbPath: String, since: Int64) -> SyncResult {
        var ocDb: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbPath, &ocDb, flags, nil) == SQLITE_OK else {
            let err = ocDb.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            Log.opencode.warning("Failed to open OpenCode DB at \(dbPath, privacy: .public): \(err, privacy: .public)")
            return SyncResult()
        }
        defer { sqlite3_close(ocDb) }

        // List all sessions with their timestamps (ms)
        let listSql = "SELECT id, time_created, time_updated FROM session"
        var listStmt: OpaquePointer?
        guard sqlite3_prepare_v2(ocDb, listSql, -1, &listStmt, nil) == SQLITE_OK else {
            let err = String(cString: sqlite3_errmsg(ocDb!))
            Log.opencode.warning("Failed to list sessions: \(err, privacy: .public)")
            return SyncResult()
        }
        defer { sqlite3_finalize(listStmt) }

        var result = SyncResult()

        while sqlite3_step(listStmt) == SQLITE_ROW {
            let sessionId = String(cString: sqlite3_column_text(listStmt, 0))
            let timeCreatedMs = sqlite3_column_int64(listStmt, 1)
            let timeUpdatedMs = sqlite3_column_int64(listStmt, 2)

            // Convert to seconds for our DB
            let timeCreatedSec = timeCreatedMs / 1000
            // Use time_updated as a change-detection value stored in file_size
            let timeUpdatedSec = timeUpdatedMs / 1000

            result.total += 1

            // Skip sessions created before the start date
            if timeCreatedSec < since {
                result.skipped += 1
                continue
            }

            let cachePath = "opencode:\(sessionId)"
            let cached = db.get(cachePath)

            // file_size stores time_updated (seconds) for change detection
            if let cached, cached.fileSize == UInt64(timeUpdatedSec) {
                result.skipped += 1
                continue
            }

            // Session is new or updated — sum its message tokens
            let oldScore = cached?.score ?? TokenScore()
            let newScore = sumSessionTokens(ocDb: ocDb!, sessionId: sessionId)

            // modified_at = time_created so totalScore(since:) filters correctly
            db.upsert(
                path: cachePath,
                fileSize: UInt64(timeUpdatedSec),
                modifiedAt: timeCreatedSec,
                score: newScore,
                source: "opencode"
            )

            result.delta = result.delta.adding(newScore).subtracting(oldScore)
            result.parsed += 1

            Log.opencode.debug(
                "Session \(sessionId, privacy: .public): in=\(newScore.inputTokens), out=\(newScore.outputTokens), cacheRead=\(newScore.cacheReadTokens), cacheWrite=\(newScore.cacheCreationTokens), reasoning=\(newScore.reasoningTokens)"
            )
        }

        return result
    }

    /// Sums token usage across all assistant messages in a single session.
    private func sumSessionTokens(ocDb: OpaquePointer, sessionId: String) -> TokenScore {
        let sql = """
            SELECT COALESCE(SUM(json_extract(data, '$.tokens.input')), 0),
                   COALESCE(SUM(json_extract(data, '$.tokens.output')), 0),
                   COALESCE(SUM(json_extract(data, '$.tokens.cache.read')), 0),
                   COALESCE(SUM(json_extract(data, '$.tokens.cache.write')), 0),
                   COALESCE(SUM(json_extract(data, '$.tokens.reasoning')), 0)
            FROM message
            WHERE session_id = ?
              AND json_extract(data, '$.role') = 'assistant'
              AND json_extract(data, '$.tokens') IS NOT NULL
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(ocDb, sql, -1, &stmt, nil) == SQLITE_OK else {
            let err = String(cString: sqlite3_errmsg(ocDb))
            Log.opencode.warning("Failed to prepare session token query: \(err, privacy: .public)")
            return TokenScore()
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return TokenScore()
        }

        return TokenScore(
            inputTokens: Int(sqlite3_column_int64(stmt, 0)),
            outputTokens: Int(sqlite3_column_int64(stmt, 1)),
            cacheReadTokens: Int(sqlite3_column_int64(stmt, 2)),
            cacheCreationTokens: Int(sqlite3_column_int64(stmt, 3)),
            reasoningTokens: Int(sqlite3_column_int64(stmt, 4))
        )
    }
}
