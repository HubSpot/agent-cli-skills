# Lifecycle Stage Progression Reference

HubSpot contacts move through lifecycle stages in a defined order. Each stage has a specific internal API value used in filters and updates.

## Stage Order and Meanings

| Stage | API Value | Meaning | Transition Trigger |
|---|---|---|---|
| Subscriber | `subscriber` | Opted into content but not yet engaged as a lead | Form fill, newsletter signup, list import |
| Lead | `lead` | Showed interest; any conversion event | Content download, webinar registration, any form fill |
| Marketing Qualified Lead | `marketingqualifiedlead` | Marketing has scored or flagged as ready for sales attention | Lead score threshold reached, behavior trigger, manual MQL flag |
| Sales Qualified Lead | `salesqualifiedlead` | Sales rep has accepted and is actively working the lead | Sales rep qualification call, deal created and associated |
| Opportunity | `opportunity` | Active deal in the pipeline | Deal created and associated to contact (often set automatically) |
| Customer | `customer` | Closed-won deal exists | Deal marked closed-won (often set automatically) |
| Evangelist | `evangelist` | Active promoter of the product | Manual, post-purchase relationship |
| Other | `other` | Doesn't fit any standard stage | Manual assignment |

## Important: Forward-Only Enforcement

HubSpot enforces forward-only progression for most stages. Attempting to move a contact **backward** (e.g., from `customer` to `lead`) may be blocked depending on your portal settings. Always move contacts **forward** through the funnel.

## CLI Commands to Transition Between Stages

### Move a contact to MQL

```bash
hubspot objects update --type contacts <contact_id> \
  --property lifecyclestage=marketingqualifiedlead
```

### Move a contact to SQL (typically done after deal creation)

```bash
hubspot objects update --type contacts <contact_id> \
  --property lifecyclestage=salesqualifiedlead \
  --property hs_lead_status=OPEN_DEAL
```

### Move a contact to Opportunity

```bash
hubspot objects update --type contacts <contact_id> \
  --property lifecyclestage=opportunity
```

### Mark a contact as Customer

```bash
hubspot objects update --type contacts <contact_id> \
  --property lifecyclestage=customer
```

### Find all contacts at a given stage

```bash
# Find all MQLs
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead" \
  --properties email,firstname,lastname,hubspot_owner_id,hs_lead_status

# Find all SQLs
hubspot objects search --type contacts \
  --filter "lifecyclestage=salesqualifiedlead" \
  --properties email,firstname,lastname,hubspot_owner_id,hs_lead_status

# Find MQLs with no deal yet
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND num_associated_deals=0" \
  --properties email,firstname,lastname,hs_lead_status
```

## Automatic Stage Updates

HubSpot may update `lifecyclestage` automatically in some cases:
- A contact becomes `opportunity` when an associated deal enters an active stage
- A contact becomes `customer` when an associated deal is marked closed-won

Do not rely on automatic updates during scripted workflows — set the stage explicitly to ensure consistency.
