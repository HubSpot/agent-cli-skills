---
name: sales-execution
description: Log sales activities — calls, notes, meetings, tasks — against contacts and deals, with the mandatory create-then-associate step that makes them visible in the CRM.
triggers:
  - "log a call"
  - "log a note"
  - "log a meeting"
  - "create task"
  - "follow-up task"
  - "log activity"
  - "log engagement"
---

## Resources

| File | When to use |
|---|---|
| `resources/activity-properties-reference.md` | Property names and enum values for calls/notes/meetings/tasks. Keep open while writing `objects create` — enum values are not discoverable via `hubspot properties get` today. |

Read `bulk-operations/SKILL.md` first — this skill assumes its batching, pipe, and dry-run patterns.

## The two non-obvious rules

**1. Activities are invisible until associated.** `hubspot objects create --type calls ...` alone produces a record nobody can see in the CRM UI. Always follow with `hubspot associations create --from calls:<id> --to contacts:<id>` (and the deal, if relevant) before stopping.

**2. Timestamps differ between write and read.**

| Path | Field | Format |
|---|---|---|
| `objects create --property hs_timestamp=...` | `hs_timestamp` | **Unix ms** (13 digits) |
| `objects get --type calls <id>` returns | `properties.hs_timestamp` | Unix ms (string) |
| `activities list --contact <id>` returns | `timestamp` (flat, top-level) | **ISO 8601** (e.g. `2024-01-15T10:00:00Z`) |

Current Unix ms: `$(date +%s)000` (macOS) or `$(date +%s%3N)` (Linux). `activities list` rows are `{"id","type","timestamp","title","body","status","owner_id"}` — the cross-type timeline read shape, no raw property names.

## Create + associate, by type

```bash
# CALL
call_id=$(hubspot objects create --type calls \
  --property hs_call_title="Discovery call" \
  --property hs_call_body="Confirmed $50K budget, Q2 timeline." \
  --property hs_call_direction=OUTBOUND \
  --property hs_call_status=COMPLETED \
  --property hs_call_duration=1800000 \
  --property hs_timestamp=$(date +%s)000 \
  --format json | jq -r '.id')
hubspot associations create --from calls:$call_id --to contacts:149
hubspot associations create --from calls:$call_id --to deals:456

# NOTE
note_id=$(hubspot objects create --type notes \
  --property hs_note_body="Sent proposal. Follow-up Friday." \
  --property hs_timestamp=$(date +%s)000 \
  --format json | jq -r '.id')
hubspot associations create --from notes:$note_id --to deals:456

# MEETING — start/end in Unix ms; reuse start as hs_timestamp
start=$(date +%s)000; end=$(( ${start%000} + 3600 ))000
meeting_id=$(hubspot objects create --type meetings \
  --property hs_meeting_title="Demo — Acme" --property hs_meeting_outcome=COMPLETED \
  --property hs_meeting_start_time=$start --property hs_meeting_end_time=$end \
  --property hs_timestamp=$start --format json | jq -r '.id')
hubspot associations create --from meetings:$meeting_id --to contacts:149

# TASK — hs_timestamp is the DUE DATE, not creation time
due=$(( $(date -v+7d +%s) * 1000 ))   # macOS; Linux: date -d '7 days' +%s
task_id=$(hubspot objects create --type tasks \
  --property hs_task_subject="Confirm proposal received" \
  --property hs_task_priority=HIGH \
  --property hs_task_status=NOT_STARTED \
  --property hs_task_type=CALL \
  --property hs_timestamp=$due \
  --format json | jq -r '.id')
hubspot associations create --from tasks:$task_id --to deals:456
```

## Open tasks for a contact — two CLI calls, no xargs

`associations list` emits `{"id","type"}` per row; `objects get` reads from stdin in one batch call (see `bulk-operations/SKILL.md` "Read in batch").

```bash
hubspot associations list --from contacts:149 --to tasks \
| hubspot objects get --type tasks \
    --properties hs_task_subject,hs_task_status,hs_task_priority,hs_timestamp \
| jq -c 'select(.properties.hs_task_status != "COMPLETED")'
```

## Bulk: follow-up task per deal in a stage

The deal ID and the task ID must travel together. Persist the deal payload to a file, create tasks (output order matches input order — see bulk-operations), then zip the two ID lists line-by-line and stream association pairs in one call.

```bash
due=$(( $(date -v+7d +%s) * 1000 ))

# 1. Per-deal payload, deal_id retained alongside the create payload.
hubspot objects search --type deals --filter "dealstage=appointmentscheduled" \
  --properties dealname \
| jq -c --argjson due "$due" '{deal_id: .id, payload: {properties: {
    hs_task_subject: ("Follow up: " + .properties.dealname),
    hs_task_priority: "HIGH", hs_task_status: "NOT_STARTED", hs_task_type: "CALL",
    hs_timestamp: ($due|tostring)
  }}}' > /tmp/deal_tasks.jsonl

# 2. Create tasks; one CLI call for the whole batch.
jq -c '.payload' /tmp/deal_tasks.jsonl \
| hubspot objects create --type tasks > /tmp/created_tasks.jsonl

# 3. Zip and stream association pairs through stdin.
paste \
  <(jq -r '.deal_id' /tmp/deal_tasks.jsonl) \
  <(jq -r '.id'      /tmp/created_tasks.jsonl) \
| jq -Rc 'split("\t") | {from:("tasks:"+.[1]), to:("deals:"+.[0])}' \
| hubspot associations create
```

For >100 rows, apply the dry-run / digest / confirm pattern from `bulk-operations/SKILL.md`.

## Known constraints

Activities must be associated immediately or they're invisible in the CRM UI. `properties get` doesn't return enum option values for activity types — use the reference. No sequences/cadences in the CLI.
