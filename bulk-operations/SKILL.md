---
name: bulk-operations
description: Foundational skill for bulk CRM operations using the JSONL pipe pattern — read from any list or search and pipe directly into create, update, or delete commands.
triggers:
  - "bulk update contacts"
  - "pipe records"
  - "process in bulk"
  - "batch import"
  - "JSONL"
  - "bulk operations"
  - "pipe output to update"
---

## Resources

| File | When to use |
|---|---|
| `resources/pagination-loop.sh` | Pagination loop for fetching more than 100 records using the `--after` cursor — adapt for any object type |
| `resources/json-patterns.md` | Transformation patterns for extracting fields, building create/update payloads, de-duplicating results, and building association JSONL |

## Context
The `hubspot` CLI outputs JSONL (one JSON object per line) by default, making every read command pipeable into every write command. This skill covers the foundational patterns for bulk data operations: pagination, JSON transformation, rate limit management, and safe bulk mutation workflows.

## How to Process JSONL

The CLI outputs JSONL — one JSON object per line. Every read command can pipe directly into every write command; the transformation step reshapes each record into the mutation input shape.

**Two-file pattern** — read output to a file, construct the payload file, then run the mutation:
```bash
hubspot objects search --type contacts --filter "lifecyclestage=lead" > /tmp/leads.jsonl
# Construct /tmp/updates.jsonl: each line is {"id":"...","properties":{"lifecyclestage":"marketingqualifiedlead"}}
hubspot objects update --type contacts < /tmp/updates.jsonl
```

**Pipe pattern** — transform each JSONL line inline and pipe directly to the write command:
```bash
hubspot objects search --type contacts --filter "lifecyclestage=lead" \
| <transform each line to {"id":"...","properties":{"lifecyclestage":"marketingqualifiedlead"}}> \
| hubspot objects update --type contacts
```

## Key Concepts

**Output shape (default JSONL):**
Each record from `list`, `search`, or `get` is one line:
```json
{"id":"123","properties":{"email":"user@example.com","firstname":"Jane"}}
```
Properties are nested under the `properties` key.

**Mutation input shape (stdin JSONL):**
- `update`: `{"id":"123","properties":{"field":"value"}}`
- `delete`: `{"id":"123"}`
- `create`: `{"properties":{"field":"value"}}`
- `associations create`: `{"from":"contacts:123","to":"companies:456"}`

## Key Workflows

### Safe Bulk Mutation Pattern

Always `--dry-run` first. Dry-run output has the same shape but includes `"dry_run":true,"executed":false`.

```bash
# Step 1: preview what will change
hubspot objects search --type contacts --filter "lifecyclestage=lead" \
| jq -c '{id, properties: {lifecyclestage: "marketingqualifiedlead"}}' \
| hubspot objects update --type contacts --dry-run

# Step 2: test on a small subset
hubspot objects search --type contacts --filter "lifecyclestage=lead" \
| head -n 10 \
| jq -c '{id, properties: {lifecyclestage: "marketingqualifiedlead"}}' \
| hubspot objects update --type contacts --dry-run

# Step 3: run for real
hubspot objects search --type contacts --filter "lifecyclestage=lead" \
| jq -c '{id, properties: {lifecyclestage: "marketingqualifiedlead"}}' \
| hubspot objects update --type contacts
```

### Pagination Loop (> 100 Records)

The CLI does not auto-paginate. Use `--format json` to get the `meta.next` cursor for the next page:

```bash
after=""
while true; do
  if [ -z "$after" ]; then
    result=$(hubspot objects list --type contacts --limit 100 --format json)
  else
    result=$(hubspot objects list --type contacts --limit 100 --after "$after" --format json)
  fi

  # Extract records: .data[] contains the JSONL records
  echo "$result" | jq -c '.data[]' >> all_contacts.jsonl

  # Get next cursor: .meta.next is empty string when no more pages
  next=$(echo "$result" | jq -r '.meta.next // empty')
  if [ -z "$next" ]; then
    break
  fi
  after="$next"
done
```

Run the first page, read `meta.next` from the JSON output, then run subsequent pages with `--after <cursor>` until `meta.next` is absent or empty.

The same pattern works for `search` with `--format json`.

### JSON Transformation Patterns

The transformation step between a read command and a write command reshapes each JSONL record. The `jq` examples below show the transformation logic — agents apply the same logic natively.

```bash
# Extract a single field from each record
hubspot objects list --type contacts | jq -r '.properties.email'

# Transform read output into update payload
hubspot objects search --type contacts --filter "company=Acme Corp" \
| jq -c '{id, properties: {company: "Acme Corporation"}}'

# Filter records before piping to mutation
hubspot objects list --type contacts \
| jq -c 'select(.properties.email != null and .properties.email != "")' \
| jq -c '{id, properties: {email: .properties.email}}'

# Build create payloads from an external JSONL file
cat import.jsonl \
| jq -c '{properties: {email: .email, firstname: .first_name, lastname: .last_name}}'

# De-duplicate IDs from two search results
(hubspot objects search --type contacts --filter "lifecyclestage=lead"; \
 hubspot objects search --type contacts --filter "lifecyclestage=marketingqualifiedlead") \
| jq -s 'map(.id) | unique[]'
```

### Find Contacts Missing a Field and Update

```bash
hubspot objects search --type contacts --filter "!email" \
| jq -c '{id, properties: {email: "missing@placeholder.com"}}' \
| hubspot objects update --type contacts
```

### Bulk Delete Pattern

Requires `export HUBSPOT_ACCESS_TOKEN=<token>` (User OAuth cannot delete).

```bash
# Dry-run first
hubspot objects search --type contacts --filter "lifecyclestage=subscriber" \
| jq -c '{id}' \
| hubspot objects delete --type contacts --dry-run

# Execute
hubspot objects search --type contacts --filter "lifecyclestage=subscriber" \
| jq -c '{id}' \
| hubspot objects delete --type contacts
```

### Bulk Association Pattern

```bash
# Associate all deals owned by rep 12345 to company 456
hubspot objects search --type deals --filter "hubspot_owner_id=12345" \
| jq -c '{from: ("deals:" + .id), to: "companies:456"}' \
| hubspot associations create
```

### Save Results for Later Processing

```bash
# Save search results to file
hubspot objects search --type contacts --filter "lifecyclestage=lead" \
  --properties email,firstname,lastname > leads.jsonl

# Process a saved file
cat leads.jsonl \
| jq -c '{id, properties: {lifecyclestage: "marketingqualifiedlead"}}' \
| hubspot objects update --type contacts
```

## Known Limitations
- No auto-pagination: the CLI returns at most 100 records per call. Use the pagination loop above for larger datasets.
- No true batch API: bulk mutations make one API call per record. Use `head -n 50` to test at small scale before running full operations to avoid hitting rate limits.
- Deletes require a private app token (`HUBSPOT_ACCESS_TOKEN`). User OAuth login cannot perform deletes.
- No Lists API: cannot create or manage HubSpot contact/company lists from the CLI. Use HubSpot UI for list creation.
- No sequences/cadences API, no contact merge, no Conversations/Inbox API, no marketing emails API.
