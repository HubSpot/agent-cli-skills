---
name: pipeline-revenue
description: Drive pipeline and revenue by creating deals from qualified contacts, associating them to the right companies, and monitoring pipeline health by stage.
triggers:
  - "create deal"
  - "marketing pipeline"
  - "deal creation"
  - "MQL to deal"
  - "pipeline health"
  - "deal from contact"
  - "add to pipeline"
  - "create opportunity"
---

## Resources

| File | When to use |
|---|---|
| `resources/deal-properties.md` | Full deal property reference including read-only fields and a reminder that `pipeline` and `dealstage` are always portal-specific IDs |
| `resources/mql-to-deal-pipeline.sh` | Complete script that searches MQL contacts, creates a deal per contact, associates to company, and promotes lifecycle stage — with dry-run mode |

## Context
Deals represent active revenue opportunities in HubSpot. Creating a deal requires portal-specific pipeline and stage IDs — these must always be discovered at runtime, never hardcoded. This skill covers the full lifecycle of deal creation: discovering pipeline IDs, creating deals, associating them to contacts and companies, and monitoring pipeline health.

## Property Reference — Deals

| Property | Type | Notes |
|---|---|---|
| dealname | string | Required |
| pipeline | string | Pipeline ID — always get from `hubspot pipelines list --object deals` |
| dealstage | string | Stage ID — portal-specific, get from `hubspot pipelines stages` |
| amount | number | Deal value |
| closedate | string | Format: YYYY-MM-DD |
| hubspot_owner_id | string | Numeric owner ID |
| dealtype | enumeration | newbusiness, existingbusiness |
| description | string | |
| hs_deal_stage_probability | number | Read-only — set by HubSpot based on stage |

## Key Workflows

### Step 0: Always Discover Pipeline and Stage IDs First

Pipeline and stage IDs are portal-specific. Run these before every deal creation workflow.

```bash
# List all deal pipelines
hubspot pipelines list --object deals --format table

# Get stages for a specific pipeline (use pipeline name or ID)
hubspot pipelines stages --object deals --pipeline "Sales Pipeline" --format table

# JSONL output for scripting
hubspot pipelines stages --object deals --pipeline "Sales Pipeline" --format jsonl
```

### Create a Single Deal and Associate It

```bash
# Step 1: discover pipeline and stage IDs (see above)

# Step 2: create the deal
hubspot objects create --type deals \
  --property dealname="Acme Corp - New Business" \
  --property pipeline=<pipeline_id> \
  --property dealstage=<stage_id> \
  --property amount=15000 \
  --property closedate=2025-06-30 \
  --property dealtype=newbusiness

# Step 3: associate deal to contact
hubspot associations create --from deals:<deal_id> --to contacts:<contact_id>

# Step 4: associate deal to company
hubspot associations create --from deals:<deal_id> --to companies:<company_id>
```

### Check Pipeline Health by Stage

```bash
# Count and list deals in a specific stage
hubspot objects search --type deals \
  --filter "dealstage=<stage_id>" \
  --properties dealname,amount,closedate,hubspot_owner_id
```

### Find Deals with No Amount Set

```bash
hubspot objects search --type deals \
  --filter "!amount" \
  --properties dealname,dealstage,hubspot_owner_id
```

### Bulk Create Deals from MQL Contacts

Use stdin piping to create multiple deals in one command. The new deal IDs come back as JSONL — save them to associate records in a second pass.

```bash
# Step 1: discover stage ID first
hubspot pipelines stages --object deals --pipeline "Sales Pipeline" --format jsonl

# Step 2: create deals from all MQL contacts
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead" \
  --properties email,firstname,lastname,company \
| jq -c '{properties: {
    dealname: (.properties.firstname + " " + .properties.lastname + " - New Business"),
    pipeline: "<pipeline_id>",
    dealstage: "<stage_id>",
    amount: "0",
    dealtype: "newbusiness"
  }}' \
| hubspot objects create --type deals \
> created_deals.jsonl

# Step 3: review created deals
cat created_deals.jsonl | jq '{id: .id, dealname: .data.properties.dealname}'
```

### Find All Open Deals (All Stages)

```bash
hubspot objects search --type deals \
  --filter "hs_is_closed!=true" \
  --properties dealname,dealstage,amount,closedate,hubspot_owner_id
```

### View All Pipelines and Stages in One Command

```bash
hubspot pipelines list --object deals --format jsonl \
| jq -r '.id' \
| xargs -I{} sh -c 'echo "=== Pipeline {} ==="; hubspot pipelines stages --object deals --pipeline {} --format table'
```

## Known Limitations
- `pipeline` and `dealstage` values are always portal-specific IDs. Never hardcode them across portals. Always call `hubspot pipelines stages` first.
- Bulk deal creation creates one API call per deal. For very large batches (> 100 deals), use the pagination loop and rate-limit caution from the `bulk-operations` skill.
- After bulk creation, the returned JSONL contains the new deal IDs. Associations must be created in a separate pass since you need the new deal IDs.
- `hs_deal_stage_probability` is read-only and set by HubSpot based on stage configuration. You cannot set it directly.
