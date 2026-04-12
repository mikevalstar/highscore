# HighScore - AI Token Usage Idle RPG

A native macOS menubar app that tracks your AI token usage across tools and turns it into an idle RPG experience.

## Current State (v0.1 - Foundation)

- [x] Swift Package Manager project (no Xcode project needed)
- [x] Menubar icon with trophy icon
- [x] Click-to-toggle popover window
- [x] Segmented score display (input/output/cache tokens)
- [x] Claude Code usage reader (reads ~/.claude/projects/ JSONL files)
- [x] Dock-hidden (menubar-only app via `.accessory` activation policy)

## Phase 1 - Polish the Score Display

- [x] Show per-session vs all-time scores
- [x] Date range filtering (today / this week / all time)

## Phase 2 - Additional AI Tool Sources

- [x] Plugin/adapter architecture for adding new sources (`TokenReader` protocol)
- [x] Codex usage (reads `~/.codex/sessions/` rollout JSONL files with full token breakdown)
- [x] OpenCode usage (reads `.opencode/opencode.db` SQLite databases per-project)
- [x] Reasoning token tracking (supported for Codex and OpenCode sources)
- [x] Copilot CLI usage (reads `~/.copilot/session-state/<uuid>/events.jsonl` — uses `session.shutdown` totals with `assistant.message` output fallback)
- [x] Cursor usage (reads `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` — partial token coverage from composer/bubble data, no cache or reasoning fields)

## Phase 3 - Overlay & Visual Flair (1)

- [ ] Setup placeholder UI for RPG element

## Phase 4 - Idle RPG Mechanics

- [ ] XP system: tokens map to XP with scaling curve
- [ ] Levels: level up based on cumulative XP
- [ ] Character/avatar that evolves with level
- [ ] Achievements/badges (e.g., "First Million Tokens", "Night Owl: 10K tokens after midnight")
- [ ] Stats screen: STR (output tokens), INT (cache efficiency), DEX (sessions/day), etc.
- [ ] Daily streak tracking
- [ ] Prestige system for resetting and gaining multipliers

## Phase 5 - Overlay & Visual Flair (2)

- [ ] Floating overlay option (always-on-top mini HUD in screen corner)
- [ ] Pixel art character display
- [ ] Level-up animations/notifications
- [ ] Achievement toast notifications
- [ ] Customizable overlay position and size
- [ ] Dark/light theme support

## Phase 6 - Persistence & Sync

- [ ] Local SQLite database for historical tracking
- [ ] Export stats as JSON/CSV
- [ ] Charts: usage over time, tokens per day/week
- [ ] Optional: iCloud sync for multi-machine tracking

## Phase 7 - Social & Fun

- [ ] Leaderboard (opt-in, anonymous)
- [ ] Share achievement cards (generate image)
- [ ] "Boss battles" — special challenges (e.g., "use 1M tokens in a day")
- [ ] Loot/item drops based on usage patterns
- [ ] Pet companion that reacts to your activity

## Future ideas

- [ ] User-configurable custom scan folders for any reader type

## Technical Notes

- **Platform**: macOS 14+ (Sonoma), SwiftUI
- **Build**: Swift Package Manager (`swift build` / `swift run`)
- **Data source (Claude Code)**: Conversations as JSONL in `~/.claude/projects/<project>/<session>.jsonl` — usage data is in `message.usage` with fields: `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`
- **Data source (Codex)**: Rollout JSONL files in `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` — last `token_count` event per file provides `input_tokens`, `output_tokens`, `cached_input_tokens`, `reasoning_output_tokens`
- **Data source (OpenCode)**: SQLite DB at `~/.local/share/opencode/opencode.db` — token usage in `message.data` JSON: `$.tokens.{input,output,reasoning,cache.read,cache.write}`
- **Data source (Copilot CLI)**: Event JSONL files in `~/.copilot/session-state/<uuid>/events.jsonl` — `session.shutdown` provides per-session `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheWriteTokens`, and `reasoningTokens`; `assistant.message.outputTokens` is fallback-only to avoid double counting
- **Data source (Cursor)**: SQLite DB at `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` — conversation metadata in `cursorDiskKV` table under `composerData:<uuid>` keys; per-bubble token counts (`inputTokens`, `outputTokens`) in `bubbleId:<composerId>:<bubbleId>` entries. Older format stores inline `conversation` array with context `tokenCount`. Use one representation per composer to avoid double counting. Note: only some agent/composer workflows populate meaningful token counts, and Cursor does not expose cache or reasoning fields locally.
- **Architecture**: `ScoreManager` (ObservableObject) orchestrates readers; each source (Claude Code, etc.) has its own reader struct
- **No Xcode project**: open `Package.swift` in Xcode if you want the IDE experience
