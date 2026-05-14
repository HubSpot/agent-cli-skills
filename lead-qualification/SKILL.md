---
name: lead-qualification
description: Turn demand into qualified sales opportunities by finding MQL contacts, creating deals with the correct pipeline stage, associating records, and promoting lifecycle stages.
triggers:
  - "qualify lead"
  - "MQL to SQL"
  - "create deal from lead"
  - "lead qualification"
  - "promote lead"
  - "convert contact to opportunity"
  - "qualify MQL"
  - "move to sales qualified"
---

## Resources

| File | When to use |
|---|---|
| `resources/lifecycle-stage-progression.md` | All 8 lifecycle stages in order with API values, meanings, transition triggers, and the CLI commands to move a contact between stages |
| `resources/lead-status-values.md` | All 8 `hs_lead_status` enum values with meanings, when to set each, and filter expressions for finding contacts at each status |
| `resources/qualification-checklist.md` | Step-by-step checklist with CLI commands to verify a contact is ready to become an SQL before creating a deal |

## Context
Lead qualification is the process of moving a contact from a marketing-generated lead (MQL) to a sales-accepted opportunity (SQL) by creating a deal and handing it off to sales. This skill covers the full qualification workflow: finding ready MQLs, creating the deal in the right pipeline stage, linking all records together, and updating the contact's lifecycle status.

## Property Reference — Contacts

| Property | Type | Notes |
|---|---|---|
| lifecyclestage | enumeration | subscriber → lead → marketingqualifiedlead → salesqualifiedlead → opportunity → customer |
| hs_lead_status | enumeration | NEW, OPEN, IN_PROGRESS, OPEN_DEAL, UNQUALIFIED, ATTEMPTED_TO_CONTACT, CONNECTED, BAD_TIMING |
| hs_analytics_source | string | Read-only — original lead source |
| num_associated_deals | number | Read-only |
| hubspot_owner_id | string | Numeric owner ID |

## Property Reference — Deals (Required Fields)

| Property | Type | Notes |
|---|---|---|
| dealname | string | Required |
| pipeline | string | Pipeline ID — always get from `hubspot pipelines list --object deals` |
| dealstage | string | Stage ID — portal-specific, get from `hubspot pipelines stages` |
| amount | number | Deal value (set to 0 if unknown at qualification time) |
| hubspot_owner_id | string | Sales rep's owner ID |

## Key Workflows

### Full MQL to SQL Qualification Pipeline

```bash
# Step 1: discover pipeline and stage IDs for your portal
hubspot pipelines list --object deals --format table
hubspot pipelines stages --object deals --pipeline "Sales Pipeline" --format table

# Step 2: find MQL contacts ready to qualify
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND hs_lead_status=CONNECTED" \
  --properties email,firstname,lastname,company,hubspot_owner_id

# Step 3: for each contact, check their company association
hubspot associations list --from contacts:<contact_id> --to companies --format jsonl

# Step 4: create the deal
hubspot objects create --type deals \
  --property dealname="<Company> - Inbound" \
  --property pipeline=<pipeline_id> \
  --property dealstage=<qualified_stage_id> \
  --property amount=0 \
  --property hubspot_owner_id=<owner_id>
# Note the returned deal ID from the output

# Step 5: associate deal to contact and company
hubspot associations create --from deals:<deal_id> --to contacts:<contact_id>
hubspot associations create --from deals:<deal_id> --to companies:<company_id>

# Step 6: promote the contact's lifecycle and lead status
hubspot objects update --type contacts <contact_id> \
  --property lifecyclestage=salesqualifiedlead \
  --property hs_lead_status=OPEN_DEAL
```

### Find All MQLs Awaiting Qualification

```bash
# MQLs with no deal yet
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND num_associated_deals=0" \
  --properties email,firstname,lastname,company,hs_lead_status

# MQLs who have been contacted and are ready
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND hs_lead_status=CONNECTED" \
  --properties email,firstname,lastname,company
```

### Disqualify a Lead

```bash
hubspot objects update --type contacts <contact_id> \
  --property hs_lead_status=UNQUALIFIED
```

### Find All SQLs (Sales Qualified Leads)

```bash
hubspot objects search --type contacts \
  --filter "lifecyclestage=salesqualifiedlead" \
  --properties email,firstname,lastname,hubspot_owner_id,hs_lead_status
```

### Find Leads by Original Source

```bash
hubspot objects search --type contacts \
  --filter "hs_analytics_source=PAID_SEARCH AND lifecyclestage=lead" \
  --properties email,firstname,hs_analytics_source,lifecyclestage
```

### Get Owner IDs for Deal Assignment

```bash
# Always resolve owner IDs at runtime
hubspot owners list --format table

# Find a specific rep's owner ID
hubspot owners list | jq -r 'select(.email == "salesrep@company.com") | .id'
```

## Known Limitations
- No sequences/cadences API — you cannot enroll contacts in outreach sequences from the CLI. Create a follow-up task instead using the `sales-execution` skill.
- Bulk qualification (qualifying many MQLs in one pass) requires a shell loop: the association step needs the new deal ID returned from each `create` call, so deals cannot be created and associated in a single piped command.
- `lifecyclestage` field: HubSpot enforces a forward-only progression for most stages. Setting a contact's lifecycle stage to an earlier stage may be blocked by your portal settings.
- Pipeline and stage IDs are always portal-specific. Never hardcode them.
