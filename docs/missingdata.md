# Missing Token Data Analysis

Documenting the remaining gaps in token data availability across all supported sources.

---

## Summary of Remaining Gaps

| Data Source | Remaining Gap | Severity | Notes |
|-------------|---------------|----------|-------|
| **Copilot CLI** | None when `session.shutdown` exists | LOW | Falls back to `assistant.message` output only for incomplete sessions |
| **Cursor** | Cache read, cache write, reasoning | HIGH | Not stored in Cursor state DB |
| **Cursor** | Input/output coverage is sparse | HIGH | Many conversations still report zero tokens |
| **Claude Code** | Reasoning tokens | LOW | Not present in Claude Code JSONL |
| **Codex** | Cache creation tokens | LOW | Not present in rollout `token_count` events |
| **OpenCode** | Reasoning tokens for some providers | LOW | Provider/model limitation |

---

## Copilot CLI

### Status
Resolved for completed sessions.

### Current Reader Behavior
- Primary source: `session.shutdown.data.modelMetrics.*.usage`
- Fallback source: `assistant.message.data.outputTokens` only when no shutdown event exists

### Why This Matters
`session.shutdown` already contains the full session totals, including output tokens. If we summed both `session.shutdown` and `assistant.message`, output tokens would be double counted.

### Double-Counting Rule
- If `session.shutdown` exists, use it as the only source of truth for the session
- Only fall back to `assistant.message` output totals when shutdown data is missing

### Fields Now Captured
| Token Type | Path |
|------------|------|
| `inputTokens` | `data.modelMetrics.*.usage.inputTokens` |
| `outputTokens` | `data.modelMetrics.*.usage.outputTokens` |
| `cacheReadTokens` | `data.modelMetrics.*.usage.cacheReadTokens` |
| `cacheWriteTokens` | `data.modelMetrics.*.usage.cacheWriteTokens` |
| `reasoningTokens` | `data.modelMetrics.*.usage.reasoningTokens` |

### Remaining Limitation
Sessions that never emit `session.shutdown` can still only contribute `outputTokens` via fallback parsing.

---

## Cursor

### Status
Still best-effort only.

### Current State
Cursor stores useful data in two mutually exclusive shapes in the sampled database:
- Inline conversations on `composerData:<uuid>` records
- Header-only composer records with per-message token counts in `bubbleId:<composerId>:<bubbleId>`

Observed on 2026-04-12:
- `composerData:*`: 196
- `bubbleId:*`: 2,334
- Bubble rows with `tokenCount`: 2,264
- Bubble rows with non-zero `tokenCount`: 110
- Inline conversation composers: 56
- Header-only composers: 69
- Metadata-only composers: 67

### Double-Counting Rule
- For a given composer, use bubble totals when Cursor stores header-only conversation data
- Otherwise use inline conversation data
- Never sum bubble totals and inline conversation totals for the same composer

This matches the current reader and avoids counting the same Cursor conversation twice.

### Remaining Missing Token Types
| Token Type | Status | Notes |
|------------|--------|-------|
| Input Tokens | Partial | Available only for some composer/agent workflows |
| Output Tokens | Partial | Available only for some composer/agent workflows |
| Cache Read Tokens | Missing | Not stored |
| Cache Creation Tokens | Missing | Not stored |
| Reasoning Tokens | Missing | Not stored |

### Notes
- `tokenCountUpUntilHere` exists on a handful of bubble rows, but not broadly enough to replace the current strategy
- Cursor chat/basic workflows still appear to record zero tokens frequently

---

## Low-Priority API Limitations

### Claude Code
- Reasoning tokens are not present in Claude Code's JSONL format

### Codex
- Cache creation tokens are not present in rollout `token_count` events
- `cached_input_tokens` and `reasoning_output_tokens` are available and already tracked

### OpenCode
- Reasoning tokens depend on the underlying provider/model
- Some providers record `0` for reasoning consistently

---

## Verification Checklist

After updating readers:
1. Copilot totals should include input, cache, and reasoning when `session.shutdown` exists
2. Copilot output should not increase by summing both shutdown totals and message totals
3. Cursor totals should remain best-effort and should not combine bubble and inline totals for one composer

## Last Updated
2026-04-12
