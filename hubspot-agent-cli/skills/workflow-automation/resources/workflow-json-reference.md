# Workflow JSON Reference

This document describes the structure of a HubSpot workflow (automation flow) JSON as returned by `hubspot workflows get <id>`. Use this as a reference when reading, editing, or creating workflow JSON files.

---

## Top-Level Fields

| Field | Type | Writable | Notes |
|---|---|---|---|
| `id` | string | **read-only** | Workflow ID assigned by HubSpot |
| `name` | string | yes | Display name of the workflow |
| `type` | string | yes | `CONTACT_FLOW` (contacts) or `PLATFORM_FLOW` (deal, company, ticket, custom object) |
| `isEnabled` | boolean | yes | `true` activates the workflow; `false` for drafts and templates |
| `objectTypeId` | string | yes | Object type the flow enrolls (e.g. `0-1` contacts, `0-2` companies, `0-3` deals). Required for `PLATFORM_FLOW` |
| `revisionId` | string | required on update | Returned by `get`; the API uses it for optimistic concurrency on PUT |
| `createdAt` | string | **read-only** | Stripped before request on create/update |
| `updatedAt` | string | **read-only** | Stripped before request on create/update |
| `dataSources` | array | **read-only** | Stripped before request on create/update |
| `enrollmentCriteria` | object | yes | Defines which contacts/records enroll (see below) |
| `actions` | array | yes | Ordered list of actions the workflow executes (see below) |
| `suppressionListIds` | array | yes | List IDs whose members are excluded from enrollment |

### `type` Values

| Value | Enrolls |
|---|---|
| `CONTACT_FLOW` | Contact records |
| `PLATFORM_FLOW` | Company, deal, ticket, or other object records |

---

## `enrollmentCriteria`

Controls which records enter the workflow. Uses a nested filter group structure with AND/OR logic.

```json
"enrollmentCriteria": {
  "filterGroups": [
    {
      "filters": [
        {
          "property": "lifecyclestage",
          "operation": {
            "operationType": "ENUMERATION",
            "operator": "IS_ANY_OF",
            "values": ["lead"]
          }
        }
      ]
    }
  ],
  "type": "OR"
}
```

- `filterGroups` — array of groups; records matching **any** group are enrolled (OR between groups)
- `filters` within a group — records must match **all** filters to satisfy that group (AND within a group)
- `operation.operationType` — common values: `ENUMERATION`, `STRING`, `NUMBER`, `BOOL`
- `operation.operator` — common values: `IS_ANY_OF`, `IS_NONE_OF`, `EQ`, `NEQ`, `GT`, `LT`, `HAS_PROPERTY`, `NOT_HAS_PROPERTY`

---

## `actions` Array

An ordered array of action objects. Each action has at minimum a `type` field.

### Common Action Types

#### `SET_CONTACT_PROPERTY`
Sets a property value on the enrolled contact.

```json
{
  "type": "SET_CONTACT_PROPERTY",
  "propertyName": "hs_lead_status",
  "newValue": "IN_PROGRESS"
}
```

#### `SEND_EMAIL`
Sends a marketing email. Requires the email ID from HubSpot's email tool.

```json
{
  "type": "SEND_EMAIL",
  "emailId": 12345
}
```

#### `CREATE_TASK`
Creates a CRM task assigned to the contact owner.

```json
{
  "type": "CREATE_TASK",
  "subject": "Follow up with lead",
  "taskType": "CALL",
  "dueDate": {
    "delayMillis": 86400000
  }
}
```

#### `DELAY`
Pauses execution for a fixed duration before the next action.

```json
{
  "type": "DELAY",
  "delayMillis": 86400000
}
```

`delayMillis` is milliseconds. Common values: `3600000` (1 hour), `86400000` (1 day), `604800000` (7 days).

#### `BRANCH`
Forks the workflow based on a condition. Each branch has its own `actions` array.

```json
{
  "type": "BRANCH",
  "filterBranches": [
    {
      "filterBranchType": "OR",
      "filters": [
        {
          "property": "hs_lead_status",
          "operation": {
            "operationType": "ENUMERATION",
            "operator": "IS_ANY_OF",
            "values": ["CONNECTED"]
          }
        }
      ],
      "actions": []
    }
  ],
  "defaultBranchActions": []
}
```

---

## `suppressionListIds`

An array of HubSpot list IDs. Contacts on any of these lists will not enroll even if they match `enrollmentCriteria`.

```json
"suppressionListIds": [101, 202]
```

Use an empty array `[]` if no suppression lists are needed.

---

## Key Rules

See `SKILL.md` for the authoritative command patterns. One non-obvious consequence worth noting here:

**Partial edits silently corrupt workflows.** Because update is a full PUT, sending only an `actions` array without `enrollmentCriteria` will clear the enrollment trigger entirely — no error, no warning. Always start from the full `get` response.
