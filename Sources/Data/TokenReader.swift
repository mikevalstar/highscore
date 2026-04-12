import Foundation

/// Common interface for all AI tool token usage readers.
///
/// Each reader scans a specific tool's local data (JSONL files, SQLite DBs, etc.)
/// and returns accumulated token usage. Readers use the shared `ScoreDatabase` to
/// cache file state and avoid redundant parsing on warm startup.
///
/// Conforming types must be `Sendable` — they are called from background threads.
protocol TokenReader: Sendable {
    /// Human-readable name for logging and UI (e.g., "Claude Code", "OpenCode").
    var name: String { get }

    /// Read token usage from this tool's local data.
    ///
    /// - Parameter since: Unix timestamp (seconds). Sources modified before this are skipped.
    /// - Returns: Accumulated token score across all sessions/files for this tool.
    func readUsage(since: Int64) -> TokenScore
}
