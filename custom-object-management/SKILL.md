---
name: custom-object-management
description: Discover, create, and manage custom CRM object schemas. Use when working with non-standard object types, defining new object schemas with properties, or inspecting what custom objects exist in a portal.
triggers:
  - "create custom object"
  - "custom object schema"
  - "define new object type"
  - "custom crm object"
  - "new object schema"
  - "what custom objects exist"
  - "add a schema"
  - "create an object type"
  - "custom object type"
  - "list object schemas"
  - "object schema"
---

## Overview

Custom object schemas define new CRM object types beyond HubSpot's standard set (contacts, companies, deals, etc.). Once a schema exists, records of that type are managed through the standard `hubspot objects` commands.

Schema write operations require a **private app token** with `crm.schemas.custom.write` scope:

```bash
export HUBSPOT_ACCESS_TOKEN=<your-private-app-token>
```

## Discovering existing schemas

List all schemas (standard and custom):

```bash
hubspot schemas list
# {"name":"equipment","label":"Equipment","singular":"Equipment","objectTypeId":"2-12345","source":"custom"}
# {"name":"contacts","label":"Contacts","singular":"Contact","objectTypeId":"0-1","source":"standard"}
```

Inspect a schema's full definition (properties, associations, labels):

```bash
hubspot schemas get equipment
# Works by name — no need to look up the objectTypeId first
```

Filter to only custom schemas:

```bash
hubspot schemas list --format jsonl | jq 'select(.source == "custom")'
```

Check what object types are available for use with `hubspot objects`:

```bash
hubspot objects types
# {"name":"equipment","label":"Equipment","singular":"Equipment","objectTypeId":"2-12345","source":"custom"}
```

## Creating a new custom object schema

Prepare a JSON body and pipe or pass it via `--file`:

```bash
cat > equipment-schema.json << 'EOF'
{
  "name": "equipment",
  "labels": {
    "singular": "Equipment",
    "plural": "Equipment"
  },
  "primaryDisplayProperty": "equipment_name",
  "requiredProperties": ["equipment_name"],
  "properties": [
    {
      "name": "equipment_name",
      "label": "Name",
      "type": "string",
      "fieldType": "text"
    },
    {
      "name": "serial_number",
      "label": "Serial Number",
      "type": "string",
      "fieldType": "text"
    },
    {
      "name": "purchase_date",
      "label": "Purchase Date",
      "type": "date",
      "fieldType": "date"
    }
  ],
  "associatedObjects": ["contacts", "companies"]
}
EOF

# Preview without creating
cat equipment-schema.json | hubspot schemas create --dry-run

# Create the schema
hubspot schemas create --file equipment-schema.json
# {"name":"equipment","ok":true,"data":{...}}
```

After creation, the new object type is immediately available via `hubspot objects`. Use the schema **name** (not the `objectTypeId`) — it resolves automatically:

```bash
hubspot objects list --type equipment
hubspot objects create --type equipment --property equipment_name="Laptop" --property serial_number="SN-001"
hubspot objects search --type equipment --filter "equipment_name=Laptop"
```

> The `objectTypeId` (e.g. `2-12345`) also works as `--type`, but the name is easier. The objectTypeId is only needed when configuring workflow `PLATFORM_FLOW` targets.

## Adding properties after creation

Use `hubspot properties create` to add fields to an existing custom object:

```bash
hubspot properties create --object equipment --name condition --label "Condition" --type enumeration --field-type select
hubspot properties create --object equipment --name notes --label "Notes" --type string --field-type textarea
hubspot properties list --object equipment
```

## Updating schema metadata

Patch labels or other metadata (does not affect properties — use `hubspot properties` for that):

```bash
echo '{"labels":{"singular":"Device","plural":"Devices"}}' | hubspot schemas update equipment
# {"name":"equipment","ok":true,"data":{...}}
```

## Deleting a schema

Deleting a schema **permanently removes all records** of that type. Cannot be undone.

```bash
# Preview
hubspot schemas delete equipment --dry-run

# Execute (requires --force)
hubspot schemas delete equipment --force
```

## Working with custom object records

Once a schema exists, all standard CRUD commands work. Pass the schema name directly — no need to look up the `objectTypeId`:

```bash
# List records (use --properties to see fields beyond the ID)
hubspot objects list --type equipment --properties equipment_name,serial_number

# Get a single record
hubspot objects get --type equipment <id> --properties equipment_name,serial_number

# Create a record
hubspot objects create --type equipment --property equipment_name="Laptop" --property serial_number="SN-001"

# Search
hubspot objects search --type equipment --filter "condition=broken"

# Update
hubspot objects update --type equipment <id> --property condition=working

# Bulk create from JSONL
cat new-equipment.jsonl | hubspot objects create --type equipment

# Associate with a contact
hubspot associations create --from equipment:789 --to contacts:12345
```

If you don't know a custom schema's `objectTypeId`, get it from `hubspot schemas list` — look for `"source":"custom"` entries.

## Key fields in schema responses

| Field | Description |
|---|---|
| `name` | Internal API name used in all commands |
| `objectTypeId` | Numeric ID (e.g. `2-12345`) needed for workflow `PLATFORM_FLOW` configs |
| `labels.plural` | Display name shown in HubSpot UI |
| `labels.singular` | Singular form for UI and reference |
| `primaryDisplayProperty` | Property shown as the record's display name |
| `associatedObjects` | Object types this schema can associate with |

The `objectTypeId` for custom schemas always starts with `2-`. It is only needed when configuring `PLATFORM_FLOW` workflows — all other commands accept the schema name directly.
