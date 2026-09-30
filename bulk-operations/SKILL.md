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

This is the `hubspot` agent CLI; the `hs` developer CLI (`@hubspot/cli`) is a different tool and does not manage CRM data or workflows. `hubspot <command> --help` is authoritative. If anything in this file contradicts `--help`, trust `--help` and tell the user. Run `hubspot objects types` once at the start of a session to see what object types exist in this portal (standard + custom).

## Submit Feedback

Use the `hubspot feedback` command to send a message to the owners of this CLI tool. Pass `--source agent` so it's attributed to agent traffic (it defaults to `user`):

```bash
hubspot feedback "batch upsert timed out on 5k rows" --source agent
```

This can be anything from:

- Specific bugs and hiccups you encountered
- Things you wish you knew before using the CLI
- Anything your user got confused, frustrated, or upset about
- Anything the user asked for that you couldn't do
- Any tools, capabilities, or skills you wish existed that would make future tasks easier

It takes one short line, attaches to the active HubSpot account, and doesn't block the task — send it and keep going.

## Output shape

Every read command (`list`, `search`, `get`) emits JSONL — one JSON object per line:

```json
{"id":"123","properties":{"email":"jane@example.com","firstname":"Jane"},"createdAt":"...","updatedAt":"...","archived":false,"url":"..."}
```

`--properties email,firstname` limits which fields the server returns under `.properties`. Downstream `jq` should use `.properties.email`, not `.prop_email`.

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

## Bulk flow: paginate first, then reshape, then write

When operating on all records of a type (or all matches of a filter), **always start with `pagination-loop.sh`** — never run a bare `list` or `search` to "check how many there are." A bare call returns at most 100 records and you will have to re-fetch them anyway. To size the job first, use `hubspot objects count --type <t> [--filter "..."]`, which returns the total matching count (e.g. `{"object_type":"contacts","total":42}`) without paging.

The canonical bulk pattern is:

1. **Paginate** all records to a JSONL file
2. **Reshape** with `jq` into the write payload
3. **Pipe** to the write command (`update`, `delete`, etc.) with `--dry-run` first

## Pagination

`list` and `search` return at most 100 records per call. Use `resources/pagination-loop.sh` to collect all pages into a single JSONL file:

```bash
bash resources/pagination-loop.sh <object_type> <output_file> [properties] [extra_flags...]
```

Examples:

```bash
# All contacts with specific properties
bash resources/pagination-loop.sh contacts /tmp/contacts.jsonl email,firstname,lastname

# Search with a filter (passes extra flags through to the CLI)
bash resources/pagination-loop.sh contacts /tmp/leads.jsonl email,firstname '--filter' 'lifecyclestage=lead'

# All deals, default properties
bash resources/pagination-loop.sh deals /tmp/deals.jsonl
```

The script pages through `--after` cursors automatically, prints progress to stderr, and writes JSONL to the output file. Run it as a single foreground command — do not background it or reconstruct the loop inline.

`associations list` also paginates (`--limit` / `--after`, default limit 100): under `--format json` the next-page cursor is at `.meta.next`, null once the last page is reached. A record can have far more associated records than one page holds, so treat a present cursor as "more remain" and page with `--after` until it is null.

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

Irreversible writes — `objects delete`, `merge`, `update`, `upsert`, `associations delete` / `limits-update`, and metadata deletes (workflows, segments, views, reports, schemas, pipelines, properties) — **always** require the two-step dry-run → digest → confirm flow, at ANY row count (one record needs it just as much as 10k). Soft writes (`objects create`, `views create/update/replace-field`, label-only `properties update`, `segments members-add`) run without a digest; their `--dry-run` is a plain preview.

**1. Dry-run** — emits ONE preview line for the whole invocation (not per record), at every size:

```json
{"ok":true,"dry_run":true,"executed":false,"mutation_kind":"RecordMutation","command":"objects delete --type contacts","target":{"kind":"contacts_record","id":"123","name":"123"},"impact":{"records_affected":1,"note":"Delete 1 contacts record(s)","reversible":false},"portal":"123456","digest":"blast-29cfdd48b583","expires_in_seconds":300,"apply_command_hint":"hubspot objects delete --type contacts --digest blast-29cfdd48b583 --confirm '123'"}
```

`mutation_kind` is `RecordMutation` for ≤100 rows and `BulkData` above the bulk threshold — **the digest is present in both cases**, so never filter on `mutation_kind`. Confirm values by command: `objects delete`/`update` → the record ID (single) or the row count (batch of 2+); `objects upsert` → the row count (always); `objects merge` → the secondary ID (one pair) or the row count (batch); metadata deletes → the target's name (workflow/view/report/schema/pipeline), the property/option name, or the row count (batch archives, associations batch ops). Don't construct the confirm value — copy it from `apply_command_hint` (or `.target.id` / `.target.name` on the preview line).

**2. Execute** within 5 minutes (digest TTL 300s): re-pipe the SAME inputs plus `--digest` and `--confirm`:

```bash
# 1. Preview
hubspot objects search --type contacts --filter "lifecyclestage=subscriber" \
| jq -c '{id}' \
| hubspot objects delete --type contacts --dry-run \
| tee /tmp/preview.jsonl

# 2. Lift the digest + confirm value (present at EVERY row count)
digest=$(jq -r 'select(.digest != null) | .digest' /tmp/preview.jsonl)
confirm=$(jq -r 'select(.digest != null) | .target.id' /tmp/preview.jsonl)

# 3. Execute — re-pipe the SAME inputs
hubspot objects search --type contacts --filter "lifecyclestage=subscriber" \
| jq -c '{id}' \
| hubspot objects delete --type contacts --digest "$digest" --confirm "$confirm"
```

Executing without `--digest` fails with `digest_required` (the error's `next_step` names the dry-run command); a wrong confirm fails with `confirm_mismatch`; an expired digest with `digest_expired`. `--force` is deprecated and ignored.

## Recovery via `hubspot history`

Every destructive op (and its dry-run) is logged locally. Check what happened in the last hour and what's reversible:

```bash
hubspot history --since 1h --format table
hubspot history --since 24h --kind BulkData       # only bulk ops
hubspot history --since 7d --kind MetadataDestroy # schema deletes
```

`history` does not currently restore records — it's an audit log. If you deleted something by mistake, capture the history line and tell the user to restore via the UI.

For CRM property *source* history (who or what changed a property — `WORKFLOW`, `INTEGRATION`, `IMPORT`, `CRM_UI`), use `hubspot objects history --type <t> --properties <p>`. It flattens each property's version history into one row per change; UI-driven (`CRM_UI`) changes are excluded by default (`--include-ui` to keep them). Add `--id <recordId>` to read one record, or omit it to scan a page. This is separate from the local `hubspot history` audit log above — use it to investigate why a property changed after a bulk op.

## Upsert beats search-then-create

For "create if missing, update if present" (the enrichment pattern), use `upsert` — one CLI call per record, no race condition:

```bash
cat external.jsonl \
| jq -c '{idProperty:"email", id:.email, properties:{firstname:.first, lastname:.last, company:.company}}' \
| hubspot objects upsert --type contacts --dry-run

# Or set idProperty once (upsert is irreversible — dry-run first, then execute):
cat external.jsonl \
| jq -c '{id:.email, properties:{firstname:.first}}' \
| hubspot objects upsert --type contacts --id-property email --dry-run \
| tee /tmp/upsert.preview.jsonl

digest=$(jq -r 'select(.digest != null) | .digest' /tmp/upsert.preview.jsonl)
confirm=$(jq -r 'select(.digest != null) | .target.id' /tmp/upsert.preview.jsonl)   # upsert confirm = the row count, even for one row

cat external.jsonl \
| jq -c '{id:.email, properties:{firstname:.first}}' \
| hubspot objects upsert --type contacts --id-property email --digest "$digest" --confirm "$confirm"
```

## Rate-limit hygiene

`objects delete` issues one API call per stdin line; `update`/`upsert` batch 100 rows per API call. Test with `head -n 50` before piping a 50k-row file — or use `hubspot imports` for purpose-built bulk ingest. If the API starts 429ing, the per-line output will show `{"ok":false,"error":{"status":429,...}}` — split your input file and retry the failed lines.

For large CSV ingests, `hubspot imports` is the purpose-built path: `imports start` (from a CSV file + import-request JSON; supports `--dry-run`), `imports list`, `imports get <id>`, `imports cancel <id>` (irreversible — dry-run first, then `--digest`/`--confirm` with the import ID), and `imports errors <id>`. Run `hubspot imports --help` for the request shape.

## Common reshapes

See `resources/json-patterns.md` for the full set. The two you need 90% of the time:

```bash
# Read → update payload (update is irreversible — dry-run, then re-pipe with the digest/confirm from the preview)
hubspot objects search --type contacts --filter "industry=Tech" \
| jq -c '{id, properties:{lifecyclestage:"marketingqualifiedlead"}}' \
| hubspot objects update --type contacts --dry-run \
| tee /tmp/update.preview.jsonl

digest=$(jq -r 'select(.digest != null) | .digest' /tmp/update.preview.jsonl)
confirm=$(jq -r 'select(.digest != null) | .target.id' /tmp/update.preview.jsonl)   # single: record ID; batch of 2+: row count

hubspot objects search --type contacts --filter "industry=Tech" \
| jq -c '{id, properties:{lifecyclestage:"marketingqualifiedlead"}}' \
| hubspot objects update --type contacts --digest "$digest" --confirm "$confirm"

# Search → delete list (delete is irreversible — dry-run, lift, then re-pipe with --digest/--confirm)
hubspot objects search --type contacts --filter "!email" \
| jq -c '{id}' \
| hubspot objects delete --type contacts --dry-run \
| tee /tmp/delete.preview.jsonl

digest=$(jq -r 'select(.digest != null) | .digest' /tmp/delete.preview.jsonl)
confirm=$(jq -r 'select(.digest != null) | .target.id' /tmp/delete.preview.jsonl)   # single: record ID; batch of 2+: row count

hubspot objects search --type contacts --filter "!email" \
| jq -c '{id}' \
| hubspot objects delete --type contacts --digest "$digest" --confirm "$confirm"
```

## Known constraints

- `objects delete` works under both user-OAuth (browser login, with the object's write scope) and a service key; a 403 means the active token is missing that write scope. The exception is the `--gdpr` permanent purge, which requires a service key (`HUBSPOT_ACCESS_TOKEN`) — the GDPR endpoint does not accept user OAuth tokens. `objects update`/`merge`/`upsert` also accept either token type. Some destructive operations (e.g. `associations` create/delete/batch/labels/limits, `schemas delete`) remain service-key-only and are enforced server-side, so `HUBSPOT_SKIP_AUTH_CHECK` will not get a user token past them.
- `hubspot owners list` returns CRM users; there is no `teams` object. For team-level operations, group by `hubspot_owner_id` client-side.
- `hubspot segments` provides CRM lists (Lists API): `list`, `get`, `create`, `update` (metadata), `update-filters`, `delete`, `restore`, and `members-list` / `members-add` / `members-remove`.
- `hubspot sequences` provides read-only access to Sales Hub sequences: `list --user-id <id>` (paginated, `--name` filter), `get <id> --user-id <id>` (steps + settings), and `enrollments <contact_id>` (a contact's enrollment history). Sequences are a product API surface (Sales Hub Professional+, `automation.sequences.read` scope), not a CRM object type — `objects list --type sequences` does not work, and there is no create/update/delete/enroll.
- **Maintaining this section:** the command surface grows — do not assume an API is absent because it was when this was written. When a new command family ships (see `CHANGELOG.md`), revisit these constraints. `hubspot --help` is authoritative for what exists today.
