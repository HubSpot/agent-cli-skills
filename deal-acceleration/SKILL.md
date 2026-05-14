---
name: deal-acceleration
description: Move opportunities to close faster by identifying stalled deals, deals past close date, and deals with no recent activity, then taking bulk action to update stages or reassign ownership.
triggers:
  - "stalled deals"
  - "deal velocity"
  - "push deals to close"
  - "move deals forward"
  - "deals past close date"
  - "accelerate pipeline"
  - "overdue deals"
  - "deals with no activity"
---

## Resources

| File | When to use |
|---|---|
| `resources/stalled-deal-queries.md` | Ready-to-run filter expressions for every stalled-deal scenario with dynamic date computation for macOS and Linux |
| `resources/bulk-stage-update.sh` | Script that moves all deals from one stage to another, with dry-run preview and confirmation before executing |

## Context
Pipeline health degrades when deals sit in stages without movement. This skill covers identifying stalled opportunities using date and status filters, bulk-extending close dates, moving deals to the next stage, flagging deals that need attention, and reassigning ownership — all without leaving the terminal.

## Property Reference — Deals

| Property | Type | Notes |
|---|---|---|
| dealname | string | |
| dealstage | string | Stage ID — portal-specific |
| pipeline | string | Pipeline ID |
| amount | number | |
| closedate | string | YYYY-MM-DD format |
| hubspot_owner_id | string | |
| hs_deal_stage_probability | number | Read-only |
| hs_is_closed | boolean | Read-only — true if deal is won or lost |
| hs_is_closed_won | boolean | Read-only |
| notes_last_contacted | datetime | Last logged contact activity |
| hs_last_sales_activity_date | datetime | Read-only |

## Key Workflows

### Discover Pipeline and Stage IDs (Always Do This First)

```bash
hubspot pipelines list --object deals --format table
hubspot pipelines stages --object deals --pipeline <pipeline_id> --format table
```

### Find Stalled Deals (Past Close Date, Still Open)

```bash
hubspot objects search --type deals \
  --filter "closedate<2025-01-01 AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id,amount
```

### Find Deals with No Recent Activity

```bash
hubspot objects search --type deals \
  --filter "hs_last_sales_activity_date<2025-03-01" \
  --properties dealname,hubspot_owner_id,closedate,dealstage
```

### Find Deals with No Activity At All

```bash
hubspot objects search --type deals \
  --filter "!hs_last_sales_activity_date AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id
```

### Bulk Extend Close Dates

```bash
# Dry-run first
hubspot objects search --type deals \
  --filter "dealstage=<stage_id> AND closedate<2025-01-01 AND hs_is_closed!=true" \
| jq -c '{id, properties: {closedate: "2025-06-30"}}' \
| hubspot objects update --type deals --dry-run

# Execute
hubspot objects search --type deals \
  --filter "dealstage=<stage_id> AND closedate<2025-01-01 AND hs_is_closed!=true" \
| jq -c '{id, properties: {closedate: "2025-06-30"}}' \
| hubspot objects update --type deals
```

### Move a Single Deal to the Next Stage

```bash
# Step 1: get current stage IDs
hubspot pipelines stages --object deals --pipeline <pipeline_id> --format table

# Step 2: update the deal's stage
hubspot objects update --type deals <deal_id> \
  --property dealstage=<next_stage_id>
```

### Bulk Move Deals from One Stage to Another

```bash
hubspot objects search --type deals \
  --filter "dealstage=<current_stage_id>" \
| jq -c '{id, properties: {dealstage: "<next_stage_id>"}}' \
| hubspot objects update --type deals --dry-run

hubspot objects search --type deals \
  --filter "dealstage=<current_stage_id>" \
| jq -c '{id, properties: {dealstage: "<next_stage_id>"}}' \
| hubspot objects update --type deals
```

### Flag Stalled Deals with a Custom Property

```bash
# Step 1: create the property (run once per portal)
hubspot properties create \
  --object deals \
  --name needs_attention \
  --label "Needs Attention" \
  --type enumeration \
  --field-type select

# Step 2: flag stalled deals
hubspot objects search --type deals \
  --filter "closedate<2025-01-01 AND hs_is_closed!=true" \
| jq -c '{id, properties: {needs_attention: "true"}}' \
| hubspot objects update --type deals
```

### Reassign Stalled Deals to a New Owner

```bash
# Step 1: get owner IDs
hubspot owners list --format table

# Step 2: reassign
hubspot objects search --type deals \
  --filter "closedate<2025-01-01 AND hs_is_closed!=true AND hubspot_owner_id=<old_owner_id>" \
| jq -c '{id, properties: {hubspot_owner_id: "<new_owner_id>"}}' \
| hubspot objects update --type deals
```

### Find Won and Lost Deals

```bash
# Won deals
hubspot objects search --type deals \
  --filter "hs_is_closed_won=true" \
  --properties dealname,amount,closedate,hubspot_owner_id

# Lost deals (closed but not won)
hubspot objects search --type deals \
  --filter "hs_is_closed=true AND hs_is_closed_won!=true" \
  --properties dealname,amount,closedate
```

### Check Activity on a Specific Deal

```bash
# Get calls associated to the deal
hubspot associations list --from deals:<deal_id> --to calls --format jsonl

# Get a specific call record
hubspot objects get --type calls <call_id> \
  --properties hs_call_title,hs_call_body,hs_call_status,hs_timestamp
```

## Known Limitations
- No unified activity query across all engagement types. To audit last activity per deal, query each type separately: calls, notes, meetings, tasks via `hubspot associations list --from deals:<id> --to <type>`.
- No sequences/cadences API — cannot enroll contacts in outreach cadences from the CLI.
- Deal stage IDs are always portal-specific. Always call `hubspot pipelines stages` first.
- `closedate` filter values use YYYY-MM-DD format. `hs_last_sales_activity_date` is a datetime — use a date string (e.g., `2025-03-01`) for comparison.
- Bulk mutations make one API call per deal. For large pipelines (> 100 deals), use the pagination loop from the `bulk-operations` skill.
