# HighScore

A native macOS menubar app that tracks your AI token usage and displays it as a retro seven-segment score counter. It reads local usage data from Claude Code, Codex, OpenCode, Copilot CLI, and Cursor, then turns that into one combined score.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ (ships with Xcode 15+)

## Quick Start

```bash
swift build
swift run HighScore
```

Look for the trophy icon in your menubar. Click it to see your score.

## Installing a Release Build

Release builds from the [Releases page](https://github.com/mikevalstar/highscore/releases) are **ad-hoc signed but not notarized** (notarization requires a paid Apple Developer account). On first launch, macOS will refuse to open the app. Pick one of the two workarounds below.

### Option 1 — System Settings (recommended)

1. Unzip `HighScore.zip` and move `HighScore.app` into `/Applications`.
2. Double-click it. You'll see *"Apple could not verify 'HighScore' is free of malware."* Click **Done**.
3. Open **System Settings → Privacy & Security**, scroll down, and you'll see *"HighScore was blocked to protect your Mac."* Click **Open Anyway**.
4. Authenticate with your password or Touch ID.
5. Launch HighScore again — this time the dialog has an **Open** button. Click it. macOS remembers the approval from here on.

### Option 2 — Strip the quarantine attribute

If you'd rather skip the settings dance, run this once after moving the app into place:

```bash
xattr -dr com.apple.quarantine /Applications/HighScore.app
```

That removes the "downloaded from the internet" flag so Gatekeeper stops prompting. The app will then open normally on double-click.

### Why any of this is necessary

macOS requires apps to be either code-signed by a registered Apple Developer and notarized, or explicitly approved by the user. HighScore is an open-source hobby project without a paid developer account, so distribution relies on the user-approval path. The app is ad-hoc signed (enough to satisfy the Apple Silicon signature requirement) but intentionally not notarized.

## What It Does

- Reads local token usage from Claude Code, Codex, OpenCode, Copilot CLI, and Cursor
- Uses the most complete source available per tool and avoids double counting overlapping session totals
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
/usr/bin/log stream --predicate 'subsystem == "org.mikevalstar.highscore"' --info --style compact

# With per-file detail
/usr/bin/log show --predicate 'subsystem == "org.mikevalstar.highscore"' --last 60s --info --debug --style compact
```

## Roadmap

See [plan.md](plan.md) for the full phased roadmap, from score polish to idle RPG mechanics.
