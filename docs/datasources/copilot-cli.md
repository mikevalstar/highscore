# Copilot CLI Data Source

## File Location
```text
~/.copilot/session-state/<session-uuid>/events.jsonl
```

## File Format
JSONL (one JSON object per line)

## Directory Structure
```text
~/.copilot/session-state/<session-uuid>/
├── events.jsonl
├── workspace.yaml
└── rewind-snapshots/
```

## Event Types

| Event Type | Contains Token Data | Notes |
|------------|---------------------|-------|
| `session.shutdown` | Yes | Canonical per-session totals |
| `assistant.message` | Partial | Output tokens only |
| `tool.execution_complete` | Partial | Tool telemetry, not session totals |

## Canonical Token Source

Use `session.shutdown` as the source of truth for completed sessions.

```json
{
  "type": "session.shutdown",
  "data": {
    "modelMetrics": {
      "claude-sonnet-4.6": {
        "usage": {
          "inputTokens": 66423,
          "outputTokens": 327,
          "cacheReadTokens": 22054,
          "cacheWriteTokens": 0,
          "reasoningTokens": 0
        }
      }
    }
  }
}
```

The reader sums `data.modelMetrics.*.usage` across models in the shutdown event.

## Fallback Source

If a session does not have `session.shutdown`, fall back to `assistant.message.data.outputTokens`:

```json
{
  "type": "assistant.message",
  "data": {
    "outputTokens": 160
  }
}
```

This fallback is intentionally limited to output tokens.

## Double Counting Guard

Do not sum `assistant.message.outputTokens` on top of `session.shutdown` totals.

Reason:
- `session.shutdown` already includes the session's full output usage
- adding message totals again would inflate Copilot output counts

## Token Mapping

| Copilot Field | TokenScore Field |
|---------------|------------------|
| `inputTokens` | `inputTokens` |
| `outputTokens` | `outputTokens` |
| `cacheReadTokens` | `cacheReadTokens` |
| `cacheWriteTokens` | `cacheCreationTokens` |
| `reasoningTokens` | `reasoningTokens` |

## Data Completeness

| Token Type | Availability |
|------------|--------------|
| Input Tokens | Complete for finished sessions |
| Output Tokens | Complete for finished sessions |
| Cache Read Tokens | Complete for finished sessions |
| Cache Write Tokens | Complete for finished sessions |
| Reasoning Tokens | Complete for finished sessions |

## Notes

- `currentTokens`, `systemTokens`, `conversationTokens`, and `toolDefinitionsTokens` are present but not currently stored in `TokenScore`
- Incomplete sessions may only contribute output tokens via fallback parsing

## Last Updated
2026-04-12
