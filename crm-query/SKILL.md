---
name: crm-query
description: Filter, list, and count HubSpot CRM records from the terminal, and discover portal schema (object types, properties, pipelines, owners). Use when the user asks to filter records by criteria, count records, look up what object types or properties exist, or resolve owner names to IDs. For aggregations (GROUP BY, SUM, AVG), time series, or cross-object filters in a single call, use crm-reports. For basic lookup by ID/email/domain/name, use crm-lookup. For deal pipeline snapshots and win/loss analysis, use sales-reporting. Website traffic analytics, marketing email metrics, and LLM-based content analysis have no CLI equivalent.
triggers:
  - "filter contacts"
  - "filter deals"
  - "filter records"
  - "count contacts"
  - "count deals"
  - "how many contacts"
  - "how many deals"
  - "how many records"
  - "what object types"
  - "list all properties"
  - "object schema"
  - "what properties exist"
  - "find owner"
  - "list owners"
  - "resolve owner"
  - "contacts with no deals"
  - "companies with no activity"
---

## Foundations

Read [`bulk-operations/SKILL.md`](../bulk-operations/SKILL.md) first — JSONL piping, batch-read, pagination, and the safety flow for downstream writes live there. `hubspot <command> --help` is authoritative; trust it over this file if they conflict.

For basic lookup by ID, email, domain, or name fragment, see [`crm-lookup/SKILL.md`](../crm-lookup/SKILL.md). For aggregations (GROUP BY, SUM, AVG, time series, cross-object filters), see [`crm-reports/SKILL.md`](../crm-reports/SKILL.md). For deal pipeline snapshots and win/loss analysis, see [`sales-reporting/SKILL.md`](../sales-reporting/SKILL.md).

## Resources

| File | When to use |
|---|---|
| `resources/filter-operators.md` | Full filter syntax: operators, AND/OR rules, date windows, null/token patterns. |
| `resources/aggregation-patterns.md` | jq recipes for counting, summing, averaging, and time-series grouping. |

## What the CLI cannot do

Tell the user upfront if their request falls into one of these unsupported areas:

- **Aggregations, GROUP BY, time series, cross-object filters** — use `crm-reports` instead (`hubspot reports create "<sql>"`).
- **Website traffic analytics** (`web_analytics.*`) — no CLI equivalent; direct user to HubSpot Reports in the UI.
- **Marketing email metrics** (`EXT_EMAIL_*`, campaign sends/opens/clicks) — no CLI equivalent; direct user to HubSpot Email Analytics in the UI.
- **LLM analysis of call/email/deal content** — no CLI equivalent; available in HubSpot Breeze AI.

## 1. Discover CRM schema

Properties, pipeline stages, and custom object types are **portal-specific** — always discover at runtime rather than hardcoding.

```bash
# all object types in this portal (standard + custom)
hubspot objects types

# all properties for an object type
hubspot properties list --type contacts
hubspot properties list --type deals
hubspot properties list --type companies

# search for properties by name fragment (pipe to grep)
hubspot properties list --type contacts | grep -i "lifecycle"
hubspot properties list --type deals   | grep -i "close"

# details for a specific property (label, type, options/enum values)
hubspot properties get --type contacts lifecyclestage

# association types available from an object
hubspot associations types --from-type contacts
hubspot associations types --from-type deals

# deal pipelines and their stages (IDs are portal-specific)
hubspot pipelines list --type deals --format jsonl
hubspot pipelines stages --type deals --pipeline default --format jsonl

# grab a stage ID by its label
QUALIFIED=$(hubspot pipelines stages --type deals --pipeline default --format jsonl \
  | jq -r 'select(.label=="Qualified To Buy") | .id')
```

## 2. Search and filter records

`search` returns ≤ 100 records per call. Paginate (see bulk-operations) before counting or aggregating — a result of exactly 100 is almost always truncated.

```bash
# exact match on enum / string
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead" \
  --properties email,firstname,lastname,hubspot_owner_id

# multiple AND conditions in one --filter
hubspot objects search --type deals \
  --filter "hs_is_closed!=true AND dealstage=qualifiedtobuy" \
  --properties dealname,amount,dealstage,closedate

# OR conditions — multiple --filter flags
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead" \
  --filter "lifecyclestage=marketingqualifiedlead" \
  --properties email,firstname,lifecyclestage

# date range — ISO dates (YYYY-MM-DD) work in comparisons
TODAY=$(date +%Y-%m-%d)
LAST_30=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d)
hubspot objects search --type contacts \
  --filter "createdate>=$LAST_30 AND createdate<=$TODAY" \
  --properties email,firstname,createdate

# null / missing property
hubspot objects search --type contacts --filter "!email" --properties firstname,lastname
hubspot objects search --type contacts --filter "email"  --properties firstname,lastname,email

# token match (whole words only — "acme" matches "Acme Corp" but not "AcmeTech")
hubspot objects search --type deals --filter "dealname~acme" --properties dealname,dealstage
```

See `resources/filter-operators.md` for the full operator list and more examples.

## 3. Count records

```bash
# quick count (≤100 — if the number is exactly 100, paginate for the real count)
hubspot objects search --type contacts --filter "lifecyclestage=lead" --properties email \
  | jq -s 'length'

# accurate count for any number of records — paginate all, count lines
bash bulk-operations/resources/pagination-loop.sh contacts /tmp/leads.jsonl email \
  '--filter' 'lifecyclestage=lead'
wc -l < /tmp/leads.jsonl
```

Never report a count of 100 without first paginating — `search` silently truncates.

## 4. Aggregate, group, and cross-object queries

For aggregations (COUNT, SUM, AVG, GROUP BY, time series) and cross-object filters, use `crm-reports`:

```bash
# count by dimension — use crm-reports
hubspot reports create \
  "SELECT dealstage, COUNT(*), SUM(amount_in_home_currency) FROM DEAL GROUP BY dealstage" \
  --intent "Deals by stage"

# cross-object filter — use crm-reports
hubspot reports create \
  "SELECT dealname, amount_in_home_currency FROM DEAL WHERE COMPANY.industry = 'RETAIL'" \
  --intent "Deals at retail companies"
```

See [`crm-reports/SKILL.md`](../crm-reports/SKILL.md) for the full command reference and SQL syntax.

**jq fallback for simple grouping** (when you already have records paginated locally):

All properties come back as **strings** — use `tonumber` for arithmetic. See `resources/aggregation-patterns.md` for the full cookbook.

```bash
jq -rs '
  group_by(.properties.dealstage)
  | map({stage: .[0].properties.dealstage, count: length})
  | sort_by(-.count)[]
  | "\(.stage)\t\(.count)"' /tmp/deals.jsonl \
| column -t -s$'\t'
```

## 5. Records with no association

`crm-reports` handles most cross-object queries, but checking for the **absence** of an association requires a client-side pass:

```bash
# deals with no associated contact
bash bulk-operations/resources/pagination-loop.sh deals /tmp/deals.jsonl dealname,dealstage
jq -r '.id' /tmp/deals.jsonl \
| while IFS= read -r id; do
    count=$(hubspot associations list --from deals:$id --to contacts 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -eq 0 ] && jq -c "select(.id == \"$id\")" /tmp/deals.jsonl
  done
```

> For large datasets (>500 records), this loop spawns one process per record and will be slow. Tell the user and paginate a filtered subset first to reduce the count.

## 6. Owner lookup and resolution

```bash
# dump owners once — reuse across queries
hubspot owners list --format jsonl > /tmp/owners.jsonl

# find owner ID by email (for use in --filter)
jq -r 'select(.email == "john@acme.com") | .id' /tmp/owners.jsonl

# find owner ID by name fragment
jq -r 'select((.firstName + " " + .lastName) | ascii_downcase | contains("john smith")) | .id' \
  /tmp/owners.jsonl

# resolve owner IDs to names in a result set
hubspot objects search --type deals --filter "hs_is_closed!=true" \
  --properties dealname,amount,hubspot_owner_id \
| jq -c --slurpfile owners /tmp/owners.jsonl '
    . + {owner_name: (
      ($owners[0][] | select(.id == .properties.hubspot_owner_id)
       | .firstName + " " + .lastName) // "unknown"
    )}'
```

## Known constraints

- `search` returns ≤ 100 records per page; paginate before counting or aggregating.
- Multiple `--filter` flags are OR'd; use `AND` inside a single flag for AND conditions.
- `~` is token/word-boundary matching only — use `jq | ascii_downcase | contains(...)` for substring.
- Date properties accept ISO format (`YYYY-MM-DD`) in `--filter` comparisons.
- `hubspot owners list` returns CRM users only; there is no `teams` object — group by `hubspot_owner_id` client-side.
- Aggregations and cross-object filters: use `crm-reports` (see "What the CLI cannot do" above).
- Website analytics, marketing email metrics, and LLM content analysis have no CLI equivalent.
