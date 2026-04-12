# Claude Code Data Source

## File Location
```
~/.claude/projects/*/*.jsonl
~/.claude/projects/*/subagents/agent-*.jsonl
```

## File Format
JSONL (one JSON object per line, newline-delimited)

## Session Directory Structure
- Each project has its own directory under `~/.claude/projects/`
- Directory name follows pattern: `-<normalized-cwd-path>`
- Each session file is named with a UUID: `<session-id>.jsonl`
- Optional `subagents/` subdirectory contains agent-specific JSONL files

## Data Structure

### Token Fields (in `message.usage`)

| Field | Path | Type | Description |
|-------|------|------|-------------|
| `input_tokens` | `message.usage.input_tokens` | Int | Raw input tokens for the turn |
| `output_tokens` | `message.usage.output_tokens` | Int | Generated output tokens |
| `cache_read_input_tokens` | `message.usage.cache_read_input_tokens` | Int | Tokens read from cache |
| `cache_creation_input_tokens` | `message.usage.cache_creation_input_tokens` | Int | Tokens used to create cache |
| `ephemeral_1h_input_tokens` | `message.usage.cache_creation.ephemeral_1h_input_tokens` | Int | Ephemeral cache (1hr TTL) |
| `ephemeral_5m_input_tokens` | `message.usage.cache_creation.ephemeral_5m_input_tokens` | Int | Ephemeral cache (5min TTL) |

### Complete Entry Example
```json
{
  "parentUuid": "22b113ef-1071-4c0d-878f-6ed1d02317d5",
  "isSidechain": false,
  "message": {
    "model": "claude-opus-4-6-20250514",
    "id": "msg_01AkzATkSdQ4qpEY4eBqh5HJ",
    "type": "message",
    "role": "assistant",
    "content": [{"type": "thinking", "thinking": "", "signature": "..."}],
    "stop_reason": null,
    "stop_sequence": null,
    "usage": {
      "input_tokens": 3,
      "cache_creation_input_tokens": 10119,
      "cache_read_input_tokens": 11431,
      "cache_creation": {
        "ephemeral_5m_input_tokens": 0,
        "ephemeral_1h_input_tokens": 10119
      },
      "output_tokens": 39,
      "service_tier": "standard",
      "inference_geo": "not_available"
    }
  },
  "requestId": "req_011CZt6PBN2YanDdsU7qjX2e",
  "type": "assistant",
  "uuid": "705d5fd4-11a0-4b30-914d-22f23a74971b",
  "timestamp": "2026-04-09T11:09:35.453Z",
  "userType": "external",
  "entrypoint": "cli",
  "cwd": "/Users/mikevalstar/projects/aether",
  "sessionId": "8f4ed261-e50a-46ed-8fa7-33ca520f6bf7",
  "version": "2.1.94",
  "gitBranch": "main",
  "slug": "buzzing-fluttering-tome"
}
```

## Token Completeness

| Token Type | Available | Notes |
|------------|-----------|-------|
| Input Tokens | ✅ Yes | `input_tokens` |
| Output Tokens | ✅ Yes | `output_tokens` |
| Cache Read Tokens | ✅ Yes | `cache_read_input_tokens` |
| Cache Creation Tokens | ✅ Yes | `cache_creation_input_tokens` |
| Reasoning Tokens | ❌ No | Not available in Claude Code format |

## Data Quality Notes

- **Completeness**: Excellent - all core token types present
- **`stop_reason`**: Always `null` - not populated even when content shows `end_turn`
- **`message.model`**: Sometimes `null` in newer versions
- **`inference_geo`**: Always `"not_available"` - placeholder field
- **Subagent files**: Same structure with `isSidechain: true` and additional `agentId` field

## Parsing Strategy

Current implementation uses `line.contains("input_tokens")` as a fast pre-filter before JSON parsing. This correctly identifies lines with token data at `message.usage.input_tokens`.

## Last Updated
2026-04-12