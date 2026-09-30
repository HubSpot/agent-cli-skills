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
  - "transcripts"
  - "call transcripts"
  - "dump transcripts"
  - "fetch transcripts"
  - "call recordings"
  - "export transcripts"
---

Read `bulk-operations/SKILL.md` first — JSONL piping, batch read, and `jq` reshape patterns (`resources/json-patterns.md`) apply. `hubspot activities list --help` is the source of truth.

## Output shape

`activities list` returns one flat row per activity, sorted newest-first: `{id, type, timestamp, lastModified, title, body, status, owner_id}`. `timestamp` and `lastModified` are ISO 8601; `type` is `CALL|EMAIL|NOTE|MEETING|TASK`. Different from the raw `hs_call_*` / `hs_timestamp` (Unix ms) on the underlying objects — fetch those with `hubspot objects get --type calls` if needed.

For point-in-time filtering compare `lastModified` (`hs_lastmodifieddate`, when the body was last edited), not `timestamp` (engagement creation time) — otherwise you include content edited after your cutoff.

## All activity for a record

Pass exactly one of `--contact`, `--deal`, `--company`, `--ticket` (or `--type <object_type> --record <id>` for any other object type). Use `--activity-type CALL|EMAIL|NOTE|MEETING|TASK` to filter by activity kind, `--limit N` for the most recent N. Note `--type` is now the object-type flag, not the activity-kind filter:

```bash
hubspot activities list --contact 73235
hubspot activities list --deal 67890 --activity-type CALL
hubspot activities list --type subscriptions --record 45123 --activity-type NOTE
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

## Transcripts

Fetch the transcript for a single call or meeting by its activity ID (from `hubspot activities list`). Defaults to `CALL`; pass `--activity-type MEETING` for a meeting, and `--fields` to limit which enrichment fields are fetched:

```bash
hubspot activities transcript get 54321
hubspot activities transcript get 54321 --activity-type MEETING
hubspot activities transcript get 54321 --fields recordingUrl,aiSummary
```

Dump all call transcripts to a file:

```bash
hubspot objects list --type calls --limit 100 --properties hs_call_title \
| jq -r '.id' \
| while read -r call_id; do
    hubspot activities transcript get "$call_id"
  done > /tmp/transcripts.jsonl
```

Output shape: `{"transcriptId":"...","activityId":...,"transcriptSource":"...","transcriptStatus":"READY","numUtterances":3,"recordingUrl":"...","aiSummary":"...","transcriptionProvider":null,"utterances":[...],"createdAt":"...","updatedAt":"..."}`. `transcriptStatus`, `numUtterances`, `recordingUrl`, `aiSummary`, and `transcriptionProvider` are the five enrichment fields — present only on enriched transcripts, and `--fields` limits which are fetched. The `utterances` array holds the speech content; empty if no transcript was recorded or uploaded.

Deleting a transcript is irreversible: `hubspot activities transcript delete <id> --dry-run` first, then re-run with `--digest`/`--confirm` (confirm the target name from the preview line).

## Constraints

- `--limit` defaults to 100 and there is no `--after` cursor — long histories can't be paged. `body` can be long; use the compact timeline for skimming.
