# Workflow JSON Reference

This describes the body of a HubSpot automation flow as used by `hubspot workflows get`, `create`, and `update`. Those commands call the public `/automation/v4/flows` API and pass the JSON straight through, so this body **is** the v4 flow shape.

> **What's verified here.** The structure below is grounded in HubSpot's public Automation V4 OpenAPI spec and the `hubspot` CLI's own acceptance test. What is **not** verified here is the exact `actionTypeId` / `fields` for each concrete action (a "set property" vs a "create task" step, etc.) — those are specific to each action type and version. Get them by copying a real action (next section), not from this doc.

## Start from a real workflow

The most reliable way to author a flow is to **`get` an existing one and modify it** — don't hand-write the JSON from scratch:

```bash
hubspot workflows list | jq -c 'select(.name | test("welcome"; "i"))'   # find a similar flow
hubspot workflows get <id> > workflow.json                              # copy its real shape
```

A real `get` gives you exact `actionTypeId`, `actionTypeVersion`, and `fields` values for every action — the parts this reference deliberately does not invent.

**No workflow to copy from?** A brand-new portal has nothing to `get`, and there is no CLI command (and no public endpoint) that lists the built-in action types and their `fields`. The automation platform keeps such a catalog internally, but the `hubspot` CLI only does flow CRUD and doesn't surface it. So the reliable bootstrap is one UI round-trip: build the step(s) you need once in the HubSpot UI (Automations → a throwaway flow with the Set property / Delay / Create task / branch actions you're after), then `hubspot workflows get <id>` on it and lift the exact `actionTypeId` / `actionTypeVersion` / `fields` from its `actions[]`. Seed every shape once, then reuse from there.

---

## Top-Level Fields

| Field | Type | Writable | Notes |
|---|---|---|---|
| `name` | string | yes | Display name |
| `description` | string | yes | Optional free text |
| `type` | string | yes | `CONTACT_FLOW` (contacts) or `PLATFORM_FLOW` (deal, company, ticket, custom object) |
| `flowType` | string | yes | `WORKFLOW` for a standard workflow. Required on create |
| `objectTypeId` | string | yes | Object type the flow enrolls — `0-1` contacts, `0-2` companies, `0-3` deals. Set it for `CONTACT_FLOW` (`0-1`) as well as `PLATFORM_FLOW` |
| `isEnabled` | boolean | yes | `true` activates the flow; `false` for drafts and templates |
| `actions` | array | yes | The flow's actions, wired as a graph — see below |
| `startActionId` | string | yes | `actionId` of the first action to run |
| `enrollmentCriteria` | object | yes | Which records enroll — a typed object, see below |
| `suppressionListIds` | array | yes | List IDs whose members are excluded from enrollment |
| `revisionId` | string | required on update | Returned by `get`; the API uses it for optimistic concurrency on PUT |
| `id` | string | **read-only** | Workflow ID assigned by HubSpot |
| `createdAt` / `updatedAt` | string | **read-only** | Stripped before request on create/update |
| `dataSources` | array | **read-only** | Stripped before request on create/update |
| `crmObjectCreationStatus` | string | **read-only** | Must read `COMPLETE` before an update PUT is accepted (provisioned asynchronously after create) |
| `nextAvailableActionId` | integer | **read-only** | Counter the API maintains for assigning new action ids |

The v4 spec marks a few more fields required (`blockedDates`, `canEnrollFromSalesforce`, `customProperties`, `timeWindows`, …), but the API fills defaults for them — the minimal body below creates successfully without them.

**Minimal valid create body** (verified against the CLI acceptance test):

```json
{
  "name": "My flow",
  "type": "CONTACT_FLOW",
  "flowType": "WORKFLOW",
  "isEnabled": false,
  "objectTypeId": "0-1",
  "actions": []
}
```

See `resources/example-contact-flow.json`.

---

## `actions` — a graph, not an ordered list

`actions` is a **flat array of action objects wired into a graph**, not a sequential to-do list. Execution begins at `startActionId` and follows each action's `connection` to the next:

- Every action has a string **`actionId`**, unique within the flow.
- Most actions carry a **`connection`** to the next action:

  ```json
  "connection": { "edgeType": "STANDARD", "nextActionId": "2" }
  ```

  `edgeType` is `STANDARD` (continue to the next action) or `GOTO` (jump to an action defined elsewhere in the graph). `nextActionId` is the `actionId` to run next.
- An action with no `connection` is terminal — the path ends there.

Array position does not define order; the `connection` / `nextActionId` edges do.

### `SINGLE_CONNECTION` — a standard step

The common action shape: do one thing, then continue to one next action.

```json
{
  "actionId": "2",
  "type": "SINGLE_CONNECTION",
  "actionTypeId": "<copy-from-a-real-get>",
  "actionTypeVersion": 1,
  "fields": {},
  "connection": { "edgeType": "STANDARD", "nextActionId": "3" }
}
```

`actionTypeId` + `actionTypeVersion` + `fields` are what make a step a "set property", "create task", "send email", and so on. Their exact values vary per action type and version — **copy them from a real `hubspot workflows get`** rather than guessing. Omit `connection` on the final step.

### `LIST_BRANCH` — branch on a condition

Forks the path on filter criteria. Each branch carries its own `connection` to whatever action it continues to:

```json
{
  "actionId": "1",
  "type": "LIST_BRANCH",
  "listBranches": [
    {
      "branchName": "Connected leads",
      "connection": { "edgeType": "STANDARD", "nextActionId": "2" },
      "filterBranch": {
        "filterBranchType": "OR",
        "filterBranchOperator": "OR",
        "filterBranches": [],
        "filters": []
      }
    }
  ],
  "defaultBranchName": "Everyone else",
  "defaultBranch": { "edgeType": "STANDARD", "nextActionId": "2" }
}
```

- `listBranches[]` — one entry per condition; each has its own `connection` and `filterBranch`. The `filterBranch.filters[]` array holds the property conditions — copy those from a real `get`.
- `defaultBranch` — the fall-through `connection` for records matching no branch.
- A record travels **exactly one** branch.

(Other branch action types exist, such as `AB_TEST_BRANCH`; `get` a real one to see its shape.)

### Branching and convergence

Because branches connect to downstream actions by `nextActionId`, **multiple branches can converge on the same action** — just point their `connection.nextActionId` at the same `actionId`. In the snippet above, the matching branch and `defaultBranch` both target action `"2"`, so both paths continue to one shared step. There is no duplication and no double-execution: the record runs `"2"` once, on whichever path it took. An `edgeType: "GOTO"` connection lets a branch jump to an action defined earlier in the graph (e.g. to rejoin a shared tail). See `resources/example-branching-flow.json`.

---

## `enrollmentCriteria`

Controls which records enter the flow. It is **typed** — a `type` discriminator selects the shape. The common one is `LIST_BASED` (enroll records matching a filter):

```json
"enrollmentCriteria": {
  "type": "LIST_BASED",
  "listFilterBranch": {
    "filterBranchType": "OR",
    "filterBranchOperator": "OR",
    "filterBranches": [],
    "filters": []
  },
  "shouldReEnroll": false,
  "unEnrollObjectsNotMeetingCriteria": false,
  "reEnrollmentTriggersFilterBranches": []
}
```

The other `type` values are `EVENT_BASED`, `MANUAL`, and `DATASET`. As with actions, copy a real `enrollmentCriteria` from `hubspot workflows get` to get the exact filter shape.

## Filter branches

Both branch conditions and list-based enrollment use a **filter branch** object: `filterBranchType` (`OR` / `AND` / …), `filterBranchOperator`, a nested `filterBranches[]` array, and a `filters[]` array of property conditions. The exact `filters[]` item shape (property name, operator, values) is best taken verbatim from a real flow.

## `suppressionListIds`

An array of HubSpot list IDs. Records on any of these lists will not enroll even if they match `enrollmentCriteria`. Use `[]` if none are needed.

---

## Update — full PUT, get-modify-put round-trip

Update is a **full replace**, not a patch:

- Include `revisionId` (from `get`) — the API uses it for optimistic concurrency.
- Read-only fields (`createdAt`, `updatedAt`, `dataSources`) are stripped automatically by the CLI.
- `crmObjectCreationStatus` must read `COMPLETE` before a PUT is accepted; right after create it may still be provisioning, so re-`get` until it does.

**Pitfall — partial bodies silently drop fields.** Because update is a full PUT, sending only an `actions` array without `enrollmentCriteria` clears the enrollment trigger entirely — no error, no warning. Always start from the full `get` response.
