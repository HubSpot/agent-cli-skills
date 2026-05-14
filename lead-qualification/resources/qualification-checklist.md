# Lead Qualification Checklist

Use this checklist to determine whether a contact is ready to be promoted from MQL to SQL. Each criterion includes the CLI command to check it and, where applicable, the property to update when it is confirmed.

---

## 1. Lifecycle stage is MQL

**Why:** Only contacts at the MQL stage should be going through qualification. Earlier-stage contacts need more marketing nurturing first.

```bash
# Check a single contact's lifecycle stage
hubspot objects get --type contacts <contact_id> \
  --properties lifecyclestage,hs_lead_status

# Find all MQLs (your starting pool)
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead" \
  --properties email,firstname,lastname,hs_lead_status,num_associated_deals
```

**Update when confirmed:** Do not change this yet — update to `salesqualifiedlead` only after all criteria are met.

---

## 2. Lead status is CONNECTED or IN_PROGRESS

**Why:** A rep must have made contact before a lead can be qualified. Contacts still at `NEW`, `OPEN`, or `ATTEMPTED_TO_CONTACT` have not been engaged yet.

```bash
# Check lead status
hubspot objects get --type contacts <contact_id> \
  --properties hs_lead_status

# Find MQLs that are ready (connected or in-progress)
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND hs_lead_status=CONNECTED" \
  --properties email,firstname,lastname,company,hubspot_owner_id
```

**Update when confirmed:** No change at this step. `hs_lead_status=CONNECTED` should already be set by the rep.

---

## 3. Has a valid email address

**Why:** Contacts imported with placeholder emails or no email cannot receive follow-up communications.

```bash
# Find MQLs missing email or with placeholder email
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND !email" \
  --properties firstname,lastname,company

# Exclude known placeholder pattern
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead" \
  --properties email,firstname,lastname \
| jq -c 'select((.properties.email // "") | test("unknown@|noemail@|placeholder"; "i") | not)'
```

**Update when confirmed:** No action needed — absence of a valid email is a disqualifier.

---

## 4. Has a company association

**Why:** Deals should be associated to both a contact and a company. If no company is associated, the deal will be an orphan with no account context.

```bash
# Check company associations for a specific contact
hubspot associations list --from contacts:<contact_id> --to companies --format jsonl

# Check num_associated_companies property (faster for bulk)
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND num_associated_companies=0" \
  --properties email,firstname,lastname,company
```

**Update when confirmed:** If a company record exists but is not associated, create the association:

```bash
hubspot associations create --from contacts:<contact_id> --to companies:<company_id>
```

---

## 5. No existing open deal

**Why:** Creating a duplicate deal for a contact that already has one active will split the pipeline and create confusion for the rep.

```bash
# Check num_associated_deals
hubspot objects get --type contacts <contact_id> \
  --properties num_associated_deals

# Find MQLs with no deal (clean qualification candidates)
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND num_associated_deals=0" \
  --properties email,firstname,lastname,hs_lead_status

# Find existing deals associated to a contact
hubspot associations list --from contacts:<contact_id> --to deals --format jsonl
```

**Update when confirmed:** If there is already an open deal, skip deal creation and update the contact lifecycle instead:

```bash
hubspot objects update --type contacts <contact_id> \
  --property lifecyclestage=salesqualifiedlead \
  --property hs_lead_status=OPEN_DEAL
```

---

## 6. Rep (owner) is assigned

**Why:** Deals and contacts without an owner will not appear in rep dashboards or be followed up on.

```bash
# Check if a contact has an owner
hubspot objects get --type contacts <contact_id> \
  --properties hubspot_owner_id

# List all available owner IDs and emails
hubspot owners list --format table

# Find a specific rep's owner ID
hubspot owners list --format jsonl \
  | jq -r 'select(.email == "rep@company.com") | .id'
```

**Update when confirmed:** Assign an owner if missing:

```bash
hubspot objects update --type contacts <contact_id> \
  --property hubspot_owner_id=<owner_id>
```

---

## Final Step: Promote to SQL

Once all criteria above are confirmed, follow the full deal creation and lifecycle promotion sequence in `SKILL.md` → "Full MQL to SQL Qualification Pipeline".
