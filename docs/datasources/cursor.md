# Cursor Data Source

## File Location
```text
~/Library/Application Support/Cursor/User/globalStorage/state.vscdb
```

## Database Type
SQLite

## Relevant Table

| Table | Purpose |
|-------|---------|
| `cursorDiskKV` | Composer metadata and message bubble state |

## Key Patterns

| Key Pattern | Purpose |
|-------------|---------|
| `composerData:<uuid>` | Composer metadata and, on older formats, inline conversation data |
| `bubbleId:<composerId>:<bubbleId>` | Per-message bubble payloads, including `tokenCount` on newer formats |

## Observed Shapes

In the sampled database on 2026-04-12:
- `composerData:*`: 196
- `bubbleId:*`: 2,334
- Inline conversation composers: 56
- Header-only composers: 69
- Metadata-only composers: 67
- Bubble rows with `tokenCount`: 2,264
- Bubble rows with non-zero `tokenCount`: 110

The important part is that inline conversations and header-only composers were observed as separate shapes, not mixed on the same composer.

## Parsing Strategy

Use one representation per composer:

1. If the composer is header-only, sum `tokenCount.inputTokens` and `tokenCount.outputTokens` from matching `bubbleId:` rows
2. Otherwise, use inline conversation data from `composerData:`
3. Never combine both for the same composer

This avoids double counting the same Cursor conversation.

## Available Fields

| Field | Location | Notes |
|-------|----------|-------|
| `tokenCount.inputTokens` | Bubble rows, sometimes inline conversation | Partial coverage |
| `tokenCount.outputTokens` | Bubble rows, sometimes inline conversation | Partial coverage |
| `tokenCountUpUntilHere` | Some bubble rows | Too sparse to use as primary total |

## Missing Fields

- Cache read tokens
- Cache creation tokens
- Reasoning tokens

These do not appear to be stored in Cursor's local state database.

## Data Quality Assessment

Cursor remains a best-effort source only:
- Many rows still report zero tokens
- Basic chat flows appear much less complete than agent/composer flows
- Missing cache and reasoning fields prevent full parity with other readers

## Recommendation

Keep Cursor support, but treat it as partial:
- useful for some agent/composer workflows
- not reliable enough to be the user's only tracked source

## Last Updated
2026-04-12
