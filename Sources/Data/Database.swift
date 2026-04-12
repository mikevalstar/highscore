import Foundation
import SQLite3

/// SQLite-backed persistent store for file scan state.
///
/// Schema:
///   file_scores(
///     path           TEXT PRIMARY KEY,
///     file_size      INTEGER NOT NULL,
///     modified_at    INTEGER NOT NULL,     -- file mtime as Unix timestamp (seconds)
///     scanned_at     INTEGER NOT NULL,     -- when we last parsed this file (seconds)
///     input_tokens   INTEGER NOT NULL DEFAULT 0,
///     output_tokens  INTEGER NOT NULL DEFAULT 0,
///     cache_read     INTEGER NOT NULL DEFAULT 0,
///     cache_creation INTEGER NOT NULL DEFAULT 0
///   )
///
/// Thread safety: all access is serialized through an internal lock.
/// The database file lives at ~/Library/Application Support/HighScore/scores.db
final class ScoreDatabase: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var db: OpaquePointer?

    init() {
        let dbPath = Self.databasePath()
        Log.app.info("Opening database at \(dbPath, privacy: .public)")

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            let err = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            Log.app.error("Failed to open database: \(err, privacy: .public)")
            db = nil
            return
        }

        // WAL mode for better concurrent read performance
        exec("PRAGMA journal_mode=WAL")
        // Relaxed sync — we can rebuild from files if the DB corrupts
        exec("PRAGMA synchronous=NORMAL")

        createTables()
        Log.app.info("Database ready")
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Public API

    struct FileEntry: Sendable {
        let path: String
        let fileSize: UInt64
        let modifiedAt: Int64  // Unix timestamp in seconds
        let scannedAt: Int64
        let score: TokenScore
    }

    /// Look up a file's cached state. Returns nil if not in the DB.
    func get(_ path: String) -> FileEntry? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }

        let sql = "SELECT file_size, modified_at, scanned_at, input_tokens, output_tokens, cache_read, cache_creation FROM file_scores WHERE path = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logDBError("prepare get")
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        return FileEntry(
            path: path,
            fileSize: UInt64(sqlite3_column_int64(stmt, 0)),
            modifiedAt: sqlite3_column_int64(stmt, 1),
            scannedAt: sqlite3_column_int64(stmt, 2),
            score: TokenScore(
                inputTokens: Int(sqlite3_column_int64(stmt, 3)),
                outputTokens: Int(sqlite3_column_int64(stmt, 4)),
                cacheReadTokens: Int(sqlite3_column_int64(stmt, 5)),
                cacheCreationTokens: Int(sqlite3_column_int64(stmt, 6))
            )
        )
    }

    /// Insert or update a file's cached state.
    func upsert(path: String, fileSize: UInt64, modifiedAt: Int64, score: TokenScore) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }

        let sql = """
            INSERT INTO file_scores (path, file_size, modified_at, scanned_at, input_tokens, output_tokens, cache_read, cache_creation)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                file_size = excluded.file_size,
                modified_at = excluded.modified_at,
                scanned_at = excluded.scanned_at,
                input_tokens = excluded.input_tokens,
                output_tokens = excluded.output_tokens,
                cache_read = excluded.cache_read,
                cache_creation = excluded.cache_creation
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logDBError("prepare upsert")
            return
        }
        defer { sqlite3_finalize(stmt) }

        let now = Int64(Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 2, Int64(fileSize))
        sqlite3_bind_int64(stmt, 3, modifiedAt)
        sqlite3_bind_int64(stmt, 4, now)
        sqlite3_bind_int64(stmt, 5, Int64(score.inputTokens))
        sqlite3_bind_int64(stmt, 6, Int64(score.outputTokens))
        sqlite3_bind_int64(stmt, 7, Int64(score.cacheReadTokens))
        sqlite3_bind_int64(stmt, 8, Int64(score.cacheCreationTokens))

        if sqlite3_step(stmt) != SQLITE_DONE {
            logDBError("step upsert")
        }
    }

    /// Load all cached scores at once (used for fast startup totals).
    func allEntries() -> [FileEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }

        let sql = "SELECT path, file_size, modified_at, scanned_at, input_tokens, output_tokens, cache_read, cache_creation FROM file_scores"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logDBError("prepare allEntries")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var entries: [FileEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = String(cString: sqlite3_column_text(stmt, 0))
            entries.append(FileEntry(
                path: path,
                fileSize: UInt64(sqlite3_column_int64(stmt, 1)),
                modifiedAt: sqlite3_column_int64(stmt, 2),
                scannedAt: sqlite3_column_int64(stmt, 3),
                score: TokenScore(
                    inputTokens: Int(sqlite3_column_int64(stmt, 4)),
                    outputTokens: Int(sqlite3_column_int64(stmt, 5)),
                    cacheReadTokens: Int(sqlite3_column_int64(stmt, 6)),
                    cacheCreationTokens: Int(sqlite3_column_int64(stmt, 7))
                )
            ))
        }
        return entries
    }

    /// Sum all scores across every tracked file (including deleted ones — running total).
    /// When `since` is provided, only files with `modified_at >= since` are included.
    func totalScore(since: Int64 = 0) -> TokenScore {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return TokenScore() }

        let sql = "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0), COALESCE(SUM(cache_creation),0) FROM file_scores WHERE modified_at >= ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logDBError("prepare totalScore")
            return TokenScore()
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, since)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return TokenScore()
        }

        return TokenScore(
            inputTokens: Int(sqlite3_column_int64(stmt, 0)),
            outputTokens: Int(sqlite3_column_int64(stmt, 1)),
            cacheReadTokens: Int(sqlite3_column_int64(stmt, 2)),
            cacheCreationTokens: Int(sqlite3_column_int64(stmt, 3))
        )
    }

    /// Number of tracked files.
    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return 0 }

        let sql = "SELECT COUNT(*) FROM file_scores"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        sqlite3_step(stmt)
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - Private

    // MARK: - Daily Snapshots

    /// Returns the snapshot for a given date string (YYYY-MM-DD), or nil if none exists.
    func getSnapshot(date: String) -> TokenScore? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }

        let sql = "SELECT input_tokens, output_tokens, cache_read, cache_creation FROM daily_snapshots WHERE date = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logDBError("prepare getSnapshot")
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        return TokenScore(
            inputTokens: Int(sqlite3_column_int64(stmt, 0)),
            outputTokens: Int(sqlite3_column_int64(stmt, 1)),
            cacheReadTokens: Int(sqlite3_column_int64(stmt, 2)),
            cacheCreationTokens: Int(sqlite3_column_int64(stmt, 3))
        )
    }

    /// Saves a snapshot for a given date. Does not overwrite if one already exists.
    func saveSnapshotIfNeeded(date: String, score: TokenScore) {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }

        let sql = """
            INSERT OR IGNORE INTO daily_snapshots (date, input_tokens, output_tokens, cache_read, cache_creation)
            VALUES (?, ?, ?, ?, ?)
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logDBError("prepare saveSnapshot")
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 2, Int64(score.inputTokens))
        sqlite3_bind_int64(stmt, 3, Int64(score.outputTokens))
        sqlite3_bind_int64(stmt, 4, Int64(score.cacheReadTokens))
        sqlite3_bind_int64(stmt, 5, Int64(score.cacheCreationTokens))

        if sqlite3_step(stmt) != SQLITE_DONE {
            logDBError("step saveSnapshot")
        }
    }

    // MARK: - Private

    private func createTables() {
        exec("""
            CREATE TABLE IF NOT EXISTS file_scores (
                path           TEXT PRIMARY KEY,
                file_size      INTEGER NOT NULL,
                modified_at    INTEGER NOT NULL,
                scanned_at     INTEGER NOT NULL,
                input_tokens   INTEGER NOT NULL DEFAULT 0,
                output_tokens  INTEGER NOT NULL DEFAULT 0,
                cache_read     INTEGER NOT NULL DEFAULT 0,
                cache_creation INTEGER NOT NULL DEFAULT 0
            )
            """)
        exec("""
            CREATE TABLE IF NOT EXISTS daily_snapshots (
                date           TEXT PRIMARY KEY,
                input_tokens   INTEGER NOT NULL DEFAULT 0,
                output_tokens  INTEGER NOT NULL DEFAULT 0,
                cache_read     INTEGER NOT NULL DEFAULT 0,
                cache_creation INTEGER NOT NULL DEFAULT 0
            )
            """)
    }

    private func exec(_ sql: String) {
        // Caller must hold the lock (or this is called from init)
        guard let db else { return }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let err = errMsg.map { String(cString: $0) } ?? "unknown"
            Log.app.error("SQL error: \(err, privacy: .public) for: \(sql, privacy: .public)")
            sqlite3_free(errMsg)
        }
    }

    private func logDBError(_ context: String) {
        guard let db else { return }
        let err = String(cString: sqlite3_errmsg(db))
        Log.app.error("DB error [\(context, privacy: .public)]: \(err, privacy: .public)")
    }

    private static func databasePath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("HighScore")

        try? FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )

        return appSupport.appendingPathComponent("scores.db").path
    }
}
