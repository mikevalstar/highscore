# Copilot CLI Data Source

## File Location
```
~/.copilot/session-state/<session-uuid>/events.jsonl
```

## File Format
JSONL (one JSON object per line, newline-delimited)

## Directory Structure
```
~/.copilot/session-state/<session-uuid>/
├── events.jsonl          # Main event stream
├── workspace.yaml        # Session metadata
└── rewind-snapshots/     # File state snapshots
```

## Event Types Found

| Event Type | Count | Contains Token Data |
|------------|-------|---------------------|
| `session.start` | 1 | No |
| `session.info` | 1 | No |
| `session.shutdown` | 1 | **YES - Comprehensive** |
| `hook.start` | 7 | No |
| `hook.end` | 7 | No |
| `user.message` | 2 | No |
| `assistant.turn_start` | 3 | No |
| `assistant.message` | 3 | **YES - outputTokens only** |
| `assistant.turn_end` | 3 | No |
| `tool.execution_start` | 2 | No |
| `tool.execution_complete` | 2 | Partial (metrics only) |

## Data Structures

### `session.shutdown` Event (Comprehensive Token Data)

```json
{
  "type": "session.shutdown",
  "data": {
    "shutdownType": "routine",
    "totalPremiumRequests": 2,
    "totalApiDurationMs": 10026,
    "sessionStartTime": 1776003726483,
    "codeChanges": {
      "linesAdded": 0,
      "linesRemoved": 0,
      "filesModified": []
    },
    "modelMetrics": {
      "claude-sonnet-4.6": {
        "requests": {
          "count": 3,
          "cost": 2
        },
        "usage": {
          "inputTokens": 66423,
          "outputTokens": 327,
          "cacheReadTokens": 22054,
          "cacheWriteTokens": 0,
          "reasoningTokens": 0
        }
      }
    },
    "currentModel": "claude-sonnet-4.6",
    "currentTokens": 21975,
    "systemTokens": 8968,
    "conversationTokens": 689,
    "toolDefinitionsTokens": 12314
  }
}
```

### `assistant.message` Event (Limited Token Data)

```json
{
  "type": "assistant.message",
  "data": {
    "messageId": "...",
    "content": "...",
    "toolRequests": [],
    "interactionId": "...",
    "outputTokens": 160,
    "requestId": "..."
  }
}
```

## Token Fields Available

### From `session.shutdown` (Complete)

| Field | Path | Type | Description |
|-------|------|------|-------------|
| `inputTokens` | `data.modelMetrics.<model>.usage.inputTokens` | Int | Total input tokens |
| `outputTokens` | `data.modelMetrics.<model>.usage.outputTokens` | Int | Total output tokens |
| `cacheReadTokens` | `data.modelMetrics.<model>.usage.cacheReadTokens` | Int | Cache read tokens |
| `cacheWriteTokens` | `data.modelMetrics.<model>.usage.cacheWriteTokens` | Int | Cache write tokens |
| `reasoningTokens` | `data.modelMetrics.<model>.usage.reasoningTokens` | Int | Reasoning tokens |
| `currentTokens` | `data.currentTokens` | Int | Current context token count |
| `systemTokens` | `data.systemTokens` | Int | System prompt tokens |
| `conversationTokens` | `data.conversationTokens` | Int | Conversation history tokens |
| `toolDefinitionsTokens` | `data.toolDefinitionsTokens` | Int | Tool definition tokens |

### From `assistant.message` (Limited)

| Field | Path | Type | Description |
|-------|------|------|-------------|
| `outputTokens` | `data.outputTokens` | Int | Output tokens only |

## Current Implementation vs Available Data

| Token Type | Currently Captured | Available in Data |
|------------|-------------------|-------------------|
| Input Tokens | ❌ No (always 0) | ✅ Yes (`inputTokens` in session.shutdown) |
| Output Tokens | ✅ Yes | ✅ Yes |
| Cache Read Tokens | ❌ No (always 0) | ✅ Yes (`cacheReadTokens`) |
| Cache Write Tokens | ❌ No (always 0) | ✅ Yes (`cacheWriteTokens`) |
| Reasoning Tokens | ❌ No (always 0) | ✅ Yes (`reasoningTokens`) |

## Additional Available Fields (Not in TokenScore)

| Field | Path | Description |
|-------|------|-------------|
| `totalApiDurationMs` | `data.totalApiDurationMs` | Total API duration in ms |
| `currentTokens` | `data.currentTokens` | Current context size |
| `systemTokens` | `data.systemTokens` | System prompt tokens |
| `conversationTokens` | `data.conversationTokens` | Conversation history tokens |
| `toolDefinitionsTokens` | `data.toolDefinitionsTokens` | Tool definition tokens |

## Data Completeness

| Token Type | Available | Notes |
|------------|-----------|-------|
| Input Tokens | ✅ Yes | In `session.shutdown.modelMetrics.usage` |
| Output Tokens | ✅ Yes | In both event types |
| Cache Read Tokens | ✅ Yes | In `session.shutdown.modelMetrics.usage` |
| Cache Write Tokens | ✅ Yes | In `session.shutdown.modelMetrics.usage` |
| Reasoning Tokens | ✅ Yes | In `session.shutdown.modelMetrics.usage` |

## Data Quality Notes

- **Current reader only uses `assistant.message` events** - missing comprehensive data from `session.shutdown`
- **`session.shutdown` provides per-session totals** - more reliable than summing individual messages
- **`cacheWriteTokens` maps to `cacheCreationTokens`** in TokenScore struct
- **`toolDefinitionsTokens`** is unique to Copilot CLI - not found in other sources

## Parsing Strategy

1. Parse `session.shutdown` events for complete token totals
2. Map `cacheWriteTokens` → `cacheCreationTokens`
3. Use `modelMetrics` for per-model breakdown
4. Fall back to `assistant.message` events only if `session.shutdown` unavailable

## Last Updated
2026-04-12