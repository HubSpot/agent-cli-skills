# Lifecycle Stage Reference

`lifecyclestage` is a contact property. These API values are HubSpot's default stages — they're stable across portals (unlike deal-pipeline stage IDs), so you can hard-code them in filters. Portals may add custom stages; verify with `hubspot properties get --type contacts lifecyclestage` if uncertain.

| Stage | API Value |
|---|---|
| Subscriber | `subscriber` |
| Lead | `lead` |
| Marketing Qualified Lead | `marketingqualifiedlead` |
| Sales Qualified Lead | `salesqualifiedlead` |
| Opportunity | `opportunity` |
| Customer | `customer` |
| Evangelist | `evangelist` |
| Other | `other` |

**What triggers each transition is team-specific.** HubSpot doesn't prescribe a universal definition of when a Lead becomes an MQL, or when an SQL becomes an Opportunity — that's set by each team's qualification criteria, lead-scoring model, or manual handoff process. Ask the user before encoding transition logic.

## Forward progression (portal setting)

Portals can enable a "Customer lifecycle stages" setting that prevents moving a contact to an earlier stage (e.g. `customer` → `lead`). This is **not** on by default in every portal — check the portal's settings or test on a sandbox record before assuming. When the setting is on, write attempts to move backward are rejected.

## CLI updates

```bash
# Set lifecycle stage explicitly
hubspot objects update --type contacts <id> \
  --property lifecyclestage=salesqualifiedlead

# Pair with hs_lead_status when relevant (see below)
hubspot objects update --type contacts <id> \
  --property lifecyclestage=salesqualifiedlead \
  --property hs_lead_status=OPEN_DEAL
```

HubSpot has automation features that can auto-update `lifecyclestage` (e.g. when a deal associates or closes-won), but whether these are enabled depends on portal configuration. If your script needs a specific stage, set it explicitly rather than relying on automation.

## `hs_lead_status` reference

`hs_lead_status` is the sales-outreach state, independent of lifecycle stage. The enum is portal-customizable. Common default values:

- `NEW`
- `OPEN`
- `IN_PROGRESS`
- `CONNECTED`
- `OPEN_DEAL`
- `UNQUALIFIED`
- `ATTEMPTED_TO_CONTACT`
- `BAD_TIMING`

For the live list of allowed values in this portal:

```bash
hubspot properties list --type contacts --format jsonl \
  | jq 'select(.name=="hs_lead_status")'
```

Which `hs_lead_status` value pairs with which `lifecyclestage` is team-defined — there's no HubSpot-prescribed pairing. Ask the user how their reps use these together if you need to encode it.

## Example: filter by stage + status

The criteria for "ready to convert" or "ready for deal creation" are team-specific. Below is the *shape* of such a query — the actual filter clauses (which status, whether a company association is required, whether an owner must be assigned) should come from the caller's qualification definition.

```bash
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND hs_lead_status=CONNECTED" \
  --properties email,firstname,lastname,company,hubspot_owner_id
```

Each additional criterion (`AND email`, `AND num_associated_companies>0`, `AND hubspot_owner_id`, `AND num_associated_deals=0`) is a filter clause you can add — but only if the user's definition of "qualified" requires it.
