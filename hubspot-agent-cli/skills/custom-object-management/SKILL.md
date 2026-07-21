---
name: custom-object-management
description: Discover, create, update, and delete custom CRM object schemas. Use when defining a new object type, inspecting existing schemas, or removing one. Record CRUD on custom objects is identical to standard objects — see `bulk-operations`.
triggers:
  - "create custom object"
  - "custom object schema"
  - "define new object type"
  - "list object schemas"
  - "delete custom object"
  - "update schema labels"
  - "what custom objects exist"
---

## Source of truth

`hubspot schemas --help` is authoritative. Subcommands: `list`, `get`, `create`, `update` (metadata only), `delete` (destructive). Schema writes require a private app token with `crm.schemas.custom.write`. Read `bulk-operations/SKILL.md` first — every command here uses its JSONL conventions, and `schemas delete` uses its dry-run / digest / confirm flow.

## Discover existing schemas

```bash
hubspot schemas list                                       # JSONL: name, label, singular, objectTypeId, source
hubspot schemas list | jq 'select(.source=="custom")'      # custom only
hubspot objects types | jq -c 'select(.source=="custom")'  # same set, also shown to confirm `--type` resolves
```

`name` is what every other command takes. `objectTypeId` (e.g. `2-12345678`) is only needed for workflow `PLATFORM_FLOW` targets.

## Inspect one schema

```bash
hubspot schemas get pets
```

Returns the full definition — properties, associations, labels, `requiredProperties`, `primaryDisplayProperty`, `fullyQualifiedName`. Reshape with `jq` as needed (see `bulk-operations/resources/json-patterns.md`).

## Create a schema

Build a JSON body and pipe it (or pass `--file`). Minimal valid body:

```json
{
  "name": "equipment",
  "labels": {"singular": "Equipment", "plural": "Equipment"},
  "primaryDisplayProperty": "equipment_name",
  "requiredProperties": ["equipment_name"],
  "properties": [
    {"name": "equipment_name", "label": "Name", "type": "string", "fieldType": "text"}
  ],
  "associatedObjects": ["contacts"]
}
```

```bash
cat equipment-schema.json | hubspot schemas create --dry-run   # preview
hubspot schemas create --file equipment-schema.json            # execute
```

Add more properties later with `hubspot properties create --type <name> ...`.

## Update schema metadata

`update` patches labels / description only. Property edits go through `hubspot properties`.

```bash
echo '{"labels":{"singular":"Device","plural":"Devices"}}' | hubspot schemas update equipment
```

`update` also supports `--dry-run` → digest → re-run with `--digest --confirm <name>` (see `bulk-operations/SKILL.md` for the pattern).

## Delete a schema (destructive)

Schema delete is destructive and irreversible — it permanently removes the schema **and every record of that type**. It is gated as `MetadataDestroy`: every delete requires `--dry-run` first, then re-run with `--digest <hash> --confirm <name>` within 5 minutes.

Follow the three-step flow documented in `bulk-operations/SKILL.md` ("Safe destructive workflow"). For schemas, the confirm value is the schema name:

```bash
hubspot schemas delete equipment --dry-run
# → digest=blast-... ; apply_command_hint shows: --digest <hash> --confirm 'equipment'
hubspot schemas delete equipment --digest <hash> --confirm equipment
```

Check `hubspot history --since 24h --kind MetadataDestroy` to audit recent schema deletes.

## Using the schema after creation

Once a schema exists, all `hubspot objects ...` commands accept its `name` as `--type` (e.g. `--type pets`). Record CRUD, search, association, bulk upsert — all identical to standard objects. Don't re-implement those flows here; see `bulk-operations/SKILL.md` and `crm-lookup`.
