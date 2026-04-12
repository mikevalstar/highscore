# Codex Data Source

## File Location
```
~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
```

Example full path:
```
~/.codex/sessions/2026/04/12/rollout-2026-04-12T10-18-32-019d820e-f7c4-75c2-92d4-958cdffeeaf8.jsonl
```

## File Format
JSONL (one JSON object per line, newline-delimited)

## Session Directory Structure
- Sessions organized by date: `YYYY/MM/DD/`
- Each file named: `rollout-YYYY-MM-DDTHH-MM-SS-<uuid>.jsonl`
- Files within a session accumulate token data over time

## Event Types

The Codex JSONL contains various event types, but the primary token data is in `token_count` events.

| Event Type | Contains Token Data |
|------------|---------------------|
| `token_count` | ✅ Yes |
| `context_write` | No |
| `model_request` | No |
| `error` | No |

## Data Structure

### `token_count` Event (Primary Token Source)

```json
{
  "timestamp": "2026-04-12T14:18:37.370Z",
  "type": "event_msg",
  "payload": {
    "type": "token_count",
    "info": {
      "total_token_usage": {
        "input_tokens": 10917,
        "cached_input_tokens": 9472,
        "output_tokens": 29,
        "reasoning_output_tokens": 14,
        "total_tokens": 10946
      },
      "last_token_usage": {
        "input_tokens": 10917,
        "cached_input_tokens": 9472,
        "output_tokens": 29,
        "reasoning_output_tokens": 14,
        "total_tokens": 10946
      },
      "model_context_window": 258400
    },
    "rate_limits": {
      "limit_id": "codex",
      "limit_name": null,
      "primary": {
        "used_percent": 1.0,
        "window_minutes": 300,
        "resets_at": 1776021515
      },
      "secondary": {
        "used_percent": 0.0,
        "window_minutes": 10080,
        "resets_at": 1776608315
      },
      "credits": null,
      "plan_type": "plus"
    }
  }
}
```

### Token Fields

| Field | Path | Type | Description |
|-------|------|------|-------------|
| `input_tokens` | `payload.info.total_token_usage.input_tokens` | Int | Total input tokens |
| `cached_input_tokens` | `payload.info.total_token_usage.cached_input_tokens` | Int | Tokens read from cache |
| `output_tokens` | `payload.info.total_token_usage.output_tokens` | Int | Output tokens |
| `reasoning_output_tokens` | `payload.info.total_token_usage.reasoning_output_tokens` | Int | Reasoning tokens |
| `total_tokens` | `payload.info.total_token_usage.total_tokens` | Int | Sum of all tokens |

### Additional Fields in `last_token_usage`
Same structure as `total_token_usage` - provides delta for just the last turn.

## Token Completeness

| Token Type | Available | Notes |
|------------|-----------|-------|
| Input Tokens | ✅ Yes | `input_tokens` |
| Output Tokens | ✅ Yes | `output_tokens` |
| Cache Read Tokens | ✅ Yes | `cached_input_tokens` |
| Cache Creation Tokens | ❌ No | Not available from Codex API |
| Reasoning Tokens | ✅ Yes | `reasoning_output_tokens` |

## Data Quality Notes

- **First event `info: null`**: The first `token_count` event in a session always has `info: null` - this is expected placeholder before tokens are consumed
- **`limit_name`**: Always `null`
- **`credits`**: Always `null`
- **Last event wins**: Implementation should use the last `token_count` event per file for final accumulated totals
- **Total mismatch**: `total_tokens` may not exactly equal sum of components (calculated at write time, may not update when cache values change)

## Parsing Strategy

- Parse all JSON lines that match `type == "event_msg"` and `payload.type == "token_count"`
- Extract `payload.info.total_token_usage` fields
- The last matching event per file contains complete session totals

## Last Updated
2026-04-12