---
name: bulk-operations
description: Foundation patterns for the `hubspot` CLI — JSONL piping, batch read, pagination, dry-run/digest/confirm for destructive ops, and `hubspot history` for recovery. Every other skill builds on this one.
triggers:
  - "bulk update"
  - "bulk create"
  - "bulk delete"
  - "process in bulk"
  - "JSONL pipe"
  - "pagination"
  - "dry-run"
  - "history"
  - "undo"
---

## Resources

| File | When to use |
|---|---|
| `resources/json-patterns.md` | Reshape patterns for turning a read into an update payload, a search into a delete list, a CSV into an upsert stream. |

## Source of truth

`hubspot <command> --help` is authoritative. If anything in this file contradicts `--help`, trust `--help` and tell the user. Run `hubspot objects types` once at the start of a session to see what object types exist in this portal (standard + custom).

## Output shape

Every read command (`list`, `search`, `get`) emits JSONL — one JSON object per line:

```json
{"id":"123","properties":{"email":"jane@example.com","firstname":"Jane"},"createdAt":"...","updatedAt":"...","archived":false,"url":"..."}
```

`--properties email,firstname` limits which fields the server returns under `.properties` — it does **not** flatten the shape (despite what `hubspot objects get --help` currently claims; that's CLI improvement #11). Downstream `jq` should use `.properties.email`, not `.prop_email`.

Write commands (`create`, `update`, `upsert`, `delete`, `merge`, `associations create`) accept JSONL on stdin and emit JSONL — one result per input line: `{"id":"123","ok":true,"data":{...}}` or `{"id":"123","ok":false,"error":{"status":...,"message":"..."}}`. Order of results matches input order.

## Read in batch — never one-by-one

The CLI accepts multiple IDs natively. **Never** pipe IDs into `xargs -I{} hubspot objects get ...` — that spawns one CLI process per record.

```bash
# Positional args (small, known list)
hubspot objects get --type contacts 12345 67890 23456 --properties email,firstname

# Stdin from another command — one CLI call total
hubspot associations list --from companies:67890 --to contacts \
| jq -c '{id}' \
| hubspot objects get --type contacts --properties email,firstname,jobtitle

# Bare IDs on stdin also work
printf '12345\n67890\n23456\n' | hubspot objects get --type contacts --properties email
```

A single `hubspot objects get` reads up to ~100 IDs per call via the batch endpoint. For more, page in chunks of 100.

## Pagination

`list` and `search` return at most 100 records per call. Use `--format json` to get the cursor under `meta.next`, then re-run with `--after <cursor>` until the cursor is empty.

```bash
after=""
while :; do
  if [ -z "$after" ]; then
    page=$(hubspot objects search --type contacts --filter "lifecyclestage=lead" --limit 100 --format json)
  else
    page=$(hubspot objects search --type contacts --filter "lifecyclestage=lead" --limit 100 --after "$after" --format json)
  fi
  echo "$page" | jq -c '.data[]' >> /tmp/leads.jsonl
  after=$(echo "$page" | jq -r '.meta.next // empty')
  [ -z "$after" ] && break
done
```

Same loop works for `list`. See `CLI_IMPROVEMENTS.md` #2 — auto-pagination is on the ask list.

## Write in batch — always pipe

Write commands accept JSONL on stdin. The transformation between a read shape and a write shape is a `jq` reshape:

| Write command | Required per-line shape |
|---|---|
| `objects create` | `{"properties":{"field":"value"}}` |
| `objects update` | `{"id":"123","properties":{"field":"value"}}` |
| `objects upsert` | `{"idProperty":"email","id":"jane@example.com","properties":{...}}` (or use `--id-property email` once) |
| `objects delete` | `{"id":"123"}` |
| `objects merge` | `{"primary":"123","secondary":"456"}` |
| `associations create` | `{"from":"contacts:123","to":"companies:456"}` |

Use **plural** object names in `from`/`to` (`contacts:`, not `contact:`).

## Safe destructive workflow

Every destructive op (`delete`, `merge`, bulk `update`) supports `--dry-run`. The gating depends on row count:

**≤100 rows** — dry-run emits one preview line per record:
```json
{"ok":true,"dry_run":true,"executed":false,"mutation_kind":"RecordMutation","command":"objects delete contacts","target":{"kind":"contacts_record","id":"123","name":"123"}}
```
Re-run without `--dry-run` to execute.

**>100 rows** — dry-run emits a single `BulkData` line with a digest and an `apply_command_hint`:
```json
{"ok":true,"dry_run":true,"executed":false,"mutation_kind":"BulkData","portal":"150890","target":{"name":"202 records"},"impact":{"records_affected":202,"reversible":false},"digest":"blast-29cfdd48b583","expires_in_seconds":300,"apply_command_hint":"hubspot objects delete contacts --digest blast-29cfdd48b583 --confirm '202'"}
```
You must re-run with `--digest <hash> --confirm <value>` within 5 minutes. The `confirm` value is the record count (deletes) or the secondary ID (merge). Read it off `apply_command_hint`.

Three-step pattern:

```bash
# 1. Preview
hubspot objects search --type contacts --filter "lifecyclestage=subscriber" \
| jq -c '{id}' \
| hubspot objects delete --type contacts --dry-run \
| tee /tmp/preview.jsonl

# 2. Lift the digest + confirm value (only present for >100 rows)
digest=$(jq -r 'select(.mutation_kind=="BulkData") | .digest' /tmp/preview.jsonl)
confirm=$(jq -r 'select(.mutation_kind=="BulkData") | .impact.records_affected' /tmp/preview.jsonl)

# 3. Execute — re-pipe the SAME inputs
hubspot objects search --type contacts --filter "lifecyclestage=subscriber" \
| jq -c '{id}' \
| hubspot objects delete --type contacts --digest "$digest" --confirm "$confirm"
```

## Recovery via `hubspot history`

Every destructive op (and its dry-run) is logged locally. Check what happened in the last hour and what's reversible:

```bash
hubspot history --since 1h --format table
hubspot history --since 24h --kind BulkData       # only bulk ops
hubspot history --since 7d --kind MetadataDestroy # schema deletes
```

`history` does not currently restore records — it's an audit log. See `CLI_IMPROVEMENTS.md` #8 for the revert ask. If you nuked something by mistake, capture the history line and tell the user to restore via the UI.

## Upsert beats search-then-create

For "create if missing, update if present" (the enrichment pattern), use `upsert` — one CLI call per record, no race condition:

```bash
cat external.jsonl \
| jq -c '{idProperty:"email", id:.email, properties:{firstname:.first, lastname:.last, company:.company}}' \
| hubspot objects upsert --type contacts --dry-run

# Or set idProperty once:
cat external.jsonl \
| jq -c '{id:.email, properties:{firstname:.first}}' \
| hubspot objects upsert --type contacts --id-property email
```

## Rate-limit hygiene

There is no true batch endpoint behind `update`/`delete`/`upsert` — the CLI issues one API call per stdin line. Test with `head -n 50` before piping a 50k-row file. If the API starts 429ing, the per-line output will show `{"ok":false,"error":{"status":429,...}}` — split your input file and retry the failed lines.

## Common reshapes

See `resources/json-patterns.md` for the full set. The two you need 90% of the time:

```bash
# Read → update payload
hubspot objects search --type contacts --filter "industry=Tech" \
| jq -c '{id, properties:{lifecyclestage:"marketingqualifiedlead"}}' \
| hubspot objects update --type contacts

# Search → delete list
hubspot objects search --type contacts --filter "!email" \
| jq -c '{id}' \
| hubspot objects delete --type contacts --dry-run
```

## Known constraints

- Some destructive operations may be blocked under user-OAuth (browser login); set `HUBSPOT_ACCESS_TOKEN` (private app token) when running deletes if the CLI returns a permission error. See `CLI_IMPROVEMENTS.md` #9 — `whoami --can ...` preflight is on the ask list.
- `hubspot owners list` returns CRM users; there is no `teams` object. For team-level operations, group by `hubspot_owner_id` client-side.
- No Lists API, no sequences/cadences API in the current CLI surface. See `CLI_IMPROVEMENTS.md` for what's tracked.
