---
name: deal-management
description: Run the full deal lifecycle from CLI — discover pipelines/stages, qualify MQLs into deals with associations, advance/reassign in bulk, hunt stalled deals, and close.
triggers:
  - "create deal"
  - "qualify lead"
  - "MQL to SQL"
  - "qualify MQL"
  - "deal from contact"
  - "advance deal"
  - "move deal stage"
  - "reassign deal"
  - "stalled deals"
  - "deals past close date"
  - "accelerate pipeline"
  - "close deal"
  - "deal lifecycle"
---

## Resources

| File | When to use |
|---|---|
| `resources/lifecycle-stage-progression.md` | Lifecycle stage API values + the contact-side updates that pair with deal moves. |
| `resources/stalled-deal-queries.md` | Filter cookbook for stalled / no-activity / past-close-date deals with dynamic dates. |

## Foundations

Read `bulk-operations/SKILL.md` first — JSONL piping, batch read, pagination, and the dry-run/digest/confirm flow live there. Reshape recipes are in `bulk-operations/resources/json-patterns.md`. `hubspot <command> --help` is the source of truth. Object types are plural (`contacts`, `deals`, `companies`). For property reference: `hubspot properties list --type deals` — don't hardcode property tables.

## 1. Discover pipelines and stages

Pipeline and stage IDs are **portal-specific**. Always discover at runtime — never hardcode across portals.

```bash
hubspot pipelines list --type deals --format jsonl
# {"id":"default","label":"Sales Pipeline","displayOrder":0}
# {"id":"e3955620-000b-4bee-bef5-e19366fc27f2","label":"Bash Pipeline","displayOrder":1}

hubspot pipelines stages --type deals --pipeline default --format jsonl
# {"id":"appointmentscheduled","label":"Appointment Scheduled","displayOrder":0}
# {"id":"qualifiedtobuy","label":"Qualified To Buy","displayOrder":1}
# ...
# {"id":"closedwon","label":"Closed Won","displayOrder":5}
# {"id":"closedlost","label":"Closed Lost","displayOrder":6}
```

Grab a specific stage ID by label:

```bash
QUALIFIED=$(hubspot pipelines stages --type deals --pipeline default --format jsonl \
  | jq -r 'select(.label=="Qualified To Buy") | .id')
```

The IDs shown above (`appointmentscheduled`, `closedwon`, etc.) are verified real for portal 150890's `default` pipeline — but discover yours every run.

## 2. Qualify an MQL into a deal

Find connected MQLs without a deal, then for each: create the deal, associate to contact + company, promote lifecycle.

```bash
# 1. find ready MQLs
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND hs_lead_status=CONNECTED AND num_associated_deals=0" \
  --properties email,firstname,lastname,company,hubspot_owner_id

# 2. for one contact: company lookup, deal create, associate, promote
hubspot associations list --from contacts:<contact_id> --to companies   # → <company_id>

hubspot objects create --type deals \
  --property "dealname=Acme Corp - Inbound" \
  --property pipeline=default --property dealstage=qualifiedtobuy \
  --property amount=0 --property hubspot_owner_id=<owner_id>
# returns {"id":"<deal_id>","ok":true,...}

hubspot associations create --from deals:<deal_id> --to contacts:<contact_id>
hubspot associations create --from deals:<deal_id> --to companies:<company_id>

hubspot objects update --type contacts <contact_id> \
  --property lifecyclestage=salesqualifiedlead --property hs_lead_status=OPEN_DEAL
```

### Bulk pattern — many MQLs at once

`objects create` returns one result line per stdin line, in input order. Capture both streams and join by line for associations:

```bash
# 1. snapshot MQLs to a file (preserves order for the join)
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND hs_lead_status=CONNECTED AND num_associated_deals=0" \
  --properties email,firstname,lastname,company,hubspot_owner_id \
  > /tmp/mqls.jsonl

# 2. one deal per MQL — output preserves order
jq -c '{properties:{
    dealname: ((.properties.firstname // "") + " " + (.properties.lastname // "") + " - " + (.properties.company // "Unknown")),
    pipeline:"default", dealstage:"qualifiedtobuy", amount:"0", dealtype:"newbusiness",
    hubspot_owner_id:(.properties.hubspot_owner_id // "")
  }}' /tmp/mqls.jsonl \
| hubspot objects create --type deals > /tmp/deals.jsonl

# 3. abort if any create failed — paste would zip null deal IDs onto real contacts
jq -e 'select(.ok==false)' /tmp/deals.jsonl > /dev/null && { echo "Some deal creates failed — inspect /tmp/deals.jsonl" >&2; exit 1; }

# 4. pair contact <-> new deal by line for the association call
paste <(jq -r '.id' /tmp/mqls.jsonl) <(jq -r '.id' /tmp/deals.jsonl) \
| jq -cR 'split("\t") | {from:("deals:" + .[1]), to:("contacts:" + .[0])}' \
| hubspot associations create

# 5. promote lifecycle on every contact
jq -c '{id, properties:{lifecyclestage:"salesqualifiedlead", hs_lead_status:"OPEN_DEAL"}}' /tmp/mqls.jsonl \
| hubspot objects update --type contacts
```

Company associations need a separate per-contact pass via `hubspot associations list --from contacts:<id> --to companies` — a contact may have zero or many companies.

Pre-qualification checks are just filters on the search: has email, has a company, no open deal, has an owner — all in the `--filter` already. See `resources/lifecycle-stage-progression.md` for the full stage progression and contact-side updates.

## 3. Advance or reassign in bulk

```bash
# move every deal in one stage to the next — preview, then re-run without --dry-run
hubspot objects search --type deals --filter "dealstage=qualifiedtobuy" \
| jq -c '{id, properties:{dealstage:"presentationscheduled"}}' \
| hubspot objects update --type deals --dry-run

# reassign open deals from one rep to another
OLD=$(hubspot owners list --format jsonl | jq -r 'select(.email=="old@co.com") | .id')
NEW=$(hubspot owners list --format jsonl | jq -r 'select(.email=="new@co.com") | .id')
hubspot objects search --type deals --filter "hubspot_owner_id=$OLD AND hs_is_closed!=true" \
| jq -c "{id, properties:{hubspot_owner_id:\"$NEW\"}}" \
| hubspot objects update --type deals --dry-run
```

For >100 rows, the dry-run emits a digest line; re-pipe with `--digest <hash> --confirm <count>`. Full flow in `bulk-operations/SKILL.md`.

## 4. Find stalled deals

Filter cookbook with dynamic dates lives in `resources/stalled-deal-queries.md`. The core query:

```bash
# open deals with no activity in 30 days (macOS / Linux date examples in resources)
hubspot objects search --type deals \
  --filter "hs_last_activity_date<$(date -v-30d +%Y-%m-%d) AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id,hs_last_activity_date
```

Pipe the result into an update (extend close dates, move stage, set a flag) or into task creation. For follow-up tasks/calls/notes against stalled deals, see the `sales-execution` skill — don't duplicate activity-object property handling here.

```bash
# extend close dates for everything past due
hubspot objects search --type deals \
  --filter "closedate<$(date +%Y-%m-%d) AND hs_is_closed!=true" \
| jq -c '{id, properties:{closedate:"2026-06-30"}}' \
| hubspot objects update --type deals --dry-run
```

## 5. Close

Closing is a stage update + `closedate` (YYYY-MM-DD). `hs_is_closed` and `hs_is_closed_won` are read-only — HubSpot derives them from the stage.

```bash
# single
hubspot objects update --type deals <deal_id> \
  --property dealstage=closedwon --property closedate=2026-05-15

# bulk — preview first
hubspot objects search --type deals --filter "dealstage=contractsent AND hubspot_owner_id=<owner_id>" \
| jq -c '{id, properties:{dealstage:"closedwon", closedate:"2026-05-15"}}' \
| hubspot objects update --type deals --dry-run
```

Win/loss analysis (close reasons, win rate, ARR roll-up) is in the `sales-reporting` skill.

## Known constraints

- Bulk MQL → deal needs a two-pass shell flow: associations must be built from `objects create` output, not in the same pipe.
- `lifecyclestage` is forward-only in most portal settings — backward transitions may be rejected.
- `closedate` is a date string (`YYYY-MM-DD`). Datetime activity props (`hs_last_activity_date`) also accept a date string for `<`/`>` comparisons.
- No sequences/cadences API in the CLI — create a follow-up task via `sales-execution` instead.
