---
name: data-enrichment
description: Match external CSV/JSONL records to CRM contacts (by email) or companies (by domain) and write enriched data back in one pass using `hubspot objects upsert`.
triggers:
  - "spreadsheet to CRM"
  - "match contacts by email"
  - "match companies by domain"
  - "enrich CRM from CSV"
  - "CRM write-back"
  - "create or update by email"
---

Prereq: read `bulk-operations/SKILL.md` first — JSONL piping, dry-run/digest, history, and rate-limit hygiene live there. This skill is the upsert-by-natural-key workflow on top.

## The core move: upsert, not search-then-create

`hubspot objects upsert --type X --id-property <natural-key>` reads JSONL on stdin and creates-or-updates each row in **one CLI call per record**, keyed by a property (email for contacts, domain for companies). No race window, no branching. Do not loop `search` → empty? → `create`.

Per line in: `{"id":"jane@example.com","properties":{"firstname":"Jane","jobtitle":"VP"}}`
Per line out: `{"id":"123","ok":true,"data":{...,"new":true|false}}` or `{"ok":false,"error":{...}}`. Order matches input.

## CSV/JSONL → upsert stream

Reshape with `jq`, preview with `--dry-run`, then execute. Always lowercase the natural key — CRM match is exact. Confirm available property names with `hubspot properties list --type contacts`; never hard-code a list. See `bulk-operations/resources/json-patterns.md` for reshape idioms.

```bash
# CSV → JSONL (any tool); example using csvkit
csvjson external.csv | jq -c '.[]' > external.jsonl

# Preview
cat external.jsonl \
| jq -c '{id:(.email|ascii_downcase), properties:{firstname:.first, lastname:.last, jobtitle:.title, company:.company}}' \
| hubspot objects upsert --type contacts --id-property email --dry-run | head

# Execute (same pipeline, drop --dry-run, capture results)
cat external.jsonl \
| jq -c '{id:(.email|ascii_downcase), properties:{firstname:.first, lastname:.last, jobtitle:.title, company:.company}}' \
| hubspot objects upsert --type contacts --id-property email \
| tee /tmp/upsert.results.jsonl
```

Companies: swap `--type companies --id-property domain` and reshape with `.domain|ascii_downcase` as `id`.

## Handle per-record OK / error output

Split with `jq`, inspect failure modes, retry just the failures after fixing the inputs:

```bash
jq -c 'select(.ok==true)'  /tmp/upsert.results.jsonl > /tmp/upsert.ok.jsonl
jq -c 'select(.ok==false)' /tmp/upsert.results.jsonl > /tmp/upsert.failed.jsonl
jq -r '.error.status' /tmp/upsert.failed.jsonl | sort | uniq -c   # status → count
jq -r '.data.new'    /tmp/upsert.ok.jsonl     | sort | uniq -c   # created vs updated
```

429s: split the input and rerun smaller chunks (see `bulk-operations` rate-limit notes). 400s usually mean a bad property name or invalid enum value — fix the reshape, rerun the failed inputs.

## Destructive-op safety

`upsert` itself is non-destructive, but write-back can clobber populated fields. Always `--dry-run` first and spot-check. For bulk delete or overwrite of existing data, follow the dry-run → digest → confirm flow in `bulk-operations/SKILL.md`. Recovery: `hubspot history --since 1h`.

## Match without upsert: OR-search → update

When you only want to read matches (no write-back), or the natural key isn't a CRM property, use repeated `--filter` flags — each flag is one OR group.

Verified cap: **5 OR groups per call**. 6+ returns `400 too many filterGroups (count: N, max allowed: 5)`. Chunk 5 at a time:

```bash
# emails.txt: one lowercased email per line
xargs -n5 < emails.txt | while read -r e1 e2 e3 e4 e5; do
  args=()
  for e in "$e1" "$e2" "$e3" "$e4" "$e5"; do [ -n "$e" ] && args+=(--filter "email=$e"); done
  hubspot objects search --type contacts "${args[@]}" --properties email,firstname,company
done > /tmp/matches.jsonl

jq -c '{id, properties:{lifecyclestage:"marketingqualifiedlead"}}' /tmp/matches.jsonl \
| hubspot objects update --type contacts --dry-run
```

For larger keyed enrichments, prefer `upsert` — one pipeline, no chunking math.
