---
name: ticket-resolution
description: Create, triage, advance, and close HubSpot support tickets — pipeline discovery, contact/company association, priority queues, bulk stage moves, resolution close-out.
triggers:
  - "create ticket"
  - "support ticket"
  - "triage tickets"
  - "open tickets"
  - "resolve ticket"
  - "close ticket"
  - "advance ticket"
  - "ticket pipeline"
  - "unassigned tickets"
  - "reassign ticket"
---

Read `bulk-operations/SKILL.md` first — JSONL piping, batch read, pagination, dry-run/digest/confirm, and `hubspot history` recovery live there. `hubspot <command> --help` is authoritative. Tickets use the `tickets` object type (plural, e.g. `tickets:45123`).

## 1. Discover pipeline + stages (portal-specific, run every session)

Stage IDs differ in every portal — never hard-code them.

```bash
hubspot pipelines list --object tickets --format table
hubspot pipelines stages --object tickets --pipeline <pipeline_id> --format table
```

The stage table prints each stage's `ID` and `Label` ("New", "Waiting on contact", "Closed", etc.).

## 2. Verify enum option values for THIS portal

`hs_ticket_priority`, `hs_ticket_category`, and `hs_resolution` are all `enumeration` properties — option values are portal-configurable and `hubspot properties get` does NOT return them. Discover by probing or by reading live records:

```bash
# Probe: send an invalid value; the 400 error lists the allowed options.
hubspot objects update --type tickets <some_ticket_id> --property hs_resolution=__probe__
# error: "was not one of the allowed options: [ISSUE_FIXED, FEATURE_REQUEST_TRACKED, ...]"

# Or read values already in use:
hubspot objects list --type tickets --limit 10 \
  --properties hs_ticket_priority,hs_ticket_category,hs_resolution
```

Do NOT assume HubSpot defaults — read the portal.

## 3. Create a ticket and associate it

`subject` is the only practically-required property. Skipping `hs_pipeline`/`hs_pipeline_stage` lands the ticket in the default pipeline's first stage.

```bash
hubspot objects create --type tickets \
  --property subject="Login error on mobile app" \
  --property content="User reports 401 since v3.2 release." \
  --property hs_pipeline=<pipeline_id> \
  --property hs_pipeline_stage=<new_stage_id> \
  --property hs_ticket_priority=<value_from_step_2> \
  --property hs_ticket_category=<value_from_step_2>
# Capture the "id" from the output JSON.

hubspot associations create --from tickets:<ticket_id> --to contacts:<contact_id>
hubspot associations create --from tickets:<ticket_id> --to companies:<company_id>
```

Bulk intake from a JSONL queue (see `bulk-operations/resources/json-patterns.md` for reshape patterns):

```bash
cat support_requests.jsonl \
| jq -c '{properties:{subject:.subject, content:.description,
    hs_pipeline:"<pipeline_id>", hs_pipeline_stage:"<new_stage_id>",
    hs_ticket_priority:"<priority>", hs_ticket_category:"<category>"}}' \
| hubspot objects create --type tickets
```

## 4. Triage queries

```bash
# Open tickets by priority
hubspot objects search --type tickets \
  --filter "hs_pipeline_stage=<open_stage_id> AND hs_ticket_priority=HIGH" \
  --properties subject,hubspot_owner_id,createdate

# Unassigned
hubspot objects search --type tickets \
  --filter "!hubspot_owner_id AND hs_pipeline_stage=<open_stage_id>" \
  --properties subject,hs_ticket_priority,createdate
```

Filter by owner with `hubspot_owner_id=<id>` (find IDs via `hubspot owners list --format table`).

## 5. Advance tickets through stages (bulk update from search)

```bash
hubspot objects search --type tickets \
  --filter "hs_ticket_category=BILLING_ISSUE AND hs_pipeline_stage=<new_stage_id>" \
| jq -c '{id, properties:{hs_pipeline_stage:"<waiting_stage_id>"}}' \
| hubspot objects update --type tickets --dry-run
```

Re-pipe the same search without `--dry-run` to execute. For >100 rows, follow the `--digest/--confirm` flow in `bulk-operations/SKILL.md` ("Safe destructive workflow"). Reassign in bulk works identically with `{hubspot_owner_id:"<new>"}`.

## 6. Log a resolution note

Activity creation lives in `sales-execution/SKILL.md` (notes/calls/meetings/tasks). After creating the note there, link it: `hubspot associations create --from notes:<note_id> --to tickets:<ticket_id>`.

## 7. Close the ticket

`hs_resolution` is an enumeration — pass an allowed option value from Step 2, not free text. HubSpot then computes `hs_is_closed=true`, `closed_date`, and `time_to_close`.

```bash
hubspot objects update --type tickets <ticket_id> \
  --property hs_pipeline_stage=<closed_stage_id> \
  --property hs_resolution=<allowed_resolution_value>
```

## Known limitations

- `properties get`/`list` do not return enum options — probe via update error or read live records (CLI ask logged).
- No Conversations/Inbox API surface — chat threads and inbox emails are not CLI-accessible.
