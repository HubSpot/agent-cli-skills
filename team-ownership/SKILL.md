---
name: team-ownership
description: Assign and reassign CRM record ownership, audit who-owns-what across object types, and handle rep transitions. Built on `bulk-operations`.
triggers:
  - "assign owner"
  - "reassign records"
  - "ownership audit"
  - "rep leaving"
  - "transfer records"
  - "change owner"
  - "find records owned by"
  - "redistribute accounts"
---

Prereq: read `bulk-operations/SKILL.md` first. JSONL piping, pagination, dry-run/digest/confirm, and `hubspot history` recovery live there. Reshape patterns live in `bulk-operations/resources/json-patterns.md`.

`hubspot_owner_id` is a string field on `contacts`, `companies`, `deals`, and `tickets`. Owners are CRM users — `hubspot owners list` returns them; there is no `teams` object, so team-level views are client-side groupings by `hubspot_owner_id`.

## 1. Resolve email → owner ID

Never hardcode IDs — they are portal-specific. Resolve, then cache:

```bash
FROM_ID=$(hubspot owners list | jq -r 'select(.email=="sarah@company.com") | .id')
TO_ID=$(hubspot owners list | jq -r 'select(.email=="mike@company.com")  | .id')
```

## 2. Find records for an owner

Same filter across all four object types. Add object-specific `--properties` for context. Unowned records use the `!property` form.

```bash
hubspot objects search --type contacts  --filter "hubspot_owner_id=$FROM_ID" --properties email,firstname,lifecyclestage
hubspot objects search --type companies --filter "hubspot_owner_id=$FROM_ID" --properties name,domain
hubspot objects search --type deals     --filter "hubspot_owner_id=$FROM_ID" --properties dealname,dealstage,amount
hubspot objects search --type tickets   --filter "hubspot_owner_id=$FROM_ID" --properties subject,hs_pipeline_stage

# Records with no owner at all
hubspot objects search --type deals --filter "!hubspot_owner_id" --properties dealname,amount
```

>100 hits — page with the `--after` loop from `bulk-operations`. Counting only: pipe to `wc -l`.

## 3. Bulk reassign — search → update

Reshape each search row into `{id, properties:{hubspot_owner_id}}` and pipe to `objects update`. Always dry-run first; for >100 rows the dry-run emits a digest + `apply_command_hint` — re-run with `--digest`/`--confirm` (see `bulk-operations/SKILL.md` § "Safe destructive workflow").

```bash
# Dry-run
hubspot objects search --type contacts --filter "hubspot_owner_id=$FROM_ID" \
| jq -c --arg to "$TO_ID" '{id, properties:{hubspot_owner_id:$to}}' \
| hubspot objects update --type contacts --dry-run

# Execute — ≤100: drop --dry-run.  >100: append --digest <hash> --confirm <count>.
hubspot objects search --type contacts --filter "hubspot_owner_id=$FROM_ID" \
| jq -c --arg to "$TO_ID" '{id, properties:{hubspot_owner_id:$to}}' \
| hubspot objects update --type contacts
```

Single-record assignment — no stdin, no jq:

```bash
hubspot objects update --type contacts 12345 --property hubspot_owner_id=$TO_ID
```

## 4. Rep-leaves workflow

Loop over the four object types the rep touches:

```bash
FROM_ID=$(hubspot owners list | jq -r 'select(.email=="leaving@company.com")    | .id')
TO_ID=$(hubspot  owners list | jq -r 'select(.email=="taking-over@company.com") | .id')

for type in contacts companies deals tickets; do
  echo "── $type ──"
  hubspot objects search --type "$type" --filter "hubspot_owner_id=$FROM_ID" \
  | jq -c --arg to "$TO_ID" '{id, properties:{hubspot_owner_id:$to}}' \
  | hubspot objects update --type "$type" --dry-run
done
```

Review each digest line, then re-run without `--dry-run` (adding `--digest`/`--confirm` per type when escalated). Mis-reassigned? `hubspot history --since 1h` lists the affected IDs.

## 5. Team-level views (client-side grouping)

Group records by `hubspot_owner_id`, join to `owners list` for human-readable emails:

```bash
hubspot objects search --type deals --filter "dealstage!=closedwon AND dealstage!=closedlost" \
  --properties hubspot_owner_id --format json \
| jq '.data | group_by(.properties.hubspot_owner_id)
       | map({owner_id: .[0].properties.hubspot_owner_id, count: length})' \
> /tmp/by-owner.json

hubspot owners list \
| jq --slurpfile by /tmp/by-owner.json -r \
     '. as $o | $by[0][] | select(.owner_id==$o.id) | "\($o.email)\t\(.count)"'
```
