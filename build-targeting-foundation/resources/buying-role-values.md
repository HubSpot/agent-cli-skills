# hs_buying_role enum values

Standard HubSpot enum options for the `hs_buying_role` contact property. Always confirm the live set in the portal before use:

```bash
hubspot properties get --type contacts hs_buying_role
# or discover live values:
hubspot objects list --type contacts --properties hs_buying_role --limit 100 --format json \
  | jq -r '.data[].properties.hs_buying_role // empty' | sort -u
```

## Standard values

| Value | Description |
|---|---|
| `BLOCKER` | Opposed to or able to veto the purchase |
| `BUDGET_HOLDER` | Controls or owns the budget for this purchase |
| `CHAMPION` | Advocates internally for your solution |
| `DECISION_MAKER` | Final authority on the purchase decision |
| `END_USER` | Will use the product day-to-day |
| `EVALUATOR` | Evaluates and scores vendors/solutions |
| `EXECUTIVE_SPONSOR` | Executive-level sponsor; may not be hands-on |
| `INFLUENCER` | Shapes the opinion of decision makers without final authority |
| `LEGAL_AND_COMPLIANCE` | Reviews contracts, security, or compliance requirements |
| `OTHER` | Does not fit another category |

## Notes

- These are HubSpot's default enum values. Portals can add custom values — discover them at runtime.
- A contact can hold only one `hs_buying_role` value (single enum). For multi-role modeling, use multiple contacts or a custom multi-select property.
- The Target Accounts sidebar in the HubSpot UI groups contacts associated to a target-account company and displays `hs_buying_role` as the "buyer role" column.
- Contacts with no `hs_buying_role` appear as unassigned in the buyer group view.

## Common patterns

```bash
# Set decision maker role (single contact)
hubspot objects update --type contacts <contact_id> --properties hs_buying_role=DECISION_MAKER

# Assign champion role to a list of contacts (dry-run first)
jq -c '{id, properties:{hs_buying_role:"CHAMPION"}}' /tmp/champions.jsonl \
  | hubspot objects update --type contacts --dry-run

# Find all contacts with a specific role at target-account companies
hubspot objects search --type contacts \
  --filter "hs_buying_role=DECISION_MAKER" \
  --properties email,firstname,lastname,company,hs_buying_role
```
