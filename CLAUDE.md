# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
swift build          # compile (~2s incremental)
swift run HighScore  # build + launch (menubar app — look for trophy icon)
swift build -c release  # optimized build
swift build 2>&1 | grep -E 'error:|warning:'  # quick check for errors only
```

No Xcode project required. Open `Package.swift` in Xcode if you want the IDE.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/) for all commit messages (e.g., `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`).

## Viewing Logs

The app uses `os.Logger` (subsystem: `com.highscore.app`). Categories: `app`, `scores`, `reader`, `overlay`, `settings`.

```bash
# Live stream
/usr/bin/log stream --predicate 'subsystem == "com.highscore.app"' --info --style compact

# Recent history (include --debug for per-file detail)
/usr/bin/log show --predicate 'subsystem == "com.highscore.app"' --last 60s --info --debug --style compact
```

Use `/usr/bin/log` (full path) to avoid shell alias conflicts.

## Architecture

This is a **menubar-only macOS app** (SwiftUI, no dock icon) that reads AI token usage from local files and displays a running total.

### Data flow

1. **ClaudeCodeReader** scans `~/.claude/projects/*/*.jsonl` on a background thread (`Task.detached`). Uses a fast `line.contains("input_tokens")` pre-filter to skip ~90% of lines before JSON parsing. Supports incremental reads (only parses appended bytes when a file grows).

2. **ScoreDatabase** (SQLite via C API, `~/Library/Application Support/HighScore/scores.db`) persists per-file state: path, file_size, modified_at (integer seconds), and accumulated token counts. On warm startup the DB provides instant scores — only files with changed size or mtime get re-parsed.

3. **ScoreManager** (`@MainActor`, `ObservableObject`) orchestrates: loads cached total from DB on init (instant display), runs a 5-second background refresh timer, and a 30fps tick timer that animates `displayScore` toward the real `totalScore`.

4. **UI layer**: `MenuBarExtra` popover with seven-segment score display, token breakdown bars, overlay toggle, and settings button. The overlay is an `NSPanel` (always-on-top, transparent, click-through).

### Key design decisions

- **Scores are a running total** — deleted JSONL files keep their scores in the DB (never pruned). This is intentional.
- **File change detection** uses both `file_size` AND `modified_at` (truncated to seconds to avoid float precision issues with SQLite).
- **No dependencies** — SQLite3 comes with macOS, UI is pure SwiftUI/AppKit.
- Settings persist via `@AppStorage` (UserDefaults). The overlay syncs with settings changes through `UserDefaults.didChangeNotification`.
- The app switches activation policy between `.accessory` (menubar-only) and `.regular` (shows in dock) when the settings window opens/closes.

## Logging Policy

This project prioritizes extensive logging for AI-assisted debugging. Every meaningful operation should emit a log line via `os.Logger` (see `Log.swift` for categories). When adding new features or modifying existing ones:

- Log at `notice` level for key state transitions, timing, and results that should always be visible (e.g., scan complete, score updated, DB operations).
- Log at `info` level for lifecycle events (init, wiring, window open/close).
- Log at `debug` level for per-item detail (per-file parse stats, position updates).
- Include timing (`CFAbsoluteTimeGetCurrent`) for any I/O or computation that could be slow.
- Include counts and deltas so the log stream tells the full story without needing a debugger.
- Use `privacy: .public` for formatted strings that would otherwise show as `<private>` in Console.app.
- Add a new `Logger` category in `Log.swift` when adding a new subsystem area.

The goal: an AI agent reading the log output should be able to diagnose any issue without access to a debugger.

## Data Source Format

Claude Code JSONL files contain one JSON object per line. Usage data lives at `message.usage` (or top-level `usage`) with fields: `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`.

- **Data source (Cursor)**: SQLite DB at `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` — conversation data in `cursorDiskKV` table under `composerData:<uuid>` keys. `tokenCount` provides approximate input/context tokens; output tokens are estimated from assistant message text (~4 chars/token). No exact API-level token counts are stored locally by Cursor.
