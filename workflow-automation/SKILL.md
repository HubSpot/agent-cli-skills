---
name: workflow-automation
description: List, inspect, create, update, and delete HubSpot workflows (automated flows) from the CLI, including duplicating a workflow as a template.
triggers:
  - "create workflow"
  - "automation"
  - "workflow"
  - "automated flow"
  - "enrollment trigger"
  - "contact flow"
  - "find workflow by name"
  - "duplicate workflow"
  - "update workflow"
---

## Resources

| File | When to use |
|---|---|
| `resources/workflow-json-reference.md` | Structure of a workflow JSON object: all fields, action types, enrollment criteria, and the full-PUT update rule — read before editing or creating a workflow |
| `resources/example-contact-flow.json` | Minimal valid CONTACT_FLOW template ready to pass to `hubspot workflows create --file` |
| `resources/find-workflow-by-name.sh` | Script for finding a workflow by name substring since the API has no search endpoint |

## Context
HubSpot workflows automate contact, deal, and company lifecycle actions. The CLI provides full CRUD for workflows, but search is not supported by the HubSpot API — finding a workflow by name requires listing all workflows and filtering the output locally. Updates are full replacements (PUT), so always fetch the current state before modifying.

## Workflow Type Field Values

| Type | Object |
|---|---|
| CONTACT_FLOW | Contact-based enrollment |
| PLATFORM_FLOW | Company, deal, ticket, or other object-based enrollment |

## Key Workflows

### List All Workflows

```bash
# Table format — useful for scanning IDs and names
hubspot workflows list --format table

# JSONL — use when filtering or processing workflow records
hubspot workflows list

# With a limit
hubspot workflows list --limit 50
```

### Find a Workflow by Name

Workflow search is not supported by the API. List all workflows and filter by name from the output.

```bash
# List all workflows and read the output to find by name
hubspot workflows list

# Filter with jq: case-insensitive name match
hubspot workflows list \
| jq -c 'select(.name | test("Welcome"; "i"))'

# Filter with jq: exact name match
hubspot workflows list \
| jq -c 'select(.name == "MQL Nurture Sequence")'

# Filter with jq: by type
hubspot workflows list \
| jq -c 'select(.type == "CONTACT_FLOW")'
```

### Inspect a Workflow's Full Structure

```bash
hubspot workflows get <flowId>

# Save to file for editing
hubspot workflows get <flowId> > workflow.json
```

### Duplicate a Workflow as a Template

```bash
# Step 1: get the source workflow
hubspot workflows get 12345 > workflow.json

# Step 2: edit workflow.json
# - Change the "name" field to the new workflow name
# - Update enrollment triggers as needed
# - Read-only fields (createdAt, updatedAt, dataSources) are stripped automatically

# Step 3: validate with dry-run
hubspot workflows create --file workflow.json --dry-run

# Step 4: create the new workflow
hubspot workflows create --file workflow.json
```

### Create a New Workflow from a File

```bash
hubspot workflows create --file new_workflow.json --dry-run
hubspot workflows create --file new_workflow.json
```

### Update a Workflow (Full Replacement)

Update is a full PUT — it replaces the entire workflow definition. Always get the current state first.

```bash
# Step 1: fetch current state
hubspot workflows get 12345 > workflow.json

# Step 2: edit workflow.json as needed

# Step 3: validate
hubspot workflows update 12345 --file workflow.json --dry-run

# Step 4: apply
hubspot workflows update 12345 --file workflow.json
```

### Delete a Workflow

```bash
hubspot workflows delete 12345 --force

# Dry-run to confirm which workflow would be deleted
hubspot workflows delete 12345 --force --dry-run
```

### Audit All Workflows (Name, Type, Status)

```bash
hubspot workflows list \
| jq -r '[.id, .name, .type, .isEnabled] | @tsv' \
| column -t
```

### Find Enabled vs. Disabled Workflows

```bash
# Enabled workflows
hubspot workflows list | jq -c 'select(.isEnabled == true)'

# Disabled workflows
hubspot workflows list | jq -c 'select(.isEnabled == false)'
```

## Key Rules
- **No workflow search endpoint** — `hubspot workflows search` does not exist. The HubSpot API has no search for workflows. Always use `hubspot workflows list` and filter the output by name. This also means `hubspot objects search --type workflows` will not work.
- **Update is a full PUT** — partial patching is not supported. Always `get` the workflow first, modify the JSON, then `update`.
- **Read-only fields** (`createdAt`, `updatedAt`, `dataSources`) are stripped automatically on create and update. You do not need to remove them manually.
- **Always `--dry-run`** before creating or updating workflows in production.

## Known Limitations
- No workflow search endpoint — the HubSpot API does not support searching workflows by name or property. Use `hubspot workflows list` and filter the output locally to find workflows by name.
- No Lists API in the CLI — you cannot create list-based enrollment triggers from the CLI. Configure list enrollment triggers in the HubSpot UI after creating the workflow.
- No sequences/cadences API.
- Workflow enrollment criteria and action definitions are complex nested JSON. Use `hubspot workflows get` on an existing similar workflow as a starting template rather than writing the JSON from scratch.
