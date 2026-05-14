---
name: crm-lookup
description: Find and retrieve specific CRM records — deals by name, contacts by email, companies by domain — and traverse associations to get the full account picture.
triggers:
  - "look up deal"
  - "find contact"
  - "search company"
  - "find contact by email"
  - "company lookup"
  - "deal lookup"
  - "get contact by email"
  - "find company by domain"
  - "get deal by name"
  - "contacts at this company"
  - "deals for this contact"
  - "find record"
  - "contact lookup"
  - "general deal lookup"
  - "general company search"
  - "general contact search"
  - "contact info lookup"
---

## Resources

| File | When to use |
|---|---|
| `resources/default-property-sets.md` | Recommended `--properties` lists for contacts, companies, deals, and tickets — what to request for a useful snapshot without fetching all fields |

## Context
The most common agent task is finding a specific record before doing anything else. This skill covers looking up records when you have an ID, searching when you have partial info (email, domain, name fragment), and traversing associations to get the full account picture. The `~` operator matches whole words/tokens — for substring matching, fetch all results and filter client-side.

## Property Reference

| Object | Key lookup properties |
|---|---|
| contacts | `email`, `firstname`, `lastname`, `company`, `phone`, `lifecyclestage`, `hs_lead_status`, `hubspot_owner_id` |
| companies | `name`, `domain`, `industry`, `annualrevenue`, `numberofemployees`, `hubspot_owner_id` |
| deals | `dealname`, `amount`, `dealstage`, `closedate`, `hubspot_owner_id`, `hs_is_closed_won` |
| tickets | `subject`, `hs_pipeline_stage`, `hs_ticket_priority`, `hubspot_owner_id` |

## Key Workflows

### Lookup by ID (when you have it)

```bash
# Contact
hubspot objects get --type contacts 12345 \
  --properties email,firstname,lastname,company,phone,lifecyclestage,hubspot_owner_id

# Company
hubspot objects get --type companies 67890 \
  --properties name,domain,industry,annualrevenue,numberofemployees,hubspot_owner_id

# Deal
hubspot objects get --type deals 11111 \
  --properties dealname,amount,dealstage,closedate,hubspot_owner_id

# Ticket
hubspot objects get --type tickets 22222 \
  --properties subject,hs_pipeline_stage,hs_ticket_priority,hubspot_owner_id
```

### Find Contact by Email (exact match)

```bash
hubspot objects search --type contacts \
  --filter "email=user@example.com" \
  --properties email,firstname,lastname,company,lifecyclestage,hubspot_owner_id
```

### Find Company by Domain

```bash
hubspot objects search --type companies \
  --filter "domain=acme.com" \
  --properties name,domain,industry,annualrevenue,hubspot_owner_id
```

### Find Deal by Name (partial match)

`~` (CONTAINS_TOKEN) matches whole words. Use it to find deals containing a keyword, then verify client-side.

```bash
# Find deals whose name contains "acme" as a whole word
hubspot objects search --type deals \
  --filter "dealname~acme" \
  --properties dealname,amount,dealstage,closedate,hubspot_owner_id

# Narrow further client-side when the token match is too broad
hubspot objects search --type deals \
  --filter "dealname~acme" \
  --properties dealname,amount,dealstage,closedate \
| jq -c 'select(.properties.dealname | ascii_downcase | contains("acme corp"))'
```

### Find All Contacts at a Company

```bash
# Step 1: get the company record to confirm the company ID
hubspot objects search --type companies --filter "domain=acme.com" --properties name

# Step 2: list contacts associated to that company
hubspot associations list --from companies:67890 --to contacts --format jsonl \
| jq -r '.id' \
| xargs -I{} hubspot objects get --type contacts {} \
    --properties email,firstname,lastname,jobtitle,hubspot_owner_id
```

### Find All Open Deals for a Contact

```bash
hubspot associations list --from contacts:12345 --to deals --format jsonl \
| jq -r '.id' \
| xargs -I{} hubspot objects get --type deals {} \
    --properties dealname,amount,dealstage,closedate,hubspot_owner_id \
| jq -c 'select(.properties.hs_is_closed != "true")'
```

### Find Contacts by Multiple Emails (OR)

Each `--filter` flag is an OR group. Use multiple flags to match several emails at once.

```bash
hubspot objects search --type contacts \
  --filter "email=alice@acme.com" \
  --filter "email=bob@acme.com" \
  --filter "email=carol@acme.com" \
  --properties email,firstname,lastname,company
```

### Get a Contact's Company and Open Deals Together

```bash
contact_id=12345

# Contact properties
hubspot objects get --type contacts $contact_id \
  --properties email,firstname,lastname,company,lifecyclestage,hubspot_owner_id

# Associated company
hubspot associations list --from contacts:$contact_id --to companies --format jsonl \
| jq -r '.id' \
| head -1 \
| xargs -I{} hubspot objects get --type companies {} \
    --properties name,domain,industry,annualrevenue

# Open deals
hubspot associations list --from contacts:$contact_id --to deals --format jsonl \
| jq -r '.id' \
| xargs -I{} hubspot objects get --type deals {} \
    --properties dealname,amount,dealstage,closedate
```

## Known Limitations
- `~` (CONTAINS_TOKEN) matches whole words only. `dealname~acme` will not match "AcmeCorp" (no space). For substring matching, fetch all results and filter client-side (e.g. check whether `dealname` contains the substring after lowercasing).
- No full-text search across all fields. Search targets a specific property.
- For > 100 results, use the pagination loop from the `bulk-operations` skill.
- Exact email match is case-sensitive in HubSpot's search API. Use lowercase.
