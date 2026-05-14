---
name: crm-data-quality
description: Maintain a single, trusted source of customer data by finding incomplete records, normalizing field values, and auditing custom properties across contacts.
triggers:
  - "clean up contacts"
  - "data quality"
  - "deduplicate"
  - "missing fields"
  - "normalize data"
  - "find incomplete records"
  - "audit contact data"
  - "contacts missing properties"
---

## Resources

| File | When to use |
|---|---|
| `resources/standard-contact-properties.md` | Full reference of standard contact property names, types, and enum values — check here before constructing filters or updates on contacts |
| `resources/standard-company-properties.md` | Same for companies, including the complete `industry` enumeration |

## Context
Reliable CRM data is the foundation for accurate reporting, effective segmentation, and automation. This skill covers finding contacts with missing or inconsistent field values, normalizing data in bulk, and creating custom flag properties — all without leaving the terminal.

## Property Reference

| Property | Type | Notes |
|---|---|---|
| email | string | Primary identifier |
| firstname | string | |
| lastname | string | |
| phone | string | |
| mobilephone | string | |
| company | string | Company name text (not the associated Company object) |
| jobtitle | string | |
| lifecyclestage | enumeration | subscriber, lead, marketingqualifiedlead, salesqualifiedlead, opportunity, customer, evangelist, other |
| hs_lead_status | enumeration | NEW, OPEN, IN_PROGRESS, OPEN_DEAL, UNQUALIFIED, ATTEMPTED_TO_CONTACT, CONNECTED, BAD_TIMING |
| hubspot_owner_id | string | Numeric owner ID (get from `hubspot owners list`) |
| createdate | datetime | Read-only |
| lastmodifieddate | datetime | Read-only |
| hs_email_last_send_date | datetime | Read-only |

## Key Workflows

### Find Contacts Missing a Required Field

```bash
# Missing phone
hubspot objects search --type contacts --filter "!phone" \
  --properties email,firstname,lastname

# Missing email
hubspot objects search --type contacts --filter "!email" \
  --properties firstname,lastname,company

# Missing both first and last name (run separately, de-duplicate)
hubspot objects search --type contacts --filter "!firstname"
hubspot objects search --type contacts --filter "!lastname"
```

### Find Contacts by Lifecycle Stage

```bash
# Find all leads
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead" \
  --properties email,lifecyclestage,hs_lead_status

# Find contacts in a specific lead status
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead AND hs_lead_status=NEW" \
  --properties email,firstname,lastname
```

### Bulk Normalize a Field Value

```bash
# Dry-run first
hubspot objects search --type contacts --filter "company=Acme Corp" \
| jq -c '{id, properties: {company: "Acme Corporation"}}' \
| hubspot objects update --type contacts --dry-run

# Execute
hubspot objects search --type contacts --filter "company=Acme Corp" \
| jq -c '{id, properties: {company: "Acme Corporation"}}' \
| hubspot objects update --type contacts
```

### Audit All Contact Properties

```bash
# Table format — useful for scanning property names and types
hubspot properties list --object contacts --format table

# JSONL — use when searching for a specific property by name or type
hubspot properties list --object contacts
```

### Create a Custom Data Quality Flag Property

```bash
hubspot properties create \
  --object contacts \
  --name data_quality_flag \
  --label "Data Quality Flag" \
  --type string \
  --field-type text
```

### Flag Contacts Missing Critical Fields

```bash
# Create the flag property (once)
hubspot properties create \
  --object contacts \
  --name missing_phone_flag \
  --label "Missing Phone Flag" \
  --type string \
  --field-type text

# Flag all contacts missing phone
hubspot objects search --type contacts --filter "!phone" \
| jq -c '{id, properties: {missing_phone_flag: "true"}}' \
| hubspot objects update --type contacts
```

### Find Contacts with a Specific Field Value (Exact Match)

```bash
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer" \
  --properties email,firstname,lastname,hubspot_owner_id
```

### Find Contacts Matching a Partial Text Pattern

Use `~` (CONTAINS_TOKEN) for partial string matches:

```bash
# Contacts with "acme" anywhere in their company field
hubspot objects search --type contacts \
  --filter "company~acme" \
  --properties email,company
```

### Check If a Specific Contact's Data Is Complete

```bash
hubspot objects get --type contacts <id> \
  --properties email,firstname,lastname,phone,company,lifecyclestage,hubspot_owner_id
```

## Known Limitations
- No contact merge from the CLI. Use the HubSpot UI (Contacts → Actions → Merge) to deduplicate records.
- `HAS_PROPERTY` across OR groups cannot be done in a single call. Run two separate searches and de-duplicate IDs client-side (collect both result sets and deduplicate on `id`).
- For > 100 records, pagination is required. Use the pagination loop from the `bulk-operations` skill.
- The `~` (CONTAINS_TOKEN) operator matches whole tokens (words), not arbitrary substrings. For full-text matching, use HubSpot UI search.
