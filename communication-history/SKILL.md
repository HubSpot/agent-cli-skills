---
name: communication-history
description: Retrieve activity history (calls, emails, notes, meetings, tasks) for a CRM record and assemble pre-call briefs.
triggers:
  - "pre-call research"
  - "call history"
  - "email history"
  - "recent activity"
  - "communication history"
  - "meeting prep"
---

Read `bulk-operations/SKILL.md` first — JSONL piping, batch read, and `jq` reshape patterns (`resources/json-patterns.md`) apply. `hubspot activities list --help` is the source of truth.

## Output shape

`activities list` returns one flat row per activity, sorted newest-first: `{id, type, timestamp, title, body, status, owner_id}`. `timestamp` is ISO 8601; `type` is `CALL|EMAIL|NOTE|MEETING|TASK`. Different from the raw `hs_call_*` / `hs_timestamp` (Unix ms) on the underlying objects — fetch those with `hubspot objects get --type calls` if needed.

## All activity for a record

Pass exactly one of `--contact`, `--deal`, `--company`, `--ticket`. Use `--type CALL|EMAIL|NOTE|MEETING|TASK` to filter, `--limit N` for the most recent N:

```bash
hubspot activities list --contact 73235
hubspot activities list --deal 67890 --type CALL
hubspot activities list --contact 73235 --limit 10
```

## Client-side date filter

ISO 8601 strings compare lexicographically.

```bash
CUTOFF=$(date -v-30d +%Y-%m-%dT%H:%M:%SZ)          # macOS
# CUTOFF=$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)  # Linux
hubspot activities list --contact 73235 \
| jq -c --arg cutoff "$CUTOFF" 'select(.timestamp > $cutoff)'
```

## Compact timeline

```bash
hubspot activities list --contact 73235 --limit 20 \
| jq -r '"\(.timestamp[0:10])  \(.type)  \(.title)"'
```

## Pre-call brief

Four piped commands: contact + company + open deals + activity. Use batch `objects get` over stdin — never `xargs -I{}` (see `bulk-operations/SKILL.md`).

```bash
cid=73235
echo "=== Contact ==="
hubspot objects get --type contacts $cid \
  --properties email,firstname,lastname,phone,jobtitle,lifecyclestage --format table

echo "=== Company ==="
hubspot associations list --from contacts:$cid --to companies \
| jq -c '{id}' \
| hubspot objects get --type companies --properties name,domain,industry,annualrevenue --format table

echo "=== Open Deals ==="
hubspot associations list --from contacts:$cid --to deals \
| jq -c '{id}' \
| hubspot objects get --type deals --properties dealname,amount,dealstage,closedate,hs_is_closed \
| jq -c 'select(.properties.hs_is_closed != "true")'

echo "=== Recent Activity ==="
hubspot activities list --contact $cid --limit 10 \
| jq -r '"\(.timestamp[0:10])  \(.type)  \(.title)"'
```

## Constraints

- `--limit` max 100 and no `--after` cursor — long histories can't be paged. `body` can be long; use the compact timeline for skimming.
