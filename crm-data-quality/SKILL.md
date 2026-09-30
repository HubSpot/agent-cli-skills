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
hubspot properties list --type contacts --format table
hubspot properties list --type contacts | jq -c 'select(.type=="enumeration") | {name, label}'
```

Same for `--type companies`, `deals`, or any custom type (`hubspot objects types`).

## 1. Find incomplete records

`!name` = NOT_HAS_PROPERTY (missing or empty). Bare `name` = HAS_PROPERTY. Within one `--filter`, chain with `AND`; multiple `--filter` flags are OR'd.

```bash
hubspot objects search --type contacts --filter "!email" --properties firstname,lastname,company
hubspot objects search --type contacts --filter "!phone AND !mobilephone" --properties email
hubspot objects search --type contacts --filter "!hubspot_owner_id" --properties email,lifecyclestage
```

For >100 results, use the pagination loop from `bulk-operations`.

## 2. Normalize field values

Search → reshape with `jq` → pipe into `update`. `objects update` is irreversible, so `--dry-run` first — the dry-run → digest → confirm flow is required at every row count, not just >100 (`bulk-operations` covers it end to end). Reshape patterns: `bulk-operations/resources/json-patterns.md`.

```bash
# Collapse spellings into one canonical value — 1. preview
hubspot objects search --type contacts --filter "company~acme" \
| jq -c '{id, properties:{company:"Acme Corporation"}}' \
| hubspot objects update --type contacts --dry-run \
| tee /tmp/normalize.preview.jsonl

# 2. lift the digest + confirm (present at every row count)
digest=$(jq -r 'select(.digest != null) | .digest' /tmp/normalize.preview.jsonl)
confirm=$(jq -r 'select(.digest != null) | .target.id' /tmp/normalize.preview.jsonl)   # single: record ID; batch of 2+: row count

# 3. execute — re-pipe the SAME inputs plus --digest/--confirm
hubspot objects search --type contacts --filter "company~acme" \
| jq -c '{id, properties:{company:"Acme Corporation"}}' \
| hubspot objects update --type contacts --digest "$digest" --confirm "$confirm"

# Lowercase emails (read, reshape, write) — 1. preview
hubspot objects search --type contacts --filter "email" --properties email \
| jq -c '{id, properties:{email: (.properties.email | ascii_downcase)}}' \
| hubspot objects update --type contacts --dry-run \
| tee /tmp/lower.preview.jsonl

# 2. lift the digest + confirm, then 3. re-pipe the SAME inputs to execute
digest=$(jq -r 'select(.digest != null) | .digest' /tmp/lower.preview.jsonl)
confirm=$(jq -r 'select(.digest != null) | .target.id' /tmp/lower.preview.jsonl)
hubspot objects search --type contacts --filter "email" --properties email \
| jq -c '{id, properties:{email: (.properties.email | ascii_downcase)}}' \
| hubspot objects update --type contacts --digest "$digest" --confirm "$confirm"
```

## 3. Dedupe with `hubspot objects merge`

Secondary is folded into primary and deleted. **Irreversible.** Dry-run/digest/confirm gating applies.

```bash
# Single pair — dry-run first, then execute with the digest + confirm (confirm = the secondary ID for one pair)
hubspot objects merge --type contacts --primary 149 --secondary 425 --dry-run
hubspot objects merge --type contacts --primary 149 --secondary 425 --digest <hash> --confirm 425
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

Lift the digest/confirm from the preview line at any size — `select(.digest != null)`; for a batch the confirm is the pair count (`.target.id`), and `mutation_kind` is `BulkData` only above the 100-row threshold (`RecordMutation` at or below it, but the digest is present either way). Re-pipe the same producer with `--digest`/`--confirm` (see `bulk-operations`).

## 4. Audit properties

`hubspot properties list` (and `get`, `batch-read`) emits `{name, label, type, fieldType, groupName, optionsDisplay}` per row. Enum option values are exposed via `properties options-list` — no need to read them off a live record or the UI.

```bash
# Count properties per group (HubSpot groups standard fields; custom groups stand out)
hubspot properties list --type contacts | jq -rs 'group_by(.groupName) | map({group: .[0].groupName, count: length}) | .[]'

# All enumeration properties
hubspot properties list --type contacts | jq -c 'select(.type=="enumeration") | {name, label, fieldType}'

# Create a DQ flag property, then set it via the normalize pattern in section 2
hubspot properties create --type contacts --name dq_missing_phone --label "DQ: Missing Phone" --prop-type string --field-type text
```

### Enum options — list and manage (`properties options-*`, v0.11.0)

```bash
# List the allowed options on an enumeration property
hubspot properties options-list --type contacts hs_buying_role
# each row: {"value":"EVALUATOR","label":"Evaluator","displayOrder":9,"hidden":false}

# Add / rename / remove an option (options-delete is irreversible — dry-run → digest → confirm, confirm = the option value)
hubspot properties options-create --type contacts hs_buying_role --label "Evaluator" --value EVALUATOR --display-order 9
hubspot properties options-update --type contacts hs_buying_role --value EVALUATOR --label "New Label"
hubspot properties options-delete --type contacts hs_buying_role --value EVALUATOR --dry-run
hubspot properties options-delete --type contacts hs_buying_role --value EVALUATOR --digest <hash> --confirm EVALUATOR
```

HubSpot-defined properties with read-only options reject `options-create`/`update`/`delete` before the API is called.

## Recovery

Merge is irreversible. After any merge, `hubspot history --since 1h` captures the audit trail. If wrong direction, restore the secondary from the UI's recycle bin.
