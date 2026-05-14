# JSON Transformation Patterns for CRM Bulk Operations

All examples assume JSONL input (one JSON object per line) from `hubspot objects list`, `search`, or `get`.
Properties are nested under the `properties` key.

The `jq` examples below show the transformation logic concisely. Use these as a reference for the input/output shapes when constructing payloads.

---

## Export as CSV or TSV

```bash
# CSV (quoted, Excel-compatible)
hubspot objects list --type contacts \
| jq -r '[.properties.email, .properties.firstname, .properties.lastname] | @csv'

# TSV (tab-separated, spreadsheet-friendly)
hubspot objects list --type contacts \
| jq -r '[.properties.email, .properties.firstname, .properties.lastname] | @tsv'
```

---

## De-duplicate and merge two search results (preserving full objects)

```bash
# Merge two searches into a unique record set (keeps the full object, not just IDs)
(hubspot objects search --type contacts --filter "lifecyclestage=lead"
 hubspot objects search --type contacts --filter "lifecyclestage=marketingqualifiedlead") \
| jq -s 'unique_by(.id)[]' -c
```

---

## Numeric comparisons (client-side)

HubSpot's search operators handle most numeric comparisons server-side, but client-side filtering
is useful when you need compound logic the server can't express.

```bash
# Contacts at companies with revenue > 1,000,000 (filter after fetching companies)
hubspot objects list --type companies \
| jq -c 'select((.properties.annualrevenue // "0") | tonumber > 1000000)'

# Deals with amount between 10k and 100k
hubspot objects list --type deals \
| jq -c 'select((.properties.amount // "0") | tonumber >= 10000 and tonumber <= 100000)'
```

---

## String pattern matching (client-side)

```bash
# Case-insensitive contains (use server-side --filter "field~token" when possible)
hubspot objects list --type contacts \
| jq -c 'select(.properties.company | test("acme"; "i"))'

# Exclude records matching a pattern
hubspot objects list --type contacts \
| jq -c 'select(.properties.email | test("test|noreply|placeholder"; "i") | not)'
```

---

## Convert search results to association create JSONL

`associations create` reads stdin in the shape `{"from": "contacts:123", "to": "companies:456"}`.

```bash
# Link every contact matching a search to a single company
hubspot objects search --type contacts --filter "company~acme" \
| jq -c '{from: ("contacts:" + .id), to: "companies:456"}'

# Cross-reference two JSONL files and associate each matched pair
jq -s '
  .[0] as $contacts | .[1] as $companies |
  $contacts[] | . as $c |
  $companies[] | select(.properties.domain == $c.properties.company_domain) |
  {from: ("contacts:" + $c.id), to: ("companies:" + .id)}
' contacts.jsonl companies.jsonl -c
```

---

## Count results

```bash
# Count lines in JSONL stream
hubspot objects search --type contacts --filter "lifecyclestage=lead" \
| wc -l

# Count by field value (frequency table)
hubspot objects list --type contacts \
| jq -r '.properties.lifecyclestage' \
| sort | uniq -c | sort -rn
```

---

## Save IDs and reuse them

```bash
# Save IDs to a file for later use
hubspot objects search --type contacts --filter "hubspot_owner_id=12345" \
| jq -r '.id' > owner_contact_ids.txt

# Fetch full records from a saved ID list
cat owner_contact_ids.txt \
| xargs -I{} hubspot objects get --type contacts {}

# Build delete-compatible JSONL from a search
hubspot objects search --type contacts --filter "lifecyclestage=subscriber" \
| jq -c '{id}'
```
