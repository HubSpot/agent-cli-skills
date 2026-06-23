---
name: workflow-automation
description: List, inspect, create, update, and delete HubSpot workflows (v4 flows API) from the `hubspot` agent CLI, not the `hs` developer CLI.
triggers:
  - "workflow"
  - "automation"
  - "automated flow"
  - "enrollment trigger"
  - "find workflow by name"
  - "duplicate workflow"
  - "update workflow"
  - "delete workflow"
  - "create a workflow"
  - "create a workflow with the hubspot cli"
  - "build an automation"
  - "does the cli support workflows"
---

## Which CLI

Two different HubSpot CLIs share a confusing resemblance — don't mix them up:

- **`hubspot`** — the HubSpot **agent CLI** that this skill library targets. It manages CRM data and automation, and it **does** have native workflow commands: `hubspot workflows list|get|create|update|delete`.
- **`hs`** — the HubSpot **developer CLI** (`@hubspot/cli`), for building dev projects: themes, modules, serverless functions, UI extensions, and private apps (`hs project`, `hs upload`, `hs create`). It does **not** create or manage workflow records.

To create or manage a workflow, use `hubspot workflows ...` — not `hs`.

If anything here ever drifts, `hubspot workflows --help` and `hs --help` are authoritative.

## Resources

| File | When to use |
|---|---|
| `resources/workflow-json-reference.md` | Body shape for create/update — the action graph, branching/convergence, enrollment, full-PUT pitfall |
| `resources/example-contact-flow.json` | Minimal valid `CONTACT_FLOW` skeleton for `hubspot workflows create --file` |
| `resources/example-branching-flow.json` | Illustrates branch convergence — two paths pointing `connection.nextActionId` at one shared downstream action |

## Source of truth

`hubspot workflows --help` lists five subcommands: `list`, `get`, `create`, `update`, `delete`. There is **no `search`** — finding by name is `list | jq`. For JSONL piping, pagination, and destructive dry-run/digest/confirm patterns, this skill builds on `bulk-operations/SKILL.md` — re-read that first.

## 1. List + find by name

```bash
hubspot workflows list                       # JSONL: id, name, isEnabled, type, objectTypeId, revisionId
hubspot workflows list --format table        # for human scanning

# Find by name — case-insensitive substring
hubspot workflows list | jq -c 'select(.name | test("Welcome"; "i"))'

# Exact match
hubspot workflows list | jq -c 'select(.name == "MQL Nurture")'
```

List is paginated at 100 per call. Loop with `--after` until `meta.next` is empty — see `bulk-operations/SKILL.md` "Pagination". See `resources/json-patterns.md` in `bulk-operations` for more `jq` filters.

## 2. Get + read shape

```bash
hubspot workflows get 12345678                            # one
hubspot workflows get 12345678 87654321                   # batch positional
printf '%s\n' 12345678 87654321 | hubspot workflows get   # batch stdin
hubspot workflows get 12345678 > workflow.json            # save for editing
```

Get returns the full body (`actions`, `enrollmentCriteria`, `revisionId`, …) — the shape required by create/update. See `resources/workflow-json-reference.md`.

## 3. Create from JSON

```bash
hubspot workflows create --file workflow.json --dry-run
hubspot workflows create --file workflow.json
cat workflow.json | hubspot workflows create         # stdin also works
```

Set `type` (`CONTACT_FLOW` or `PLATFORM_FLOW`), `flowType` (`WORKFLOW`), and `objectTypeId` (e.g. `0-1` for contacts) — all required on create. See `resources/workflow-json-reference.md` for the body shape and `resources/example-contact-flow.json` for the minimal template. **Easiest path: `get` an existing similar workflow as a starting template** rather than hand-writing the JSON.

**Branching and convergence.** A `LIST_BRANCH` action forks the path on filter criteria; each branch — and the `defaultBranch` — carries a `connection` to the action it continues to. Because connections target actions by `nextActionId`, **branches can converge**: point two branches at the same `actionId` and both paths continue to one shared action, no duplication. See the branching section of `resources/workflow-json-reference.md` and `resources/example-branching-flow.json`.

## 4. Update — full PUT, get-modify-put round-trip

Update is a **full replace**. The body must include `revisionId` (from `get`) and `type`. Read-only fields (`createdAt`, `updatedAt`, `dataSources`) are stripped automatically. Update is gated: dry-run first, then re-run with `--digest <hash> --confirm <flowId>`.

```bash
# 1. Fetch current state
hubspot workflows get 12345678 > workflow.json

# 2. Edit workflow.json (preserve revisionId, type, and any field you want to keep)

# 3. Dry-run — emits a digest
hubspot workflows update 12345678 --file workflow.json --dry-run

# 4. Apply — confirm value is the flow id
hubspot workflows update 12345678 --file workflow.json \
  --digest blast-xxxxxxxx --confirm 12345678
```

**Pitfall:** partial bodies silently clear fields. Sending only `actions` will wipe `enrollmentCriteria`. Always start from the full `get` response.

## 5. Delete — destructive, link to bulk safety flow

```bash
# 1. Dry-run — emits a digest + the confirm hint
hubspot workflows delete 12345678 --dry-run

# 2. Re-run with digest + confirm. Confirm value is the workflow's NAME, not its id.
hubspot workflows delete 12345678 --digest blast-xxxxxxxx --confirm "New lead routing"
```

The dry-run output includes an `apply_command_hint` — copy the exact confirm string from there to avoid quoting surprises. Workflows cannot be restored through the automation API after deletion; check `hubspot history --since 1h` for an audit record. The full safety pattern (digest, 5-minute expiry, history recovery) is documented in `bulk-operations/SKILL.md` "Safe destructive workflow".

## Known limitations

- No `hubspot workflows search` — `list | jq` is the workaround.
- No Lists API in the CLI — list-membership enrollment triggers must be wired up in the UI.
- No sequences/cadences API. `dataSources` is read-only — cannot be rewired via update.
