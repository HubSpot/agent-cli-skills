---
name: communication-history
description: Retrieve all activity history for a CRM record — calls, emails, notes, meetings, and tasks — and assemble pre-call research briefs.
triggers:
  - "pre-call research"
  - "review notes"
  - "call history"
  - "email history"
  - "recent activity"
  - "note review"
  - "communication history"
  - "prepare for call"
  - "meeting prep"
  - "what happened with this contact"
  - "call record review"
  - "email record review"
  - "note review for context"
  - "email history review"
  - "pre-call research and preparation"
---

## Resources

| File | When to use |
|---|---|
| `resources/pre-call-research.sh` | Script that assembles a complete pre-call brief for a contact: contact properties, associated company, open deals, and recent activity history |

## Context
Activity history lives in five separate CRM object types: calls, notes, emails, meetings, and tasks. The `hubspot activities list` command retrieves all of them for a given record in a single operation, sorted newest first. This skill covers reading that history, filtering it by type or date, and assembling it into a useful pre-call brief.

## Property Reference — Activity Types

| Type | Key properties |
|---|---|
| CALL | `hs_call_title`, `hs_call_body`, `hs_call_status` (COMPLETED/CANCELED/etc.), `hs_timestamp`, `hubspot_owner_id` |
| NOTE | `hs_note_body`, `hs_timestamp`, `hubspot_owner_id` |
| EMAIL | `hs_email_subject`, `hs_email_text`, `hs_email_status`, `hs_timestamp`, `hubspot_owner_id` |
| MEETING | `hs_meeting_title`, `hs_meeting_body`, `hs_timestamp`, `hubspot_owner_id` |
| TASK | `hs_task_subject`, `hs_task_body`, `hs_task_status` (NOT_STARTED/COMPLETED/etc.), `hs_timestamp`, `hubspot_owner_id` |

`hs_timestamp` is returned as an ISO 8601 string (`2024-01-15T10:00:00.000Z`). Results are already sorted newest first.

## Key Workflows

### Get All Recent Activity for a Contact

```bash
hubspot activities list --contact 12345
```

### Get All Activity for a Deal or Company

```bash
hubspot activities list --deal 67890
hubspot activities list --company 11111
```

### Filter to a Specific Activity Type

```bash
# Only calls
hubspot activities list --contact 12345 --type CALL

# Only notes
hubspot activities list --contact 12345 --type NOTE

# Only emails
hubspot activities list --contact 12345 --type EMAIL
```

### Get the 10 Most Recent Activities

```bash
hubspot activities list --contact 12345 --limit 10
```

### Filter by Date Client-Side

ISO 8601 timestamps compare correctly as strings.

```bash
# Activity in the last 30 days (macOS)
CUTOFF=$(date -v-30d +%Y-%m-%dT%H:%M:%S)
hubspot activities list --contact 12345 \
| jq -c --arg cutoff "$CUTOFF" 'select(.timestamp > $cutoff)'

# Activity in the last 30 days (Linux)
CUTOFF=$(date -d '30 days ago' +%Y-%m-%dT%H:%M:%S)
hubspot activities list --contact 12345 \
| jq -c --arg cutoff "$CUTOFF" 'select(.timestamp > $cutoff)'
```

### Print a Compact Activity Timeline

```bash
hubspot activities list --contact 12345 --limit 20 \
| jq -r '"\(.timestamp[0:10])  \(.type)  \(.title)"'
```

### Pre-Call Research (Full Brief)

Combines contact properties, associated company, open deals, and recent activity.

```bash
contact_id=12345

echo "=== Contact ==="
hubspot objects get --type contacts $contact_id \
  --properties email,firstname,lastname,company,phone,jobtitle,lifecyclestage,hubspot_owner_id

echo ""
echo "=== Company ==="
hubspot associations list --from contacts:$contact_id --to companies --format jsonl \
| jq -r '.id' | head -1 \
| xargs -I{} hubspot objects get --type companies {} \
    --properties name,domain,industry,annualrevenue,numberofemployees

echo ""
echo "=== Open Deals ==="
hubspot associations list --from contacts:$contact_id --to deals --format jsonl \
| jq -r '.id' \
| xargs -I{} hubspot objects get --type deals {} \
    --properties dealname,amount,dealstage,closedate \
| jq -c 'select(.properties.hs_is_closed != "true")'

echo ""
echo "=== Recent Activity (last 10) ==="
hubspot activities list --contact $contact_id --limit 10 \
| jq -r '"\(.timestamp[0:10])  \(.type | .[0:8])  \(.title)"'
```

Use the `resources/pre-call-research.sh` script for a ready-to-run, formatted version.

## Known Limitations
- Results per type are limited to the IDs returned in the association list. HubSpot returns up to 100 association IDs per type. Contacts with very long activity histories may be truncated per type.
- `hs_timestamp` on some older records may be null or empty. These sort to the bottom.
- Activity body fields (`hs_call_body`, `hs_email_text`) can be very long. For table output, use `--limit` to keep the output readable.
