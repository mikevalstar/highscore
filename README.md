# HighScore

A native macOS menubar app that tracks your AI token usage and displays it as a retro seven-segment score counter. Currently reads from Claude Code; will eventually become an idle RPG powered by your AI usage.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ (ships with Xcode 15+)

## Quick Start

```bash
swift build
swift run HighScore
```

Look for the trophy icon in your menubar. Click it to see your score.

## What It Does

- Reads Claude Code conversation files from `~/.claude/projects/` and totals up all token usage (input, output, cache read, cache creation)
- Displays the running total in a retro seven-segment display that ticks up in real-time when AI is active
- Optional always-on-top overlay HUD (toggle from the menubar, configure position/size/opacity in Settings)
- Persists scores in a local SQLite database (`~/Library/Application Support/HighScore/scores.db`) so startup is instant and deleted conversation files keep their scores

## Build Commands

| Command | Description |
|---|---|
| `swift build` | Debug build |
| `swift run HighScore` | Build and launch |
| `swift build -c release` | Optimized release build |
| `open Package.swift` | Open in Xcode |

## Viewing Logs

The app logs extensively via `os.Logger` for debuggability:

```bash
# Live stream
/usr/bin/log stream --predicate 'subsystem == "com.highscore.app"' --info --style compact

# With per-file detail
/usr/bin/log show --predicate 'subsystem == "com.highscore.app"' --last 60s --info --debug --style compact
```

## Roadmap

See [plan.md](plan.md) for the full phased roadmap, from score polish to idle RPG mechanics.
