---
name: build-targeting-foundation
description: Identify target accounts, build segments, and assign buyer roles for CUJ 6 / Build Pipeline targeting workflows. Use when an agent or user wants to select and mark companies as target accounts (hs_is_target_account=true), create or update CRM segments (lists) around those accounts, associate contacts to target-account companies, or assign contact buyer roles (hs_buying_role). Also triggers for "target account", "ICP fit", "buyer group", "buying role", "account segmentation", "build pipeline targeting", "identify target accounts", "who are our target accounts", "decision makers at target accounts", or "upload an account list".
triggers:
  - "target accounts"
  - "identify target accounts"
  - "mark as target account"
  - "ICP fit"
  - "buyer roles"
  - "buying role"
  - "buyer group"
  - "hs_is_target_account"
  - "hs_buying_role"
  - "account segmentation"
  - "build pipeline targeting"
  - "targeting foundation"
  - "target account list"
  - "account list upload"
  - "decision makers at target accounts"
---

## Resources

| File | When to use |
|---|---|
| `resources/buying-role-values.md` | Full enum options for `hs_buying_role` with descriptions — load before setting buyer roles. |

## Foundation

Read `bulk-operations/SKILL.md` first — JSONL piping, batch read, pagination, and the dry-run/digest/confirm safety flow all live there. For contact/company lookups and association traversal, see `crm-lookup/SKILL.md`. For contact segmentation by engagement or firmographics, see `audience-targeting/SKILL.md`.

**Related issues:** DPG2-386 (parent interaction), DPG2-93 (`hubspot crm segments` command group).

## CRM model

Target accounts and buyer roles use existing CRM primitives — no `target-accounts` or `buyer-groups` command groups are needed:

| Concept | CRM surface |
|---|---|
| Target account | Company property `hs_is_target_account=true` |
| Buyer role | Contact property `hs_buying_role` (enum) |
| Buyer group | Contacts associated to a target-account company with `hs_buying_role` set |
| Segment | CRM list via `hubspot crm segments` (DPG2-93) |

## Step 0 — Auth and portal context

Always confirm identity and portal before any mutation:

```bash
hubspot whoami
# → {"portalId":12345678,"portalName":"Acme Corp","environment":"PROD","email":"user@acme.com"}
```

Capture `portalId` — include it in all outputs and product URLs.

## Step 1 — Inspect properties

Property enum options are portal-specific. Discover them at runtime before setting values:

```bash
# Confirm hs_is_target_account exists and inspect its type
hubspot properties get --type companies hs_is_target_account

# Inspect hs_buying_role and its allowed values
hubspot properties get --type contacts hs_buying_role
```

If `hubspot properties get` does not return enum options, discover live values in the portal:

```bash
hubspot objects list --type contacts --properties hs_buying_role --limit 100 --format json \
  | jq -r '.data[].properties.hs_buying_role // empty' | sort -u
```

See `resources/buying-role-values.md` for the standard HubSpot enum values and their meaning.

## Step 2 — Define targeting inputs

Before searching, gather and confirm targeting criteria with the user. Do not invent the model — surface the criteria and ask for confirmation. Collect:

- **ICP fit criteria** — industry, company size (employees/revenue), geography, technology, or other firmographics
- **Past-win similarity** — closed-won company attributes to match
- **Engagement signals** — intent data, recent activity, or engagement scores
- **Exclusions** — existing customers (`lifecyclestage=customer`), competitors, partners, suppressed domains, or previously disqualified companies
- **Customer-provided list** — domain list, CSV of company IDs, or external account list
- **Required properties to return** — for human review before marking
- **Desired segment** — name, type (static/dynamic), filter definition or manual membership list
- **Buyer role assignments** — contact filter(s) and the role to assign

Confirm these inputs explicitly before proceeding to search or mutation.

## Step 3 — Search candidate companies

Run a read-only query first. Always show results for review before marking:

```bash
# ICP fit: SaaS companies 200-2000 employees, US only, not already a customer
hubspot objects search --type companies \
  --filter "industry=SOFTWARE AND numberofemployees>=200 AND numberofemployees<=2000 AND country=United States AND lifecyclestage!=customer" \
  --properties hs_object_id,name,domain,industry,numberofemployees,annualrevenue,hs_is_target_account,lifecyclestage

# From a customer-provided domain list
while read -r domain; do
  hubspot objects search --type companies --filter "domain=$domain" \
    --properties hs_object_id,name,domain,hs_is_target_account
done < account_list.txt > /tmp/candidates.jsonl

# Already-target-account check — to find what's already marked
hubspot objects search --type companies \
  --filter "hs_is_target_account=true" \
  --properties hs_object_id,name,domain > /tmp/existing_targets.jsonl
```

Save candidates to a file for review and the downstream steps:

```bash
hubspot objects search --type companies \
  --filter "<your criteria>" \
  --properties hs_object_id,name,domain,industry,numberofemployees,hs_is_target_account \
  > /tmp/candidates.jsonl

wc -l /tmp/candidates.jsonl  # show count before proceeding
jq -r '[.id, .properties.name, .properties.domain] | @tsv' /tmp/candidates.jsonl | head -20
```

**Stop here.** Show the candidate list to the user and ask for confirmation before marking any companies.

## Step 4 — Mark companies as target accounts

Require explicit user confirmation before this step. Use dry-run first:

```bash
# Preview — shows every company that would be updated
jq -c '{id, properties:{hs_is_target_account:"true"}}' /tmp/candidates.jsonl \
  | hubspot objects update --type companies --dry-run

# Apply after confirmation
jq -c '{id, properties:{hs_is_target_account:"true"}}' /tmp/candidates.jsonl \
  | hubspot objects update --type companies
```

For >100 companies, the dry-run emits a digest line — apply with `--digest <hash> --confirm <count>` per `bulk-operations/SKILL.md`.

Readback after marking:

```bash
jq -c '{id}' /tmp/candidates.jsonl \
  | hubspot objects get --type companies \
    --properties hs_object_id,name,domain,hs_is_target_account \
  | jq -c 'select(.properties.hs_is_target_account == "true")' \
  | tee /tmp/confirmed_targets.jsonl | wc -l
# Expected: count matches /tmp/candidates.jsonl
```

## Step 5 — Create or update segments

Segments (CRM lists) are managed via `hubspot crm segments` (DPG2-93). If that command group is available:

```bash
# Discover available segment commands
hubspot crm segments --help

# List existing segments (find one to update, or confirm name doesn't conflict)
hubspot crm segments list

# Create a dynamic segment filtered to target accounts in an industry
hubspot crm segments create \
  --name "Target Accounts - SaaS 200-2000 employees" \
  --type DYNAMIC \
  --filter "hs_is_target_account=true AND industry=SOFTWARE"

# Or create a static segment with the confirmed company IDs
hubspot crm segments create \
  --name "Target Accounts - Q3 2026" \
  --type STATIC \
  --members "$(jq -r '.id' /tmp/confirmed_targets.jsonl | paste -sd',')"
```

If `hubspot crm segments` is not yet available in the installed CLI version, document the segment definition as a filter expression for the user to create via the HubSpot UI, and include it in the output. Dry-run / preview output for segment changes where `--dry-run` is supported.

Readback:

```bash
hubspot crm segments list | jq -c 'select(.name | test("Target Accounts"; "i"))'
```

## Step 6 — Associate contacts to target-account companies

A buyer group is a set of contacts associated to a target-account company. Contacts may already be associated — check before creating:

```bash
# Find contacts not yet associated to a target company
company_id=<company_id>
hubspot associations list --from companies:$company_id --to contacts \
  | jq -c '{id}' \
  | hubspot objects get --type contacts \
    --properties email,firstname,lastname,jobtitle,hs_buying_role

# Associate a new contact to a target company (requires explicit confirmation)
hubspot associations create --from contacts:<contact_id> --to companies:<company_id>
```

For bulk association from a matched contact list:

```bash
# Pair matched contacts with their target companies, then associate in bulk
jq -c '{from:("contacts:"+.contact_id), to:("companies:"+.company_id)}' /tmp/contact_company_pairs.jsonl \
  | hubspot associations create --dry-run

# Apply after confirmation
jq -c '{from:("contacts:"+.contact_id), to:("companies:"+.company_id)}' /tmp/contact_company_pairs.jsonl \
  | hubspot associations create
```

## Step 7 — Set contact buyer roles

Load `resources/buying-role-values.md` before this step to pick the right enum value. Require explicit user confirmation before setting roles.

```bash
# Preview role assignments
jq -c '{id, properties:{hs_buying_role:"DECISION_MAKER"}}' /tmp/decision_makers.jsonl \
  | hubspot objects update --type contacts --dry-run

# Apply after confirmation
jq -c '{id, properties:{hs_buying_role:"DECISION_MAKER"}}' /tmp/decision_makers.jsonl \
  | hubspot objects update --type contacts
```

Multiple contacts in one pass — reshape from a file that records the intended role per contact:

```bash
# /tmp/role_assignments.jsonl format: {"id":"123","role":"CHAMPION"}
jq -c '{id, properties:{hs_buying_role:.role}}' /tmp/role_assignments.jsonl \
  | hubspot objects update --type contacts --dry-run
```

Readback:

```bash
jq -c '{id}' /tmp/role_assignments.jsonl \
  | hubspot objects get --type contacts \
    --properties email,firstname,lastname,hs_buying_role \
  | jq -c 'select(.properties.hs_buying_role != null and .properties.hs_buying_role != "")'
```

## Step 8 — Verify and produce output

Run readback commands before reporting completion. Emit a machine-readable summary:

```bash
# Full target account list with buyer groups
jq -r '.id' /tmp/confirmed_targets.jsonl | while read -r cid; do
  echo "--- Company: $cid"
  hubspot objects get --type companies $cid \
    --properties name,domain,hs_is_target_account
  hubspot associations list --from companies:$cid --to contacts \
    | jq -c '{id}' \
    | hubspot objects get --type contacts \
      --properties email,firstname,lastname,hs_buying_role
done
```

Product URLs for UI verification (replace `<portalId>` with the value from `hubspot whoami`):

```
Target Accounts view:  https://app.hubspot.com/contacts/<portalId>/target-accounts
CRM Contacts:          https://app.hubspot.com/contacts/<portalId>/contacts/list/view/all/
CRM Companies:         https://app.hubspot.com/contacts/<portalId>/companies/list/view/all/
Lists/Segments:        https://app.hubspot.com/contacts/<portalId>/lists/
```

## Standardized output

Always produce this summary before stopping:

```
Portal ID:              <portalId>
Environment:            PROD | QA
Candidate filter used:  <filter expression or "customer-provided list">
Companies marked:       <count> company IDs
Segment IDs/names:      <list or "none created">
Contacts associated:    <count> contact → company pairs
Buyer roles set:        <count> contacts, roles: <ROLE=count, ...>
Skipped records:        <count and reasons, or "none">
Verification commands:  <readback commands used>
Product URLs:           <links above>
Rollback guidance:      hubspot objects update --type companies --dry-run (set hs_is_target_account=false for marked IDs); hubspot history --since 1h for audit
```

## Safety rules

- Run readback commands before every mutation step.
- Require explicit user confirmation before: marking `hs_is_target_account=true`, changing segment definitions or membership, creating contact-company associations, and setting `hs_buying_role`.
- Always `--dry-run` first for bulk updates; show the preview count before asking to confirm.
- Use machine-readable output so another agent can continue the workflow.
- Do not invent ICP criteria or targeting models — surface candidates and ask.
- Do not create `target-accounts` or `buyer-groups` command groups; all operations go through `objects`, `properties`, `associations`, and `crm segments`.

## Known constraints

- `hubspot crm segments` availability depends on DPG2-93 landing — fall back to filter-expression documentation if the command is not available.
- `hubspot properties get` may not return enum option labels — discover live values with `objects list | jq` if needed.
- `associations list` has no batch `--from`. Loop to gather contact IDs across many companies, then batch the `objects get`.
- For >100 companies, pagination loop from `bulk-operations/SKILL.md` is required.
- `hs_is_target_account` and `hs_buying_role` are standard HubSpot properties but may be hidden or renamed in some portals — verify with `hubspot properties get` first.
