# Filter Operators Reference

Use `--filter "expression"` with `hubspot objects search`.

**AND / OR rules:**
- Multiple `--filter` flags are **OR'd**.
- Multiple conditions in a single `--filter "A AND B"` are **AND'd**.

```bash
# AND — one --filter flag with AND
hubspot objects search --type deals \
  --filter "hs_is_closed!=true AND hubspot_owner_id=12345"

# OR — multiple --filter flags
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead" \
  --filter "lifecyclestage=marketingqualifiedlead"

# AND + OR combined: (closed=false AND owner=X) OR (closed=false AND owner=Y)
# — not directly expressible; use a jq post-filter on a broader search instead
```

## Operators

| Operator | Syntax | Notes |
|---|---|---|
| Equals | `field=value` | String, enum, boolean, numeric, owner ID |
| Not equals | `field!=value` | Excludes exact matches |
| Greater than | `field>value` | Numeric or date (`YYYY-MM-DD`) |
| Greater than or equal | `field>=value` | |
| Less than | `field<value` | |
| Less than or equal | `field<=value` | |
| Contains token | `field~token` | Whole-word token match; not substring |
| Has property | `field` | Property is set / non-null |
| Not has property | `!field` | Property is unset / null |

## Date patterns

Date properties accept ISO strings (`YYYY-MM-DD`). Generate dynamic windows with shell `date`:

```bash
# macOS
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -v-1d +%Y-%m-%d)
LAST_30=$(date -v-30d +%Y-%m-%d)
NEXT_7=$(date -v+7d +%Y-%m-%d)

# Linux (GNU date)
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d '1 day ago' +%Y-%m-%d)
LAST_30=$(date -d '30 days ago' +%Y-%m-%d)
NEXT_7=$(date -d '7 days' +%Y-%m-%d)
```

```bash
# contacts created in the last 30 days
hubspot objects search --type contacts \
  --filter "createdate>=$LAST_30" \
  --properties email,firstname,lastname,createdate

# deals closing in the next 7 days
hubspot objects search --type deals \
  --filter "closedate>=$TODAY AND closedate<=$NEXT_7 AND hs_is_closed!=true" \
  --properties dealname,closedate,amount

# deals with no activity for 30+ days
hubspot objects search --type deals \
  --filter "hs_last_activity_date<$LAST_30 AND hs_is_closed!=true" \
  --properties dealname,dealstage,hs_last_activity_date

# explicit date range (e.g. Q1 2026)
hubspot objects search --type deals \
  --filter "closedate>=2026-01-01 AND closedate<2026-04-01 AND hs_is_closed_won=true" \
  --properties dealname,amount,closedate
```

## Null / missing property

```bash
# contacts missing an email
hubspot objects search --type contacts --filter "!email" --properties firstname,lastname

# contacts that have an email set
hubspot objects search --type contacts --filter "email" --properties firstname,lastname,email

# deals missing a close date (and still open)
hubspot objects search --type deals --filter "!closedate AND hs_is_closed!=true" \
  --properties dealname,dealstage
```

## Boolean and enum fields

HubSpot stores booleans as strings; the filter API parses them:

```bash
# open deals
hubspot objects search --type deals --filter "hs_is_closed!=true"

# closed-won deals only
hubspot objects search --type deals --filter "hs_is_closed_won=true"

# closed-lost deals
hubspot objects search --type deals --filter "hs_is_closed=true AND hs_is_closed_won!=true"
```

## Token match vs substring

`~` matches whole words/tokens. For substring matching, use a `jq` post-filter:

```bash
# "acme" matches "Acme Corp" and "ACME" — but NOT "AcmeTech"
hubspot objects search --type deals --filter "dealname~acme" --properties dealname,dealstage

# substring match: post-filter in jq
hubspot objects search --type deals --filter "dealname~acme" --properties dealname,dealstage \
| jq -c 'select(.properties.dealname | ascii_downcase | contains("acmetech"))'
```
