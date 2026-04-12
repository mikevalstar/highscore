import Foundation
import SQLite3

/// SQLite-backed persistent store for file scan state.
///
/// Schema:
///   file_scores(
///     path           TEXT PRIMARY KEY,
///     source         TEXT NOT NULL DEFAULT 'claude',  -- reader source identifier
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

        runMigrations()
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
        let source: String     // reader source identifier (e.g., "claude", "opencode")
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

        let sql = "SELECT source, file_size, modified_at, scanned_at, input_tokens, output_tokens, cache_read, cache_creation FROM file_scores WHERE path = ?"
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
            source: String(cString: sqlite3_column_text(stmt, 0)),
            fileSize: UInt64(sqlite3_column_int64(stmt, 1)),
            modifiedAt: sqlite3_column_int64(stmt, 2),
            scannedAt: sqlite3_column_int64(stmt, 3),
            score: TokenScore(
                inputTokens: Int(sqlite3_column_int64(stmt, 4)),
                outputTokens: Int(sqlite3_column_int64(stmt, 5)),
                cacheReadTokens: Int(sqlite3_column_int64(stmt, 6)),
                cacheCreationTokens: Int(sqlite3_column_int64(stmt, 7))
            )
        )
    }

    /// Insert or update a file's cached state.
    func upsert(path: String, fileSize: UInt64, modifiedAt: Int64, score: TokenScore, source: String = "claude") {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return }

        let sql = """
            INSERT INTO file_scores (path, source, file_size, modified_at, scanned_at, input_tokens, output_tokens, cache_read, cache_creation)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                source = excluded.source,
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
        sqlite3_bind_text(stmt, 2, (source as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 3, Int64(fileSize))
        sqlite3_bind_int64(stmt, 4, modifiedAt)
        sqlite3_bind_int64(stmt, 5, now)
        sqlite3_bind_int64(stmt, 6, Int64(score.inputTokens))
        sqlite3_bind_int64(stmt, 7, Int64(score.outputTokens))
        sqlite3_bind_int64(stmt, 8, Int64(score.cacheReadTokens))
        sqlite3_bind_int64(stmt, 9, Int64(score.cacheCreationTokens))

        if sqlite3_step(stmt) != SQLITE_DONE {
            logDBError("step upsert")
        }
    }

    /// Load all cached scores at once (used for fast startup totals).
    func allEntries() -> [FileEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return [] }

        let sql = "SELECT path, source, file_size, modified_at, scanned_at, input_tokens, output_tokens, cache_read, cache_creation FROM file_scores"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logDBError("prepare allEntries")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var entries: [FileEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path = String(cString: sqlite3_column_text(stmt, 0))
            let source = String(cString: sqlite3_column_text(stmt, 1))
            entries.append(FileEntry(
                path: path,
                source: source,
                fileSize: UInt64(sqlite3_column_int64(stmt, 2)),
                modifiedAt: sqlite3_column_int64(stmt, 3),
                scannedAt: sqlite3_column_int64(stmt, 4),
                score: TokenScore(
                    inputTokens: Int(sqlite3_column_int64(stmt, 5)),
                    outputTokens: Int(sqlite3_column_int64(stmt, 6)),
                    cacheReadTokens: Int(sqlite3_column_int64(stmt, 7)),
                    cacheCreationTokens: Int(sqlite3_column_int64(stmt, 8))
                )
            ))
        }
        return entries
    }

    /// Sum all scores across every tracked file (including deleted ones — running total).
    /// When `since` is provided, only files with `modified_at >= since` are included.
    /// When `source` is provided, only files from that reader are included.
    func totalScore(since: Int64 = 0, source: String? = nil) -> TokenScore {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return TokenScore() }

        let sql: String
        if source != nil {
            sql = "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0), COALESCE(SUM(cache_creation),0) FROM file_scores WHERE modified_at >= ? AND source = ?"
        } else {
            sql = "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(cache_read),0), COALESCE(SUM(cache_creation),0) FROM file_scores WHERE modified_at >= ?"
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logDBError("prepare totalScore")
            return TokenScore()
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, since)
        if let sourceValue = source {
            sqlite3_bind_text(stmt, 2, (sourceValue as NSString).utf8String, -1, nil)
        }

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

    // MARK: - Migration System

    /// Current schema version. Bump this and add a case to `runMigration(_:)` for each new migration.
    private static let currentVersion = 3

    /// Reads the current DB version from the env table. Returns 0 if the table doesn't exist (fresh or pre-migration DB).
    private func getDBVersion() -> Int {
        guard let db else { return 0 }
        // Check if env table exists
        var checkStmt: OpaquePointer?
        let checkSQL = "SELECT name FROM sqlite_master WHERE type='table' AND name='env'"
        guard sqlite3_prepare_v2(db, checkSQL, -1, &checkStmt, nil) == SQLITE_OK else { return 0 }
        let hasEnvTable = sqlite3_step(checkStmt) == SQLITE_ROW
        sqlite3_finalize(checkStmt)

        guard hasEnvTable else { return 0 }

        var stmt: OpaquePointer?
        let sql = "SELECT value FROM env WHERE key = 'db_version'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW,
              let valuePtr = sqlite3_column_text(stmt, 0) else { return 0 }

        return Int(String(cString: valuePtr)) ?? 0
    }

    /// Updates the stored DB version in the env table.
    private func setDBVersion(_ version: Int) {
        exec("""
            INSERT INTO env (key, value) VALUES ('db_version', '\(version)')
            ON CONFLICT(key) DO UPDATE SET value = '\(version)'
            """)
    }

    /// Runs all pending migrations from the current version up to `currentVersion`.
    private func runMigrations() {
        let startVersion = getDBVersion()
        let startTime = CFAbsoluteTimeGetCurrent()
        Log.app.info("Database version: \(startVersion), target: \(Self.currentVersion)")

        if startVersion >= Self.currentVersion {
            Log.app.info("Database schema up to date (v\(startVersion))")
            return
        }

        // Ensure the env table exists before any migration runs
        if startVersion == 0 {
            exec("""
                CREATE TABLE IF NOT EXISTS env (
                    key   TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                )
                """)
        }

        // Detect pre-migration databases that already have tables but no version tracking
        let isLegacy = startVersion == 0 && tableExists("file_scores")
        if isLegacy {
            Log.app.notice("Detected legacy database without version tracking — running upgrade migrations")
        }

        for version in (startVersion + 1)...Self.currentVersion {
            Log.app.notice("Running migration to v\(version)...")
            runMigration(version, isLegacy: isLegacy)
            setDBVersion(version)
            Log.app.notice("Migration to v\(version) complete")
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        Log.app.notice("All migrations complete (v\(startVersion) → v\(Self.currentVersion)) in \(String(format: "%.1f", elapsed * 1000))ms")
    }

    /// Executes a single migration step. Each version number corresponds to a schema change.
    private func runMigration(_ version: Int, isLegacy: Bool) {
        switch version {

        // v1: base file_scores table
        case 1:
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

        // v2: add source column to file_scores
        case 2:
            if !isLegacy || !columnExists("file_scores", column: "source") {
                exec("ALTER TABLE file_scores ADD COLUMN source TEXT NOT NULL DEFAULT 'claude'")
            }

        // v3: daily_snapshots table
        case 3:
            exec("""
                CREATE TABLE IF NOT EXISTS daily_snapshots (
                    date           TEXT PRIMARY KEY,
                    input_tokens   INTEGER NOT NULL DEFAULT 0,
                    output_tokens  INTEGER NOT NULL DEFAULT 0,
                    cache_read     INTEGER NOT NULL DEFAULT 0,
                    cache_creation INTEGER NOT NULL DEFAULT 0
                )
                """)

        default:
            Log.app.error("Unknown migration version \(version) — skipping")
        }
    }

    /// Checks whether a table exists in the database.
    private func tableExists(_ name: String) -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    /// Checks whether a column exists in a given table.
    private func columnExists(_ table: String, column: String) -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        let sql = "PRAGMA table_info(\(table))"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(stmt, 1),
               String(cString: namePtr) == column {
                return true
            }
        }
        return false
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
