---
name: sales-reporting
description: Generate daily sales briefings, pipeline snapshots by owner or close date, and activity summaries — all from the terminal.
triggers:
  - "daily briefing"
  - "pipeline report"
  - "deals closing this week"
  - "sales summary"
  - "pipeline snapshot"
  - "morning report"
  - "deals by owner"
  - "sales performance"
  - "daily sales briefing"
  - "weekly pipeline"
---

## Resources

| File | When to use |
|---|---|
| `resources/daily-briefing.sh` | Script that runs 5 pipeline queries and prints a formatted daily sales snapshot: deals closing soon, recently updated deals, new contacts, and pipeline totals by owner |

## Context
Sales reporting aggregates what's happening across the pipeline right now. This skill covers filtering deals by close date, grouping by rep, finding recently modified records, and combining multiple queries into a structured daily brief. All date-based filters use YYYY-MM-DD format, computed dynamically at runtime.

## Key Workflows

### Deals Closing This Week

```bash
# macOS
WEEK_START=$(date +%Y-%m-%d)
WEEK_END=$(date -v+7d +%Y-%m-%d)

# Linux
WEEK_START=$(date +%Y-%m-%d)
WEEK_END=$(date -d '7 days' +%Y-%m-%d)

hubspot objects search --type deals \
  --filter "closedate>$WEEK_START AND closedate<$WEEK_END AND hs_is_closed!=true" \
  --properties dealname,amount,dealstage,closedate,hubspot_owner_id
```

### Deals Closing This Month

```bash
# macOS
MONTH_START=$(date +%Y-%m-01)
MONTH_END=$(date -v+1m -v1d -v-1d +%Y-%m-%d)

# Linux
MONTH_START=$(date +%Y-%m-01)
MONTH_END=$(date -d "$(date +%Y-%m-01) +1 month -1 day" +%Y-%m-%d)

hubspot objects search --type deals \
  --filter "closedate>$MONTH_START AND closedate<=$MONTH_END AND hs_is_closed!=true" \
  --properties dealname,amount,dealstage,closedate,hubspot_owner_id
```

### Deals Modified in the Last 24 Hours

```bash
# macOS
YESTERDAY=$(date -v-1d +%Y-%m-%d)
# Linux
YESTERDAY=$(date -d '1 day ago' +%Y-%m-%d)

hubspot objects search --type deals \
  --filter "hs_lastmodifieddate>$YESTERDAY AND hs_is_closed!=true" \
  --properties dealname,amount,dealstage,hubspot_owner_id,hs_lastmodifieddate
```

### Open Pipeline by Owner (Grouped)

```bash
hubspot objects search --type deals \
  --filter "hs_is_closed!=true" \
  --properties dealname,amount,hubspot_owner_id \
| jq -s '
  group_by(.properties.hubspot_owner_id)
  | map({
      owner_id: .[0].properties.hubspot_owner_id,
      deal_count: length,
      total_value: ([.[].properties.amount | select(. != null) | tonumber] | add // 0 | round)
    })
  | sort_by(-.total_value)
  | .[]
  | "owner \(.owner_id)  deals: \(.deal_count)  value: $\(.total_value)"
' -r
```

To map owner IDs to names, cross-reference with owners:

```bash
hubspot owners list --format jsonl \
| jq -r '"\(.id)\t\(.firstName) \(.lastName) <\(.email)>"' > /tmp/owners.tsv

hubspot objects search --type deals \
  --filter "hs_is_closed!=true" \
  --properties dealname,amount,hubspot_owner_id \
| jq -s '
  group_by(.properties.hubspot_owner_id)
  | map({owner_id: .[0].properties.hubspot_owner_id, count: length,
         value: ([.[].properties.amount | select(. != null) | tonumber] | add // 0 | round)})
  | .[]
' | while IFS= read -r row; do
  owner_id=$(echo "$row" | jq -r '.owner_id')
  name=$(grep "^$owner_id" /tmp/owners.tsv | cut -f2 || echo "owner $owner_id")
  echo "$row" | jq -r --arg name "$name" '"  \($name): \(.count) deals, $\(.value)"'
done
```

### New Contacts This Week

```bash
# macOS
WEEK_START=$(date -v-7d +%Y-%m-%d)
# Linux
WEEK_START=$(date -d '7 days ago' +%Y-%m-%d)

hubspot objects search --type contacts \
  --filter "createdate>$WEEK_START" \
  --properties email,firstname,lastname,company,lifecyclestage,hubspot_owner_id
```

### Deal Count and Total Value for Open Pipeline

```bash
hubspot objects search --type deals \
  --filter "hs_is_closed!=true" \
  --properties amount \
| jq -s '{
    deal_count: length,
    total_value: ([.[].properties.amount | select(. != null) | tonumber] | add // 0 | round)
  }
  | "Open pipeline: \(.deal_count) deals, $\(.total_value) total"' -r
```

## Known Limitations
- Search returns at most 100 records. For pipelines with more than 100 open deals, use the pagination loop from the `bulk-operations` skill to collect all deals before aggregating.
- `amount` and date values come back as strings in JSONL output. Use `tonumber` for arithmetic and string comparison for dates.
- `hubspot_owner_id` in deal records is a numeric string. Cross-reference with `hubspot owners list` to get names.
