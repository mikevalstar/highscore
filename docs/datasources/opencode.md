# OpenCode Data Source

## File Location
```
~/.local/share/opencode/opencode.db
```

## Database Type
SQLite

## Database Size
~44 MB

## Schema Overview

| Table | Purpose |
|-------|---------|
| `__drizzle_migrations` | Migration tracking |
| `account` | User account credentials |
| `account_state` | Active account/org state |
| `control_account` | External control accounts |
| `event` | Event sourcing events |
| `event_sequence` | Event sequence tracking |
| `message` | **Chat messages (primary token data)** |
| `part` | Message parts/steps with token data |
| `permission` | Project permissions |
| `project` | Projects/workspaces |
| `session` | Chat sessions |
| `session_share` | Shared session links |
| `todo` | Todo items |
| `workspace` | Workspace definitions |

## Primary Token Tables

### `message` Table

Token data stored as JSON in `data` column.

```sql
SELECT 
  id,
  session_id,
  time_created,
  json_extract(data, '$.tokens.input') as input_tokens,
  json_extract(data, '$.tokens.output') as output_tokens,
  json_extract(data, '$.tokens.reasoning') as reasoning_tokens,
  json_extract(data, '$.tokens.cache.read') as cache_read_tokens,
  json_extract(data, '$.tokens.cache.write') as cache_write_tokens,
  json_extract(data, '$.tokens.total') as total_tokens,
  json_extract(data, '$.cost') as cost,
  json_extract(data, '$.modelID') as model_id,
  json_extract(data, '$.providerID') as provider_id
FROM message
WHERE json_extract(data, '$.tokens.input') IS NOT NULL;
```

### Token Data Structure (JSON in `data` column)

```json
{
  "tokens": {
    "total": 8395,
    "input": 276,
    "output": 155,
    "reasoning": 0,
    "cache": {
      "read": 6960,
      "write": 1004
    }
  },
  "cost": 0.0010629,
  "modelID": "MiniMax-M2.7",
  "providerID": "minimax"
}
```

## Token Fields

| Field | JSON Path | Type | Description |
|-------|----------|------|-------------|
| `input` | `$.tokens.input` | Int | Input tokens |
| `output` | `$.tokens.output` | Int | Output tokens |
| `reasoning` | `$.tokens.reasoning` | Int | Reasoning tokens |
| `cache.read` | `$.tokens.cache.read` | Int | Cache read tokens |
| `cache.write` | `$.tokens.cache.write` | Int | Cache write tokens |
| `total` | `$.tokens.total` | Int | Sum of all token types |
| `cost` | `$.cost` | Float | Cost in USD |
| `modelID` | `$.modelID` | String | Model identifier |
| `providerID` | `$.providerID` | String | Provider (openai, minimax) |

## Statistics

| Metric | Value |
|--------|-------|
| Total Messages | 1,715 |
| Messages with token data | 1,551 (90.4%) |
| Messages without data | 164 (user prompts - expected) |

## Supported Providers

| Provider | Model | Message Count |
|----------|-------|--------------|
| openai | gpt-5.4 | 949 |
| minimax | MiniMax-M2.7 | 591 |

## Data Completeness

| Token Type | Available | Notes |
|------------|-----------|-------|
| Input Tokens | ✅ Yes | `tokens.input` |
| Output Tokens | ✅ Yes | `tokens.output` |
| Cache Read Tokens | ✅ Yes | `tokens.cache.read` |
| Cache Write Tokens | ✅ Yes | `tokens.cache.write` |
| Reasoning Tokens | ⚠️ Partial | Only for OpenAI models; MiniMax always 0 |

## Data Quality Notes

- **User messages**: Do not have token data (`role: "user"`) - expected behavior
- **Total mismatch**: `tokens.total` may not equal sum of components in ~100+ records
- **Reasoning tokens**: Only OpenAI `gpt-5.4` tracks reasoning; MiniMax-M2.7 always 0
- **Cache writes**: Only GPT models have non-zero cache writes; MiniMax models always 0

## Parsing Strategy

- Filter `WHERE json_extract(data, '$.tokens.input') > 0` to exclude user prompts
- May want to recalculate `total` from components rather than trusting stored value
- Reasoning tokens default to 0 for non-OpenAI models

## Last Updated
2026-04-12