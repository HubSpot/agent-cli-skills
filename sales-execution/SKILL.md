---
name: sales-execution
description: Log sales activities (calls, notes, meetings, tasks) against contacts and deals to maintain complete CRM engagement records and drive consistent follow-up.
triggers:
  - "log a call"
  - "create task"
  - "log activity"
  - "sales note"
  - "follow-up task"
  - "log meeting"
  - "sales consistency"
  - "log engagement"
  - "log note"
  - "log meeting notes"
---

## Resources

| File | When to use |
|---|---|
| `resources/activity-properties-reference.md` | Complete property tables for calls, notes, meetings, and tasks — including all enum values and timestamp conversion examples |
| `resources/log-activity-and-associate.sh` | Reusable shell functions for creating each activity type and immediately associating it to a CRM record |

## Context
Sales consistency requires every customer interaction to be logged in the CRM. This skill covers creating calls, notes, meetings, and tasks, then immediately associating them to the right contacts and deals. Unassociated activities are invisible in the HubSpot CRM — the association step is mandatory.

## Property Reference — Calls

| Property | Type | Notes |
|---|---|---|
| hs_call_title | string | |
| hs_call_body | string | Call notes |
| hs_call_duration | number | Duration in milliseconds |
| hs_call_direction | enumeration | INBOUND, OUTBOUND |
| hs_call_status | enumeration | BUSY, CALLING_CRM_USER, CANCELED, COMPLETED, CONNECTING, FAILED, IN_PROGRESS, MISSED, NO_ANSWER, QUEUED, RINGING |
| hs_timestamp | number | Unix timestamp in milliseconds |

## Property Reference — Notes

| Property | Type | Notes |
|---|---|---|
| hs_note_body | string | Note content (HTML supported) |
| hs_timestamp | number | Unix timestamp in milliseconds |

## Property Reference — Meetings

| Property | Type | Notes |
|---|---|---|
| hs_meeting_title | string | |
| hs_meeting_body | string | Meeting notes |
| hs_meeting_start_time | number | Unix timestamp in milliseconds |
| hs_meeting_end_time | number | Unix timestamp in milliseconds |
| hs_meeting_outcome | enumeration | SCHEDULED, COMPLETED, RESCHEDULED, NO_SHOW, CANCELLED |
| hs_timestamp | number | Unix timestamp in milliseconds |

## Property Reference — Tasks

| Property | Type | Notes |
|---|---|---|
| hs_task_subject | string | Task title |
| hs_task_body | string | Task notes |
| hs_task_status | enumeration | NOT_STARTED, IN_PROGRESS, COMPLETED, DEFERRED, WAITING |
| hs_task_priority | enumeration | LOW, MEDIUM, HIGH |
| hs_task_type | enumeration | TODO, CALL, EMAIL |
| hs_timestamp | number | Due date as Unix timestamp in milliseconds |

**Getting the current Unix timestamp in milliseconds:**
- Linux: `date +%s%3N`
- macOS: `$(date +%s)000`

## Key Workflows

### Log a Call and Associate to Contact and Deal

```bash
# Create the call
hubspot objects create --type calls \
  --property hs_call_title="Discovery Call" \
  --property hs_call_body="Discussed budget and timeline. Contact confirmed $50K budget." \
  --property hs_call_direction=OUTBOUND \
  --property hs_call_status=COMPLETED \
  --property hs_timestamp=$(date +%s)000
# Note the returned call ID

# Associate to contact (mandatory — unassociated calls are invisible)
hubspot associations create --from calls:<call_id> --to contacts:<contact_id>

# Associate to deal
hubspot associations create --from calls:<call_id> --to deals:<deal_id>
```

### Log a Note

```bash
hubspot objects create --type notes \
  --property hs_note_body="Sent proposal via email. Follow-up scheduled for Friday." \
  --property hs_timestamp=$(date +%s)000

hubspot associations create --from notes:<note_id> --to contacts:<contact_id>
hubspot associations create --from notes:<note_id> --to deals:<deal_id>
```

### Log a Meeting

```bash
hubspot objects create --type meetings \
  --property hs_meeting_title="Demo Call — Acme Corp" \
  --property hs_meeting_body="Walked through product demo. Strong interest in enterprise plan." \
  --property hs_meeting_outcome=COMPLETED \
  --property hs_meeting_start_time=1735689600000 \
  --property hs_meeting_end_time=1735693200000 \
  --property hs_timestamp=1735689600000

hubspot associations create --from meetings:<meeting_id> --to contacts:<contact_id>
hubspot associations create --from meetings:<meeting_id> --to deals:<deal_id>
```

### Create a Follow-Up Task

```bash
hubspot objects create --type tasks \
  --property hs_task_subject="Follow up on proposal sent 2025-02-01" \
  --property hs_task_body="Call to confirm receipt and answer questions" \
  --property hs_task_priority=HIGH \
  --property hs_task_status=NOT_STARTED \
  --property hs_task_type=CALL \
  --property hs_timestamp=1738368000000

hubspot associations create --from tasks:<task_id> --to contacts:<contact_id>
hubspot associations create --from tasks:<task_id> --to deals:<deal_id>
```

### Check Open Tasks for a Contact

```bash
hubspot associations list --from contacts:<contact_id> --to tasks --format jsonl \
| jq -r '.id' \
| xargs -I{} hubspot objects get --type tasks {} \
    --properties hs_task_subject,hs_task_status,hs_task_priority,hs_timestamp
```

### Bulk Create Follow-Up Tasks for All Deals in a Stage

```bash
# Create tasks and save the output
hubspot objects search --type deals --filter "dealstage=<stage_id>" \
  --properties dealname \
| jq -c '{
    deal_id: .id,
    properties: {
      hs_task_subject: ("Follow up: " + .properties.dealname),
      hs_task_priority: "HIGH",
      hs_task_status: "NOT_STARTED",
      hs_task_type: "CALL",
      hs_timestamp: 1738368000000
    }
  }' \
> deals_for_tasks.jsonl

# Create tasks
cat deals_for_tasks.jsonl \
| jq -c '{properties}' \
| hubspot objects create --type tasks \
> created_tasks.jsonl

# Associate each task to its deal (requires both files)
paste -d'\n' \
  <(cat created_tasks.jsonl | jq -r '.id') \
  <(cat deals_for_tasks.jsonl | jq -r '.deal_id') \
| paste - - \
| while read task_id deal_id; do
    hubspot associations create --from tasks:$task_id --to deals:$deal_id
  done
```

### View All Activities on a Deal

```bash
# Calls
hubspot associations list --from deals:<deal_id> --to calls --format jsonl \
| jq -r '.id' \
| xargs -I{} hubspot objects get --type calls {} \
    --properties hs_call_title,hs_call_status,hs_timestamp

# Notes
hubspot associations list --from deals:<deal_id> --to notes --format jsonl \
| jq -r '.id' \
| xargs -I{} hubspot objects get --type notes {} \
    --properties hs_note_body,hs_timestamp

# Tasks
hubspot associations list --from deals:<deal_id> --to tasks --format jsonl \
| jq -r '.id' \
| xargs -I{} hubspot objects get --type tasks {} \
    --properties hs_task_subject,hs_task_status,hs_task_priority
```

## Known Limitations
- **Activities MUST be associated immediately after creation.** Unassociated calls, notes, meetings, and tasks are invisible in the HubSpot CRM UI.
- No unified engagements endpoint — calls, notes, meetings, and tasks must each be queried separately.
- Unix timestamps are in milliseconds. Use `$(date +%s)000` on macOS or `date +%s%3N` on Linux for the current time.
- No sequences/cadences API — cannot enroll contacts in automated outreach cadences from the CLI.
