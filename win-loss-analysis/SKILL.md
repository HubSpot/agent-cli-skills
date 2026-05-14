---
name: win-loss-analysis
description: Analyze closed deals (won and lost), measure win rates by rep or time period, audit pipeline stage distribution, and identify revenue trends.
triggers:
  - "closed won deals"
  - "win rate"
  - "lost deals"
  - "win/loss analysis"
  - "deals we closed"
  - "pipeline health"
  - "pipeline audit"
  - "deal outcomes"
  - "deals closed this quarter"
  - "which deals did we win"
  - "closed lost"
  - "closed-won deal analysis"
  - "closed-lost deal analysis"
  - "pipeline audit and review"
---

## Resources

| File | When to use |
|---|---|
| `resources/pipeline-distribution.sh` | Script that fetches all open deals and prints a stage-by-stage breakdown showing count and total value per stage |

## Context
Win/loss analysis is retrospective — it looks at deals that have already closed to measure outcomes. `deal-acceleration` covers forward-looking work (moving open deals). This skill covers `hs_is_closed_won` filtering, revenue totals, win rates by rep, pipeline stage distribution of open deals, and time-scoped close date analysis. Stage IDs are always portal-specific; the first step is always looking them up.

## Property Reference — Deals

| Property | Type | Notes |
|---|---|---|
| `hs_is_closed` | boolean | `true` for both won and lost deals |
| `hs_is_closed_won` | boolean | `true` for won deals only |
| `dealstage` | string | Portal-specific stage ID |
| `amount` | number | Deal value |
| `closedate` | date | YYYY-MM-DD format for filters |
| `hubspot_owner_id` | string | Owning rep's numeric ID |
| `hs_deal_stage_probability` | number | Read-only; 100 = won stage, 0 = lost stage |
| `createdate` | datetime | When the deal was created |
| `hs_date_entered_closedwon` | datetime | When the deal moved to closed won |

## Key Workflows

### Identify Won and Lost Stage IDs for Your Portal

Stage IDs are portal-specific. Won stages have 100% probability; lost stages have 0%.

```bash
# List all pipelines to find the pipeline ID
hubspot pipelines list --object deals --format table

# List stages for a specific pipeline
hubspot pipelines stages --object deals --pipeline <pipeline_id> --format table
# Look for stages with probability 1.0 (won) or 0.0 (lost)
```

### Find All Closed Won Deals

```bash
hubspot objects search --type deals \
  --filter "hs_is_closed_won=true" \
  --properties dealname,amount,closedate,hubspot_owner_id
```

### Find All Closed Lost Deals

```bash
hubspot objects search --type deals \
  --filter "hs_is_closed=true AND hs_is_closed_won!=true" \
  --properties dealname,amount,closedate,hubspot_owner_id
```

### Scope to a Time Period

```bash
# Closed won this quarter (Q1 2025)
hubspot objects search --type deals \
  --filter "hs_is_closed_won=true AND closedate>2025-01-01 AND closedate<2025-04-01" \
  --properties dealname,amount,closedate,hubspot_owner_id

# Closed lost this month
hubspot objects search --type deals \
  --filter "hs_is_closed=true AND hs_is_closed_won!=true AND closedate>2025-03-01" \
  --properties dealname,amount,closedate,hubspot_owner_id
```

### Total Revenue from Won Deals

```bash
hubspot objects search --type deals \
  --filter "hs_is_closed_won=true AND closedate>2025-01-01" \
  --properties amount \
| jq -s '[.[].properties.amount | select(. != null) | tonumber] | add // 0'
```

### Win Rate by Rep

```bash
# All closed deals (both won and lost), grouped by owner
hubspot objects search --type deals \
  --filter "hs_is_closed=true AND closedate>2025-01-01" \
  --properties hubspot_owner_id,hs_is_closed_won \
| jq -s '
  group_by(.properties.hubspot_owner_id)
  | map({
      owner: .[0].properties.hubspot_owner_id,
      total: length,
      won: map(select(.properties.hs_is_closed_won == "true")) | length,
      win_rate: (map(select(.properties.hs_is_closed_won == "true")) | length) / length * 100 | round
    })
  | .[]
  | "\(.owner)  won: \(.won)/\(.total)  rate: \(.win_rate)%"
' -r
```

### Average Deal Value (Won Deals)

```bash
hubspot objects search --type deals \
  --filter "hs_is_closed_won=true" \
  --properties amount \
| jq -s '
  [.[].properties.amount | select(. != null) | tonumber]
  | if length == 0 then "no data" else (add / length | round | tostring + " avg") end
'
```

### Pipeline Stage Distribution (Open Deals)

```bash
hubspot objects search --type deals \
  --filter "hs_is_closed!=true" \
  --properties dealstage,amount \
| jq -s '
  group_by(.properties.dealstage)
  | map({
      stage: .[0].properties.dealstage,
      count: length,
      total_value: (map(.properties.amount | select(. != null) | tonumber) | add // 0 | round)
    })
  | sort_by(.stage)
  | .[]
  | "\(.stage)  count: \(.count)  value: $\(.total_value)"
' -r
```

### Find Deals That Stalled and Closed Lost (No Activity Before Closing)

```bash
hubspot objects search --type deals \
  --filter "hs_is_closed=true AND hs_is_closed_won!=true AND !hs_last_sales_activity_date" \
  --properties dealname,amount,closedate,hubspot_owner_id
```

## Known Limitations
- `hs_is_closed_won` is returned as the string `"true"` in JSONL output (not a boolean) — compare as a string when filtering client-side.
- `amount` is a string in JSONL output. Use `tonumber` before arithmetic.
- For > 100 closed deals, use the pagination loop from the `bulk-operations` skill to collect all records before aggregating.
- Stage IDs in `dealstage` are portal-specific. Run `hubspot pipelines stages` first to map IDs to names.
