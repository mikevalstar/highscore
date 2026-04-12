# Cursor Data Source

## File Location
```
~/Library/Application Support/Cursor/User/globalStorage/state.vscdb
```

## Database Type
SQLite

## Database Size
~77 MB

## Schema Overview

| Table | Purpose |
|-------|---------|
| `ItemTable` | VS Code/Cursor settings (UI state, telemetry, preferences) |
| `cursorDiskKV` | Main Cursor state (conversations, code edits, context) |

## Key Patterns in `cursorDiskKV`

| Key Pattern | Count | Purpose |
|-------------|-------|---------|
| `composerData:<uuid>` | 196 | Chat conversations/composers |
| `bubbleId:<composer>:<bubble>` | 2,334 | Individual message bubbles |
| `checkpointId:<uuid>` | - | Code checkpoint data |
| `codeBlockDiff:<uuid>` | - | Code block diffs |
| `agentKv:<key>` | - | Agent key-value data |
| `messageRequestContext:<uuid>` | - | Request context |
| `ofsContent:<uuid>` | - | Content data |

## Data Structure

### Token Fields Found

| Field | Location | Type | Description |
|-------|----------|------|-------------|
| `inputTokens` | `tokenCount.inputTokens` | Int | Input tokens |
| `outputTokens` | `tokenCount.outputTokens` | Int | Output tokens |
| `tokenCountUpUntilHere` | `tokenCountUpUntilHere` | - | Cumulative token count |
| `tokenDetailsUpUntilHere` | `tokenDetailsUpUntilHere` | - | Per-file breakdown |

### Fields NOT Found

- `cache_read_input_tokens` - **NOT STORED**
- `cache_creation_input_tokens` - **NOT STORED**
- `input_tokens` at top level
- `output_tokens` at top level
- `reasoning_tokens` - **NOT STORED**

### Composer Data Example
```json
{
  "type": 2,
  "tokenCount": {
    "inputTokens": 11286,
    "outputTokens": 1650
  },
  "text": "I've made several improvements to the styling..."
}
```

## Statistics

| Metric | Value |
|--------|-------|
| Total conversation items | 828 |
| Items with `tokenCount` field | 197 (23.8%) |
| Items with **non-zero** tokens | 27 (**3.3%**) |
| Items with `tokenDetailsUpUntilHere` | 135 (16.3%) |

## Sample Non-Zero Token Data

| inputTokens | outputTokens | Use Case |
|-------------|--------------|----------|
| 11,286 | 1,650 | Slack bot memory functionality |
| 11,135 | 2,289 | Creating a TODO list page |
| 9,986 | 2,080 | Creating core-memory API endpoint |
| 6,399 | 2,036 | Logging configuration changes |
| 4,641 | 1,419 | Server logging with pino |

## Data Completeness

| Token Type | Available | Notes |
|------------|-----------|-------|
| Input Tokens | ⚠️ Partial | Only in composerData, sparse (3.3% non-zero) |
| Output Tokens | ⚠️ Partial | Only in composerData, sparse (3.3% non-zero) |
| Cache Read Tokens | ❌ No | Not stored by Cursor |
| Cache Creation Tokens | ❌ No | Not stored by Cursor |
| Reasoning Tokens | ❌ No | Not stored by Cursor |

## Data Quality Assessment

**Overall: POOR - Not viable for comprehensive token tracking**

### Critical Limitations

1. **97% of tokenCount values are zero** - Most messages have no token data
2. **No prompt caching tracking** - Cache token fields completely absent
3. **`usageData` only tracks cost** - Contains `costInCents` but no token breakdown
4. **Cannot calculate accurate ratios** - Too sparse to be meaningful
5. **Agent/composer mode only** - Chat mode records 0 tokens

### Notes

- Only agent/composer mode populates token counts - chat mode records 0
- Older format stored inline `conversation` array with context `tokenCount`
- Token counts may only be present for certain interaction types

## Parsing Strategy

- Query `cursorDiskKV` for `composerData:*` keys
- Parse `tokenCount.inputTokens` and `tokenCount.outputTokens`
- Filter out zero values
- **Do not rely on this as primary data source** - data is too sparse

## Recommendation

The Cursor `state.vscdb` database is **not a viable source** for comprehensive token usage tracking due to:
- Extreme sparsity (97% zero)
- No cache token tracking
- No reasoning token tracking

Use Claude Code JSONL files as the primary reliable method for token tracking.

## Last Updated
2026-04-12