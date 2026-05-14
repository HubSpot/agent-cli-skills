---
name: ticket-resolution
description: Resolve customer issues quickly by creating and triaging support tickets, associating them to contacts and companies, moving them through the pipeline, and logging resolution notes.
triggers:
  - "create ticket"
  - "support ticket"
  - "customer issue"
  - "ticket pipeline"
  - "resolve issue"
  - "service ticket"
  - "triage tickets"
  - "open tickets"
  - "customer support"
  - "ticket lookup"
  - "find ticket"
  - "review ticket"
  - "check ticket status"
  - "ticket by contact"
  - "look up ticket"
  - "ticket lookup and review"
---

## Resources

| File | When to use |
|---|---|
| `resources/ticket-properties.md` | Full ticket property reference with priority and category enum values, and the commands to run first for getting portal-specific pipeline/stage IDs |
| `resources/batch-ticket-intake.sh` | Script that reads a CSV of support requests and bulk-creates tickets, with optional contact association by email |

## Context
HubSpot tickets track customer-reported issues through a pipeline of stages from intake to resolution. This skill covers the full ticket lifecycle: discovering pipeline/stage IDs, creating tickets, associating them to contacts and companies, triaging by priority, moving through stages, and logging resolution notes.

## Property Reference — Tickets

| Property | Type | Notes |
|---|---|---|
| subject | string | Required — ticket title |
| content | string | Ticket description |
| hs_pipeline | string | Pipeline ID — always get from `hubspot pipelines list --object tickets` |
| hs_pipeline_stage | string | Stage ID — portal-specific, get from `hubspot pipelines stages --object tickets` |
| hubspot_owner_id | string | Assigned support agent |
| hs_ticket_priority | enumeration | LOW, MEDIUM, HIGH, URGENT |
| hs_ticket_category | enumeration | PRODUCT_ISSUE, BILLING_ISSUE, FEATURE_REQUEST, GENERAL_INQUIRY, OTHER |
| hs_resolution | string | Resolution notes |
| createdate | datetime | Read-only |
| hs_lastmodifieddate | datetime | Read-only |

## Key Workflows

### Step 0: Always Discover Pipeline and Stage IDs First

Ticket stage IDs are portal-specific. Run these commands before creating any tickets.

```bash
# List all ticket pipelines
hubspot pipelines list --object tickets --format table

# Get stages for a specific pipeline
hubspot pipelines stages --object tickets --pipeline <pipeline_id> --format table
```

### Create a Ticket and Associate to Contact

```bash
# Step 1: create the ticket
hubspot objects create --type tickets \
  --property subject="Login error on mobile app" \
  --property content="User reports unable to login since update 3.2. Error: 401 Unauthorized." \
  --property hs_pipeline=<pipeline_id> \
  --property hs_pipeline_stage=<new_stage_id> \
  --property hs_ticket_priority=HIGH \
  --property hs_ticket_category=PRODUCT_ISSUE
# Note the returned ticket ID

# Step 2: associate to contact (mandatory for CRM visibility)
hubspot associations create --from tickets:<ticket_id> --to contacts:<contact_id>

# Step 3: associate to company
hubspot associations create --from tickets:<ticket_id> --to companies:<company_id>
```

### Batch Create Tickets from a Support Queue

```bash
# Input format (support_requests.jsonl):
# {"subject":"Issue 1","description":"Details about issue 1"}
# {"subject":"Issue 2","description":"Details about issue 2"}

cat support_requests.jsonl \
| jq -c '{properties: {
    subject: .subject,
    content: .description,
    hs_pipeline: "<pipeline_id>",
    hs_pipeline_stage: "<new_stage_id>",
    hs_ticket_priority: "MEDIUM",
    hs_ticket_category: "GENERAL_INQUIRY"
  }}' \
| hubspot objects create --type tickets \
> created_tickets.jsonl
```

### Find All Open Tickets by Priority

```bash
# All URGENT tickets
hubspot objects search --type tickets \
  --filter "hs_pipeline_stage=<open_stage_id> AND hs_ticket_priority=URGENT" \
  --properties subject,hubspot_owner_id,createdate

# All HIGH priority tickets
hubspot objects search --type tickets \
  --filter "hs_pipeline_stage=<open_stage_id> AND hs_ticket_priority=HIGH" \
  --properties subject,hubspot_owner_id,hs_ticket_category
```

### Find Unassigned Tickets

```bash
hubspot objects search --type tickets \
  --filter "!hubspot_owner_id AND hs_pipeline_stage=<open_stage_id>" \
  --properties subject,hs_ticket_priority,createdate
```

### Move a Ticket to the Resolved Stage

```bash
hubspot objects update --type tickets <ticket_id> \
  --property hs_pipeline_stage=<resolved_stage_id> \
  --property hs_resolution="Issue was fixed in v3.3. Customer notified via email."
```

### Bulk Close Tickets by Category

```bash
hubspot objects search --type tickets \
  --filter "hs_ticket_category=FEATURE_REQUEST AND hs_pipeline_stage=<open_stage_id>" \
| jq -c '{id, properties: {
    hs_pipeline_stage: "<closed_stage_id>",
    hs_resolution: "Logged as a product feature request. No immediate fix scheduled."
  }}' \
| hubspot objects update --type tickets --dry-run

hubspot objects search --type tickets \
  --filter "hs_ticket_category=FEATURE_REQUEST AND hs_pipeline_stage=<open_stage_id>" \
| jq -c '{id, properties: {
    hs_pipeline_stage: "<closed_stage_id>",
    hs_resolution: "Logged as a product feature request. No immediate fix scheduled."
  }}' \
| hubspot objects update --type tickets
```

### Log a Note on a Ticket

```bash
# Create the note
hubspot objects create --type notes \
  --property hs_note_body="Called customer. Issue confirmed and escalated to engineering. ETA: 48 hours." \
  --property hs_timestamp=$(date +%s)000

# Associate note to ticket (mandatory)
hubspot associations create --from notes:<note_id> --to tickets:<ticket_id>
```

### Reassign Tickets to a Different Agent

```bash
# Get owner IDs
hubspot owners list --format table

# Reassign
hubspot objects search --type tickets \
  --filter "hubspot_owner_id=<old_agent_id> AND hs_pipeline_stage=<open_stage_id>" \
| jq -c '{id, properties: {hubspot_owner_id: "<new_agent_id>"}}' \
| hubspot objects update --type tickets
```

### Get All Contacts Associated with a Ticket

```bash
hubspot associations list --from tickets:<ticket_id> --to contacts --format jsonl
```

## Known Limitations
- No Conversations/Inbox API — live chat threads and email conversations in the HubSpot Inbox are not accessible from the CLI. Use the HubSpot UI to manage inbox conversations.
- Ticket stage IDs are always portal-specific. Always run `hubspot pipelines stages --object tickets` before creating or updating tickets.
- Notes must be associated to tickets immediately after creation — unassociated notes are invisible in the ticket timeline.
- Bulk ticket creation makes one API call per ticket. For large batches, test with `head -n 20` first to avoid rate limits.
