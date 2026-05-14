---
name: team-ownership
description: Enable teams to work together with clear ownership by assigning, reassigning, and auditing record ownership across contacts, deals, and companies.
triggers:
  - "assign owner"
  - "reassign records"
  - "team visibility"
  - "ownership"
  - "rep leaving"
  - "transfer records"
  - "change owner"
  - "find records owned by rep"
---

## Resources

| File | When to use |
|---|---|
| `resources/association-graph.md` | Which object types can be associated to which, with exact CLI syntax for every valid pair in both directions |
| `resources/bulk-reassignment.sh` | Ready-to-run script for reassigning all records of a given type from one owner to another, with dry-run and confirmation prompt |

## Context
Ownership fields connect CRM records to the people responsible for them. This skill covers discovering owner IDs, finding records owned by specific reps, bulk reassigning records when reps leave or territories change, and managing the associations that give teams full visibility into account relationships.

## Property Reference

| Property | Type | Notes |
|---|---|---|
| hubspot_owner_id | string | Numeric owner ID — exists on contacts, companies, deals, and tickets |

Owner IDs are numeric strings (e.g., `"12345"`). Always resolve owner IDs with `hubspot owners list` before filtering or updating records.

## Key Workflows

### Get All Owners and Their IDs

```bash
# Table format — useful for scanning owner IDs and emails
hubspot owners list --format table

# JSONL — use when extracting a specific owner ID
hubspot owners list

# Find a specific owner's ID by email
hubspot owners list | jq -r 'select(.email == "rep@company.com") | .id'
```

### Find All Records Owned by a Specific Rep

```bash
# Contacts
hubspot objects search --type contacts \
  --filter "hubspot_owner_id=12345" \
  --properties email,firstname,lastname,lifecyclestage

# Deals
hubspot objects search --type deals \
  --filter "hubspot_owner_id=12345" \
  --properties dealname,dealstage,amount,closedate

# Companies
hubspot objects search --type companies \
  --filter "hubspot_owner_id=12345" \
  --properties name,industry

# Tickets
hubspot objects search --type tickets \
  --filter "hubspot_owner_id=12345" \
  --properties subject,hs_pipeline_stage,hs_ticket_priority
```

### Bulk Reassign All Records from One Rep to Another

Always resolve owner IDs from email addresses first — never hardcode them.

```bash
# Step 1: resolve numeric owner IDs from email addresses
FROM_ID=$(hubspot owners list | jq -r 'select(.email == "sarah@company.com") | .id')
TO_ID=$(hubspot owners list | jq -r 'select(.email == "mike@company.com") | .id')

# Step 2: reassign contacts (dry-run first)
hubspot objects search --type contacts --filter "hubspot_owner_id=$FROM_ID" \
| jq -c --arg to "$TO_ID" '{id, properties: {hubspot_owner_id: $to}}' \
| hubspot objects update --type contacts --dry-run

# Step 3: reassign contacts (execute)
hubspot objects search --type contacts --filter "hubspot_owner_id=$FROM_ID" \
| jq -c --arg to "$TO_ID" '{id, properties: {hubspot_owner_id: $to}}' \
| hubspot objects update --type contacts

# Step 4: reassign deals
hubspot objects search --type deals --filter "hubspot_owner_id=$FROM_ID" \
| jq -c --arg to "$TO_ID" '{id, properties: {hubspot_owner_id: $to}}' \
| hubspot objects update --type deals

# Step 5: reassign companies
hubspot objects search --type companies --filter "hubspot_owner_id=$FROM_ID" \
| jq -c --arg to "$TO_ID" '{id, properties: {hubspot_owner_id: $to}}' \
| hubspot objects update --type companies
```

### Find Unowned Records

```bash
# Contacts with no owner assigned
hubspot objects search --type contacts --filter "!hubspot_owner_id" \
  --properties email,firstname,lastname,lifecyclestage

# Deals with no owner
hubspot objects search --type deals --filter "!hubspot_owner_id" \
  --properties dealname,dealstage,amount
```

### Assign an Owner to a Single Record

```bash
hubspot objects update --type contacts <contact_id> \
  --property hubspot_owner_id=67890
```

### View All Records Associated with a Contact

```bash
# Associated companies
hubspot associations list --from contacts:123 --to companies

# Associated deals
hubspot associations list --from contacts:123 --to deals

# Associated tickets
hubspot associations list --from contacts:123 --to tickets
```

### Link a Contact to a Company

```bash
hubspot associations create --from contacts:123 --to companies:456
```

### Common Association Pairs

| From | To | Use Case |
|---|---|---|
| contacts | companies | Link contact to their employer |
| contacts | deals | Link contact involved in a deal |
| contacts | tickets | Link contact to their support ticket |
| deals | companies | Link deal to the company it's for |
| deals | line_items | Link deal to its line items |
| quotes | deals | Link quote to its deal |

Association type IDs are resolved automatically — you do not need to specify them.

### Bulk Create Associations from a File

```bash
# File format: one JSON object per line
# {"from":"contacts:123","to":"companies:456"}
cat associations.jsonl | hubspot associations create
```

## Known Limitations
- Owner IDs are portal-specific numeric strings. Always run `hubspot owners list` to get the correct IDs for your portal — never hardcode them.
- Bulk reassignments make one API call per record. For large rep transitions (> 100 records), use the pagination loop from the `bulk-operations` skill.
- There is no "team" object in the CLI — team-level queries are not supported. Ownership is tracked per-rep (owner ID).
- Association type IDs: some association directions support multiple types (e.g., primary vs. secondary). The CLI resolves the default type automatically.
