---
name: crm-data-quality
description: Find incomplete records, normalize field values in bulk, dedupe with `hubspot objects merge`, and audit custom properties. Builds on `bulk-operations` for JSONL piping and dry-run/digest/confirm.
triggers:
  - "clean up contacts"
  - "data quality"
  - "deduplicate"
  - "missing fields"
  - "normalize data"
  - "find incomplete records"
  - "merge duplicates"
  - "audit properties"
---

Read `bulk-operations/SKILL.md` first — JSONL piping, batch read, pagination, and dry-run/digest/confirm gating apply to every command below.

## Property discovery

Don't guess property names. List them:

```bash
hubspot properties list --object contacts --format table
hubspot properties list --object contacts | jq -c 'select(.type=="enumeration") | {name, label}'
```

Same for `--object companies`, `deals`, or any custom type (`hubspot objects types`).

## 1. Find incomplete records

`!name` = NOT_HAS_PROPERTY (missing or empty). Bare `name` = HAS_PROPERTY. Within one `--filter`, chain with `AND`; multiple `--filter` flags are OR'd.

```bash
hubspot objects search --type contacts --filter "!email" --properties firstname,lastname,company
hubspot objects search --type contacts --filter "!phone AND !mobilephone" --properties email
hubspot objects search --type contacts --filter "!hubspot_owner_id" --properties email,lifecyclestage
```

For >100 results, use the pagination loop from `bulk-operations`.

## 2. Normalize field values

Search → reshape with `jq` → pipe into `update`. Always `--dry-run` first; `bulk-operations` covers digest/confirm escalation for >100 rows. Reshape patterns: `bulk-operations/resources/json-patterns.md`.

```bash
# Collapse spellings into one canonical value
hubspot objects search --type contacts --filter "company~acme" \
| jq -c '{id, properties:{company:"Acme Corporation"}}' \
| hubspot objects update --type contacts --dry-run

# Lowercase emails (read, reshape, write)
hubspot objects search --type contacts --filter "email" --properties email \
| jq -c '{id, properties:{email: (.properties.email | ascii_downcase)}}' \
| hubspot objects update --type contacts --dry-run
```

## 3. Dedupe with `hubspot objects merge`

Secondary is folded into primary and deleted. **Irreversible.** Dry-run/digest/confirm gating applies.

```bash
# Single pair
hubspot objects merge --type contacts --primary 149 --secondary 425 --dry-run
hubspot objects merge --type contacts --primary 149 --secondary 425   # execute (≤100 pairs)
```

Bulk: pipe JSONL `{"primary":"...","secondary":"..."}` on stdin (omit `--primary`/`--secondary`).

**Pagination required.** `objects search` caps at 100 rows per call and `jq -s` slurps a single stream into memory — running the snippet below against a raw `search` will silently miss every duplicate that crosses a page boundary. Collect the full set first with the pagination loop from `bulk-operations/SKILL.md` (write to `/tmp/contacts.jsonl`), then dedupe from the file:

```bash
# /tmp/contacts.jsonl produced by the pagination loop (bulk-operations/SKILL.md)
jq -s -c '
    group_by(.properties.email)[]
    | select(length > 1)
    | sort_by(.id | tonumber)
    | .[0].id as $p | .[1:][] | {primary: $p, secondary: .id}
  ' /tmp/contacts.jsonl \
| hubspot objects merge --type contacts --dry-run | tee /tmp/merge-preview.jsonl
```

For >100 pairs, lift `digest` and `impact.records_affected` from the `BulkData` line and re-pipe the same producer with `--digest`/`--confirm` (see `bulk-operations`).

## 4. Audit properties

`hubspot properties list` (and `get`, `batch-read`) emits `{name, label, type, fieldType, groupName}` per row. Enum option values are not currently exposed by the CLI — read them off a real record (`hubspot objects search ... --properties <enum>`) or the HubSpot UI.

```bash
# Count properties per group (HubSpot groups standard fields; custom groups stand out)
hubspot properties list --object contacts | jq -rs 'group_by(.groupName) | map({group: .[0].groupName, count: length}) | .[]'

# All enumeration properties
hubspot properties list --object contacts | jq -c 'select(.type=="enumeration") | {name, label, fieldType}'

# Create a DQ flag property, then set it via the normalize pattern in section 2
hubspot properties create --object contacts --name dq_missing_phone --label "DQ: Missing Phone" --type string --field-type text
```

## Recovery

Merge is irreversible. After any merge, `hubspot history --since 1h` captures the audit trail. If wrong direction, restore the secondary from the UI's recycle bin.
