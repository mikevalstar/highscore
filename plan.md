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

- [ ] Auto-refresh on a timer (poll every 30-60 seconds)
- [ ] Show per-session vs all-time scores
- [ ] Date range filtering (today / this week / all time)
- [ ] Animate score changes
- [ ] Persist cached scores so startup is fast
- [ ] Show score breakdown by project directory

## Phase 2 - Additional AI Tool Sources

- [ ] Plugin/adapter architecture for adding new sources
- [ ] Claude.ai web usage (if accessible via local data)
- [ ] ChatGPT usage (if accessible via local data)
- [ ] Cursor / Copilot usage (if accessible via local data)
- [ ] API key direct usage tracking (optional: user provides API key to check billing)

## Phase 3 - Idle RPG Mechanics

- [ ] XP system: tokens map to XP with scaling curve
- [ ] Levels: level up based on cumulative XP
- [ ] Character/avatar that evolves with level
- [ ] Achievements/badges (e.g., "First Million Tokens", "Night Owl: 10K tokens after midnight")
- [ ] Stats screen: STR (output tokens), INT (cache efficiency), DEX (sessions/day), etc.
- [ ] Daily streak tracking
- [ ] Prestige system for resetting and gaining multipliers

## Phase 4 - Overlay & Visual Flair

- [ ] Floating overlay option (always-on-top mini HUD in screen corner)
- [ ] Pixel art character display
- [ ] Level-up animations/notifications
- [ ] Achievement toast notifications
- [ ] Customizable overlay position and size
- [ ] Dark/light theme support

## Phase 5 - Persistence & Sync

- [ ] Local SQLite database for historical tracking
- [ ] Export stats as JSON/CSV
- [ ] Charts: usage over time, tokens per day/week
- [ ] Optional: iCloud sync for multi-machine tracking

## Phase 6 - Social & Fun

- [ ] Leaderboard (opt-in, anonymous)
- [ ] Share achievement cards (generate image)
- [ ] "Boss battles" — special challenges (e.g., "use 1M tokens in a day")
- [ ] Loot/item drops based on usage patterns
- [ ] Pet companion that reacts to your activity

## Technical Notes

- **Platform**: macOS 14+ (Sonoma), SwiftUI
- **Build**: Swift Package Manager (`swift build` / `swift run`)
- **Data source**: Claude Code stores conversations as JSONL in `~/.claude/projects/<project>/<session>.jsonl` — usage data is in `message.usage` with fields: `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`
- **Architecture**: `ScoreManager` (ObservableObject) orchestrates readers; each source (Claude Code, etc.) has its own reader struct
- **No Xcode project**: open `Package.swift` in Xcode if you want the IDE experience
