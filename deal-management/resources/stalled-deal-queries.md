# Stalled Deal Filter Cookbook

Filter expressions for surfacing deals that need attention. Substitute date placeholders or use the dynamic-date snippets below — queries stay current with no edits.

## Dynamic dates

```bash
# macOS
THIRTY_DAYS_AGO=$(date -v-30d +%Y-%m-%d)
SIXTY_DAYS_AGO=$(date -v-60d +%Y-%m-%d)
SIXTY_DAYS_OUT=$(date -v+60d +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)

# Linux
THIRTY_DAYS_AGO=$(date -d '30 days ago' +%Y-%m-%d)
SIXTY_DAYS_AGO=$(date -d '60 days ago' +%Y-%m-%d)
SIXTY_DAYS_OUT=$(date -d '60 days' +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)
```

## Past close date, still open

```bash
hubspot objects search --type deals \
  --filter "closedate<$TODAY AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id,amount
```

## No sales activity in 30 days

```bash
hubspot objects search --type deals \
  --filter "hs_last_activity_date<$THIRTY_DAYS_AGO AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id,hs_last_activity_date
```

## No activity at all (open deals)

```bash
hubspot objects search --type deals \
  --filter "!hs_last_activity_date AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id
```

## Stuck in a specific stage with old close dates

Discover the stage ID first: `hubspot pipelines stages --type deals --pipeline <pipeline_id>`.

```bash
hubspot objects search --type deals \
  --filter "dealstage=<stage_id> AND closedate<$THIRTY_DAYS_AGO AND hs_is_closed!=true" \
  --properties dealname,closedate,hubspot_owner_id,amount
```

## Missing amount

```bash
hubspot objects search --type deals \
  --filter "!amount AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id
```

## No associated contacts

```bash
hubspot objects search --type deals \
  --filter "num_associated_contacts<1 AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id,amount
```

## High probability but no near-term close

Deals showing pipeline intent (probability > 0) with close date pushed far out — strong acceleration candidates.

```bash
hubspot objects search --type deals \
  --filter "hs_deal_stage_probability>0 AND closedate>$SIXTY_DAYS_OUT AND hs_is_closed!=true" \
  --properties dealname,dealstage,hs_deal_stage_probability,closedate,amount,hubspot_owner_id
```

## Combined stalled-deal report

`--filter` is AND-only within a flag. Use repeated `--filter` flags for OR, or merge multiple queries with `jq -s 'unique_by(.id)'`:

```bash
{
  hubspot objects search --type deals --filter "closedate<$TODAY AND hs_is_closed!=true"
  hubspot objects search --type deals --filter "!amount AND hs_is_closed!=true"
  hubspot objects search --type deals --filter "hs_last_activity_date<$THIRTY_DAYS_AGO AND hs_is_closed!=true"
} | jq -s 'unique_by(.id) | .[]'
```

## Filter syntax notes

- `closedate` is a date; activity-date props are datetime but accept `YYYY-MM-DD` strings for `<`/`>` comparisons.
- `!prop` = null/empty; bare `prop` = present and non-empty.
- AND only within one `--filter`. Use repeated `--filter` flags for OR.
- `hs_is_closed` and `hs_is_closed_won` are read-only but filterable.
