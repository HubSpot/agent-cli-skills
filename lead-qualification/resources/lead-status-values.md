# Lead Status Values Reference

`hs_lead_status` is a contact property that tracks where a lead is in the sales outreach process. It is a freeform enumeration — values are set manually by reps or automation.

## Enum Values

| Value | Meaning | When to Set |
|---|---|---|
| `NEW` | Fresh lead, not yet worked by sales | On lead creation, import, or when no rep has touched the record |
| `OPEN` | Rep has taken ownership but not yet reached out | Rep accepts the lead; first CRM activity logged |
| `IN_PROGRESS` | Active outreach is underway | First contact attempt made (call, email, LinkedIn) |
| `OPEN_DEAL` | A deal exists and is associated to this contact | When a deal is created and associated — set this alongside `lifecyclestage=salesqualifiedlead` |
| `UNQUALIFIED` | Lead is not a fit for the product or offer | After qualification call or review determines no fit |
| `ATTEMPTED_TO_CONTACT` | Outreach was sent but no response received | After voicemail, email, or message with no reply |
| `CONNECTED` | Two-way contact was made | First live conversation or email reply from the prospect |
| `BAD_TIMING` | Lead is a good fit but not ready to buy now | Expressed interest but asked to follow up later |

## CLI Commands

### Set lead status on a single contact

```bash
# Mark as in-progress when outreach begins
hubspot objects update --type contacts <contact_id> \
  --property hs_lead_status=IN_PROGRESS

# Mark as connected after first conversation
hubspot objects update --type contacts <contact_id> \
  --property hs_lead_status=CONNECTED

# Disqualify a lead
hubspot objects update --type contacts <contact_id> \
  --property hs_lead_status=UNQUALIFIED

# Mark deal created
hubspot objects update --type contacts <contact_id> \
  --property hs_lead_status=OPEN_DEAL \
  --property lifecyclestage=salesqualifiedlead
```

### Filter contacts by lead status

```bash
# All NEW leads (no rep has touched them)
hubspot objects search --type contacts \
  --filter "hs_lead_status=NEW" \
  --properties email,firstname,lastname,hubspot_owner_id,lifecyclestage

# Leads where contact was attempted but no response
hubspot objects search --type contacts \
  --filter "hs_lead_status=ATTEMPTED_TO_CONTACT" \
  --properties email,firstname,lastname,hubspot_owner_id

# Connected leads without a deal (ready to qualify)
hubspot objects search --type contacts \
  --filter "hs_lead_status=CONNECTED AND num_associated_deals=0" \
  --properties email,firstname,lastname,company,hubspot_owner_id

# MQLs that are connected or in-progress (qualification candidates)
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND hs_lead_status=CONNECTED" \
  --properties email,firstname,lastname,company,hubspot_owner_id

# All unqualified leads (for reporting)
hubspot objects search --type contacts \
  --filter "hs_lead_status=UNQUALIFIED" \
  --properties email,firstname,lastname,hubspot_owner_id,lifecyclestage
```

### Combined lifecycle + lead status filter for SQL candidates

```bash
# Contacts ready for deal creation: MQL + connected, no deal yet
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND hs_lead_status=CONNECTED AND num_associated_deals=0" \
  --properties email,firstname,lastname,company,hubspot_owner_id
```
