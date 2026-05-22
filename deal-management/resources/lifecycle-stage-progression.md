# Lifecycle Stage Progression

`lifecyclestage` is a contact property — these API values are HubSpot defaults (semantic, portal-independent, unlike deal stage IDs). Use these in `--filter` and `--property` exactly.

| Stage | API Value | Transition Trigger |
|---|---|---|
| Subscriber | `subscriber` | Opted in (newsletter, content) but not yet engaged |
| Lead | `lead` | Any conversion event (form fill, content download) |
| Marketing Qualified Lead | `marketingqualifiedlead` | Lead score / manual MQL flag |
| Sales Qualified Lead | `salesqualifiedlead` | Sales rep accepted; deal usually created here |
| Opportunity | `opportunity` | Active deal in pipeline (often auto-set when a deal associates) |
| Customer | `customer` | Closed-won deal exists (often auto-set) |
| Evangelist | `evangelist` | Post-purchase advocate (manual) |
| Other | `other` | Doesn't fit standard stages (manual) |

## Forward-only enforcement

HubSpot blocks backward transitions (e.g. `customer` → `lead`) in most portal settings. Always move forward.

## CLI updates that pair with deal moves

```bash
# Promote MQL → SQL when creating a deal
hubspot objects update --type contacts <id> \
  --property lifecyclestage=salesqualifiedlead \
  --property hs_lead_status=OPEN_DEAL

# Promote to opportunity (often automatic on deal-stage advance)
hubspot objects update --type contacts <id> --property lifecyclestage=opportunity

# Mark as customer (often automatic on closedwon)
hubspot objects update --type contacts <id> --property lifecyclestage=customer
```

HubSpot may auto-update `lifecyclestage` when a deal associates or closes — but don't rely on that in scripts. Set it explicitly.

## `hs_lead_status` quick reference

`hs_lead_status` is the sales outreach state, independent of lifecycle stage. Common values: `NEW`, `OPEN`, `IN_PROGRESS`, `CONNECTED`, `OPEN_DEAL`, `UNQUALIFIED`, `ATTEMPTED_TO_CONTACT`, `BAD_TIMING`. Pair `OPEN_DEAL` with `salesqualifiedlead` when creating a deal; pair `UNQUALIFIED` with a disqualification (no lifecycle change).

For the live list of allowed values in this portal: `hubspot properties list --type contacts --format jsonl | jq 'select(.name=="hs_lead_status")'`.

## Qualification filter checklist

To find MQLs ready for deal creation, combine these in one filter:

```bash
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead \
            AND hs_lead_status=CONNECTED \
            AND num_associated_deals=0 \
            AND num_associated_companies>0 \
            AND email \
            AND hubspot_owner_id" \
  --properties email,firstname,lastname,company,hubspot_owner_id
```

Each criterion (has email, has a company, no open deal, has an owner) is just a filter clause — no separate tooling needed.
