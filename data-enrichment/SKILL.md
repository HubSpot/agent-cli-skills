---
name: data-enrichment
description: Match external records to CRM contacts and companies by email or domain, read CRM data to enrich external sources, and write enriched data back to HubSpot.
triggers:
  - "spreadsheet to CRM"
  - "match contacts"
  - "enrich from CRM"
  - "CRM write-back"
  - "match records"
  - "update CRM from spreadsheet"
  - "look up contacts by email list"
  - "find contacts from list"
  - "spreadsheet-to-CRM matching"
  - "contact data enrichment"
  - "CRM write-back consolidation"
  - "record matching"
---

## Resources

| File | When to use |
|---|---|
| `resources/match-and-enrich.sh` | Script that reads a JSONL file of `{email,...}` records, looks up each contact in HubSpot, and outputs matched records with CRM IDs and properties merged |

## Context
Data enrichment involves two flows: (1) bringing external data into HubSpot — matching records by email or domain and updating CRM properties from an external source; (2) reading CRM data to enrich external records — fetching properties for a list of known contacts and merging them into an external dataset. Both flows use the same lookup patterns with different write targets.

## Key Workflows

### Match a Single Record by Email

```bash
hubspot objects search --type contacts \
  --filter "email=user@example.com" \
  --properties email,firstname,lastname,company,lifecyclestage,hubspot_owner_id
```

### Match Multiple Emails at Once (small batch)

Each `--filter` flag creates an OR group. Use multiple flags to look up several emails in one search call.

```bash
hubspot objects search --type contacts \
  --filter "email=alice@acme.com" \
  --filter "email=bob@acme.com" \
  --filter "email=carol@acme.com" \
  --properties email,firstname,lastname,company
```

For batches larger than ~5 emails, chunk the list and run multiple searches, then merge results:

```bash
# chunk.txt contains one email per line; process in groups of 3
while IFS= read -r -d '' chunk; do
  args=()
  while IFS= read -r email; do
    args+=(--filter "email=$email")
  done <<< "$chunk"
  hubspot objects search --type contacts "${args[@]}" --properties email,firstname,lastname,company
done < <(paste -d '\n' - - - < emails.txt | tr '\n' '\0')
```

### Match Companies by Domain

```bash
hubspot objects search --type companies \
  --filter "domain=acme.com" \
  --properties name,domain,industry,annualrevenue,hubspot_owner_id
```

### Read CRM Data to Enrich an External File

Given a file of contact IDs (`ids.txt`, one per line), fetch CRM properties and output enriched JSONL:

```bash
cat ids.txt \
| xargs -I{} hubspot objects get --type contacts {} \
    --properties email,firstname,lastname,company,lifecyclestage,hubspot_owner_id \
| jq -c '{id, email: .properties.email, firstname: .properties.firstname, lifecycle: .properties.lifecyclestage}'
```

### Write Enriched Data Back to CRM (CRM Write-Back)

Given an enriched JSONL file where each line has `{id, ...new_properties}`, update the matching CRM records:

```bash
# Transform enriched JSONL to update payload
cat enriched.jsonl \
| jq -c '{id, properties: {company: .company, jobtitle: .title, phone: .phone}}' \
| hubspot objects update --type contacts

# Dry-run first
cat enriched.jsonl \
| jq -c '{id, properties: {company: .company, jobtitle: .title, phone: .phone}}' \
| hubspot objects update --type contacts --dry-run
```

### Upsert Pattern: Create if Missing, Update if Found

```bash
email="user@example.com"

existing=$(hubspot objects search --type contacts \
  --filter "email=$email" --properties email 2>/dev/null)

if [[ -z "$existing" ]]; then
  # Create new contact
  hubspot objects create --type contacts \
    --property "email=$email" \
    --property "firstname=Jane" \
    --property "lastname=Doe"
else
  # Update existing contact
  contact_id=$(echo "$existing" | jq -r '.id')
  hubspot objects update --type contacts "$contact_id" \
    --property "firstname=Jane" \
    --property "lastname=Doe"
fi
```

### Route Matched vs Unmatched Records

When processing a list, route matched and unmatched records to separate outputs:

```bash
cat emails.jsonl | while IFS= read -r line; do
  email=$(echo "$line" | jq -r '.email')
  result=$(hubspot objects search --type contacts \
    --filter "email=$email" --properties email,firstname,lastname 2>/dev/null)
  if [[ -n "$result" ]]; then
    # Merge CRM data with external record
    echo "$result" | jq -c --argjson ext "$line" '. + {external: $ext}' >> matched.jsonl
  else
    echo "$line" >> unmatched.jsonl
  fi
done
```

## Known Limitations
- Email match is exact. `User@Acme.com` will not match `user@acme.com`. Normalize to lowercase before searching.
- `~` (CONTAINS_TOKEN) for name-based matching matches whole words only — not reliable for name variations (e.g., "Bob" won't match "Bobby"). For fuzzy matching, fetch a broad result and filter client-side.
- HubSpot's search supports a limited number of OR filter groups per call (typically up to 5). For large email lists, chunk into batches of 3-5 and run multiple searches.
- Bulk updates make one API call per record. For large write-backs (> 100 records), use the batch update pattern from the `bulk-operations` skill.
