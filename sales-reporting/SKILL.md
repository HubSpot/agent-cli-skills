---
name: sales-reporting
description: Daily briefings, pipeline snapshots, and win/loss analysis from the terminal — closing-this-week, open pipeline by stage/owner, and closed-won vs closed-lost over a period.
triggers:
  - "daily briefing"
  - "pipeline snapshot"
  - "deals closing this week"
  - "deals by owner"
  - "win rate"
  - "closed won"
  - "closed lost"
  - "win/loss analysis"
  - "revenue by month"
  - "pipeline by stage"
---

## Source of truth

`hubspot <command> --help` is authoritative. Build on `bulk-operations/SKILL.md` — JSONL shape, batch-read rules, and pagination live there. Reshape patterns: `bulk-operations/resources/json-patterns.md`. `search`/`list` cap at 100 rows per call; a result of exactly 100 is almost always truncated — paginate via `bulk-operations/SKILL.md` before aggregating.

## Property and output shape notes

- All CRM property values come back as **strings** in JSONL — booleans included. `hs_is_closed_won` is returned as `"true"`/`"false"` (string); `amount` is a numeric string. Use `tonumber` for arithmetic; compare booleans as strings (`== "true"`) when filtering client-side.
- In `--filter` expressions, `hs_is_closed_won=true` and `hs_is_closed!=true` work — the API parses the value.
- `--properties` returns the standard nested shape: `{"id":"123","properties":{"amount":"5000","dealname":"..."}}`. Reference fields as `.properties.amount` in jq.
- Stage IDs in `dealstage` are portal-specific. Map them with `hubspot pipelines stages --type deals --pipeline <id>`.
- `hubspot_owner_id` is a numeric string. Resolve to a name with `hubspot owners list` (fields: `id`, `firstName`, `lastName`, `email`).

## 1. Daily briefing

Date windows differ between macOS and GNU `date`:
```bash
# macOS
TODAY=$(date +%Y-%m-%d); NEXT_7=$(date -v+7d +%Y-%m-%d); YESTERDAY=$(date -v-1d +%Y-%m-%d)
# Linux
TODAY=$(date +%Y-%m-%d); NEXT_7=$(date -d '7 days' +%Y-%m-%d); YESTERDAY=$(date -d '1 day ago' +%Y-%m-%d)
```

**Deals closing in the next 7 days:**
```bash
hubspot objects search --type deals \
  --filter "closedate>$TODAY AND closedate<$NEXT_7 AND hs_is_closed!=true" \
  --properties dealname,amount,closedate,hubspot_owner_id
```

**Deals updated in the last 24h:**
```bash
hubspot objects search --type deals \
  --filter "hs_lastmodifieddate>$YESTERDAY AND hs_is_closed!=true" \
  --properties dealname,amount,dealstage,hs_lastmodifieddate
```

**Open-pipeline summary line:**
```bash
hubspot objects search --type deals --filter "hs_is_closed!=true" --properties amount \
| jq -rs '{count: length, value: ([.[].properties.amount | select(. != null) | tonumber] | add // 0 | round)}
          | "Open pipeline: \(.count) deals, $\(.value)"'
```

## 2. Pipeline snapshot

**By stage** — count and amount per `dealstage`:
```bash
hubspot objects search --type deals --filter "hs_is_closed!=true" \
  --properties dealstage,amount \
| jq -rs '
    group_by(.properties.dealstage)
    | map({stage: .[0].properties.dealstage, count: length,
           total: ([.[].properties.amount | select(. != null) | tonumber] | add // 0 | round)})
    | sort_by(-.total) | .[] | "\(.stage)\tcount: \(.count)\tvalue: $\(.total)"' \
| column -t -s$'\t'
```

**By owner:**
```bash
hubspot objects search --type deals --filter "hs_is_closed!=true" \
  --properties amount,hubspot_owner_id \
| jq -rs '
    group_by(.properties.hubspot_owner_id)
    | map({owner: .[0].properties.hubspot_owner_id, count: length,
           total: ([.[].properties.amount | select(. != null) | tonumber] | add // 0 | round)})
    | sort_by(-.total) | .[] | "owner \(.owner)\tdeals: \(.count)\tvalue: $\(.total)"' \
| column -t -s$'\t'
```

To label owner IDs with names, dump the owners file once and join:
```bash
hubspot owners list | jq -r '"\(.id)\t\(.firstName) \(.lastName) <\(.email)>"' > /tmp/owners.tsv
```

## 3. Win/loss analysis

Filter on `hs_is_closed_won=true` for won; `hs_is_closed=true AND hs_is_closed_won!=true` for lost. Scope with `closedate>=YYYY-MM-DD AND closedate<YYYY-MM-DD`.

**Closed won / lost in a period:**
```bash
hubspot objects search --type deals \
  --filter "hs_is_closed_won=true AND closedate>=2026-04-01 AND closedate<2026-07-01" \
  --properties dealname,amount,closedate,hubspot_owner_id

hubspot objects search --type deals \
  --filter "hs_is_closed=true AND hs_is_closed_won!=true AND closedate>=2026-04-01 AND closedate<2026-07-01" \
  --properties dealname,amount,closedate,hubspot_owner_id
```

**Win rate by rep** — pull all closed deals in the period, group, divide. Note: `hs_is_closed_won` lands as a string, so compare `== "true"`.
```bash
hubspot objects search --type deals \
  --filter "hs_is_closed=true AND closedate>=2026-01-01" \
  --properties hubspot_owner_id,hs_is_closed_won,amount \
| jq -rs '
    group_by(.properties.hubspot_owner_id)
    | map({owner: .[0].properties.hubspot_owner_id,
           total: length,
           won: ([.[] | select(.properties.hs_is_closed_won == "true")] | length),
           won_value: ([.[] | select(.properties.hs_is_closed_won == "true")
                       | .properties.amount | select(. != null) | tonumber] | add // 0 | round)})
    | map(. + {win_rate: ((.won / .total * 100) | round)})
    | sort_by(-.won_value)
    | .[] | "owner \(.owner)\twon: \(.won)/\(.total)\trate: \(.win_rate)%\twon: $\(.won_value)"' \
| column -t -s$'\t'
```

**Revenue by close month** (won deals):
```bash
hubspot objects search --type deals \
  --filter "hs_is_closed_won=true AND closedate>=2026-01-01" \
  --properties amount,closedate \
| jq -rs '
    group_by(.properties.closedate[0:7])
    | map({month: .[0].properties.closedate[0:7], count: length,
           revenue: ([.[].properties.amount | select(. != null) | tonumber] | add // 0 | round)})
    | sort_by(.month) | .[] | "\(.month)\tdeals: \(.count)\trevenue: $\(.revenue)"' \
| column -t -s$'\t'
```

## Known limitations

- `hubspot pipelines stages` does not expose stage probability — won/lost stages can't be auto-identified from the stages list. Use `hs_is_closed_won` on deals instead.
- No team object — group by `hubspot_owner_id` and resolve names from `hubspot owners list` client-side.
