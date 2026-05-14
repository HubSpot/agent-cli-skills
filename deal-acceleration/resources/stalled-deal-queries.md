# Stalled Deal Filter Expressions

CLI filter expressions for finding deals that need attention. Substitute date placeholders or use the dynamic date snippets below.

## Dynamic Date Computation

These shell expressions compute date strings at runtime so queries stay current without manual edits.

```bash
# macOS
THIRTY_DAYS_AGO=$(date -v-30d +%Y-%m-%d)
SIXTY_DAYS_AGO=$(date -v-60d +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)

# Linux
THIRTY_DAYS_AGO=$(date -d '30 days ago' +%Y-%m-%d)
SIXTY_DAYS_AGO=$(date -d '60 days ago' +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)
```

---

## Scenario: Deals Past Close Date (Still Open)

Deals where `closedate` is in the past and the deal has not been marked closed/won/lost.

```bash
hubspot objects search --type deals \
  --filter "closedate<$(date -v-0d +%Y-%m-%d) AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id,amount
```

Linux equivalent:
```bash
hubspot objects search --type deals \
  --filter "closedate<$(date +%Y-%m-%d) AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id,amount
```

---

## Scenario: Deals with No Activity in 30 Days

```bash
# macOS
hubspot objects search --type deals \
  --filter "hs_last_sales_activity_date<$(date -v-30d +%Y-%m-%d) AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id,hs_last_sales_activity_date

# Linux
hubspot objects search --type deals \
  --filter "hs_last_sales_activity_date<$(date -d '30 days ago' +%Y-%m-%d) AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id,hs_last_sales_activity_date
```

---

## Scenario: Deals in a Specific Stage with Old Close Dates

Get the stage ID first:
```bash
hubspot pipelines stages --object deals --pipeline <pipeline_id> --format table
```

Then filter:
```bash
# macOS — deals in a specific stage with close dates more than 14 days past
hubspot objects search --type deals \
  --filter "dealstage=<stage_id> AND closedate<$(date -v-14d +%Y-%m-%d) AND hs_is_closed!=true" \
  --properties dealname,closedate,hubspot_owner_id,amount

# Linux
hubspot objects search --type deals \
  --filter "dealstage=<stage_id> AND closedate<$(date -d '14 days ago' +%Y-%m-%d) AND hs_is_closed!=true" \
  --properties dealname,closedate,hubspot_owner_id,amount
```

---

## Scenario: Deals Without an Amount Set

`!amount` matches deals where the `amount` field is empty/null.

```bash
hubspot objects search --type deals \
  --filter "!amount AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id
```

---

## Scenario: Deals with No Associated Contacts

```bash
hubspot objects search --type deals \
  --filter "num_associated_contacts<1 AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id,amount
```

---

## Scenario: Deals with Probability Above 0 But Not Closing Soon

Find deals that show pipeline intent but have a close date more than 60 days out — candidates for acceleration.

```bash
# macOS
hubspot objects search --type deals \
  --filter "hs_deal_stage_probability>0 AND closedate>$(date -v+60d +%Y-%m-%d) AND hs_is_closed!=true" \
  --properties dealname,dealstage,hs_deal_stage_probability,closedate,amount,hubspot_owner_id

# Linux
hubspot objects search --type deals \
  --filter "hs_deal_stage_probability>0 AND closedate>$(date -d '60 days' +%Y-%m-%d) AND hs_is_closed!=true" \
  --properties dealname,dealstage,hs_deal_stage_probability,closedate,amount,hubspot_owner_id
```

---

## Scenario: Deals with No Activity at All

Deals where `hs_last_sales_activity_date` has never been set.

```bash
hubspot objects search --type deals \
  --filter "!hs_last_sales_activity_date AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id
```

---

## Combining Filters for a Full Stalled-Deal Report

This finds open deals that are: past close date, have no amount, or have had no activity in 30 days.
Run each query separately and combine outputs with `jq -s`:

```bash
# macOS
{
  hubspot objects search --type deals \
    --filter "closedate<$(date +%Y-%m-%d) AND hs_is_closed!=true" \
    --properties dealname,dealstage,closedate,amount,hubspot_owner_id
  hubspot objects search --type deals \
    --filter "!amount AND hs_is_closed!=true" \
    --properties dealname,dealstage,closedate,amount,hubspot_owner_id
  hubspot objects search --type deals \
    --filter "hs_last_sales_activity_date<$(date -v-30d +%Y-%m-%d) AND hs_is_closed!=true" \
    --properties dealname,dealstage,closedate,amount,hubspot_owner_id
} | sort -u
```

---

## Notes on Filter Syntax

- `closedate` and `hs_last_sales_activity_date` accept `YYYY-MM-DD` strings for comparison operators (`<`, `>`).
- `hs_last_sales_activity_date` is a datetime field but a date string (e.g., `2025-03-01`) works for `<` comparisons.
- `!property` matches records where the field is null or empty.
- `AND` is the only supported boolean operator in a single `--filter` string.
- For `OR` logic, run multiple queries and merge results.
