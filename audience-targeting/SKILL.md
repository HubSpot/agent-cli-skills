---
name: audience-targeting
description: Build targeted contact segments for campaigns by filtering on lifecycle stage, engagement, firmographics, and geography, then exporting results as JSONL.
triggers:
  - "segment contacts"
  - "target audience"
  - "find prospects"
  - "filter contacts by industry"
  - "export contact list"
  - "build audience"
  - "contact segmentation"
  - "find contacts in"
---

## Resources

| File | When to use |
|---|---|
| `resources/contact-segmentation-filters.md` | Ready-to-run filter expressions organized by use case: lifecycle stage, lead status, email engagement, activity recency, deal association, and OR group examples |
| `resources/industry-values.md` | Complete `industry` enum value list for Company objects, plus the two-step pattern for targeting contacts by their associated company's industry |

## Context
Precise audience targeting starts with accurate segmentation. This skill covers filtering contacts and companies on behavioral, demographic, and firmographic properties, composing OR and AND logic, and exporting results for use in campaigns or downstream tools. Note that industry lives on Company objects, so cross-object targeting requires two steps.

## Property Reference — Contacts

| Property | Type | Notes |
|---|---|---|
| lifecyclestage | enumeration | subscriber, lead, marketingqualifiedlead, salesqualifiedlead, opportunity, customer, evangelist, other |
| hs_persona | enumeration | Portal-specific — check `hubspot properties list --object contacts` for valid values |
| jobtitle | string | |
| city | string | |
| state | string | |
| country | string | |
| hs_language | string | ISO language code |
| hs_email_optout | boolean | true if opted out of all marketing email |
| hs_email_last_open_date | datetime | Last marketing email open — format YYYY-MM-DD for filters |
| num_associated_deals | number | Read-only |

## Property Reference — Companies

| Property | Type | Notes |
|---|---|---|
| industry | enumeration | See `resources/industry-values.md` for all 36 values |
| numberofemployees | number | |
| annualrevenue | number | |
| type | enumeration | PROSPECT, PARTNER, RESELLER, VENDOR, OTHER |
| city | string | |
| country | string | |

## Key Workflows

### Find Leads in a Specific Lifecycle Stage

```bash
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead" \
  --properties email,firstname,lastname,lifecyclestage
```

### Combine Conditions with AND

```bash
# MQLs that are not yet owned by anyone
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND !hubspot_owner_id" \
  --properties email,firstname,lastname
```

### OR Logic with Multiple --filter Flags

Each `--filter` flag is a separate OR group. Records matching any group are returned.

```bash
# Contacts in tech OR software companies (CONTAINS_TOKEN)
hubspot objects search --type contacts \
  --filter "company~tech" \
  --filter "company~software" \
  --properties email,company

# Contacts who are leads OR MQLs
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead" \
  --filter "lifecyclestage=marketingqualifiedlead" \
  --properties email,lifecyclestage
```

### Find Unengaged Contacts (No Recent Email Open)

```bash
hubspot objects search --type contacts \
  --filter "hs_email_last_open_date<2024-01-01" \
  --properties email,firstname,hs_email_last_open_date
```

### Find Opted-In Contacts Only

```bash
# Contacts who have NOT opted out
hubspot objects search --type contacts \
  --filter "hs_email_optout!=true" \
  --properties email,firstname,lastname
```

### Export a Targeted List to File

```bash
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead" \
  --properties email,firstname,lastname,jobtitle \
  > leads.jsonl

# Convert to CSV (example using jq — agent can construct CSV directly from the JSONL)
cat leads.jsonl | jq -r '[.properties.email, .properties.firstname, .properties.lastname, .properties.jobtitle] | @csv'
```

### Target by Company Size — Two-Step Cross-Object Query

Industry and company size live on Company objects, not Contact objects. To target contacts at large companies:

```bash
# Step 1: find matching companies
hubspot objects search --type companies \
  --filter "numberofemployees>=500" \
  > large_companies.jsonl

# Step 2: get associated contacts for each company
cat large_companies.jsonl \
| jq -r '.id' \
| xargs -I{} hubspot associations list --from companies:{} --to contacts --format jsonl \
> target_contacts.jsonl
```

### Target by Industry (Two-Step)

```bash
# Step 1: find companies in target industries
hubspot objects search --type companies \
  --filter "industry=INFORMATION_TECHNOLOGY" \
  --filter "industry=SOFTWARE" \
  > tech_companies.jsonl

# Step 2: get their contacts
cat tech_companies.jsonl \
| jq -r '.id' \
| xargs -I{} hubspot associations list --from companies:{} --to contacts --format jsonl
```

### Combined Cross-Object Targeting for Email Campaigns

Industry and employee count live on Company objects. To build a contact audience from firmographic criteria, always query companies first then traverse to contacts, then filter out opted-out contacts.

```bash
# Step 1: find matching companies (industry + size)
hubspot objects search --type companies \
  --filter "industry=INFORMATION_TECHNOLOGY AND numberofemployees>=500" \
  --filter "industry=SOFTWARE AND numberofemployees>=500" \
  --properties name,industry,numberofemployees \
  > target_companies.jsonl

# Step 2: collect contacts from those companies via association traversal
cat target_companies.jsonl \
| jq -r '.id' \
| xargs -I{} hubspot associations list --from companies:{} --to contacts --format jsonl \
| jq -r '.id' \
| sort -u \
> candidate_contact_ids.txt

# Step 3: fetch contact records and exclude opted-out contacts
# (run per contact ID or re-query with the owner/lifecycle filters you need)
hubspot objects search --type contacts \
  --filter "hs_email_optout!=true" \
  --properties email,firstname,lastname,lifecyclestage
```

For the full list of `industry` enum values (e.g., `INFORMATION_TECHNOLOGY`, `SOFTWARE`, `FINANCIAL_SERVICES`), see `resources/industry-values.md`.

### Filter by Location

```bash
# Contacts in a specific country
hubspot objects search --type contacts \
  --filter "country=United States" \
  --properties email,firstname,state,city

# Companies in a specific city
hubspot objects search --type companies \
  --filter "city=San Francisco" \
  --properties name,industry,numberofemployees
```

## Known Limitations
- No Lists API in the CLI. You cannot save a search as a HubSpot list or use list membership as a filter condition. Use the HubSpot UI to create and manage lists.
- Industry lives on Company objects, not Contact objects. Cross-object targeting always requires a two-step query (companies → associations → contacts).
- For > 100 results, use the pagination loop from the `bulk-operations` skill.
- OR logic requires separate `--filter` flags — one condition group per flag. You cannot use OR inside a single `--filter` expression.
- The `~` (CONTAINS_TOKEN) operator matches whole words/tokens, not arbitrary substrings.
- `hs_email_optout` filter values: use `!=true` to find opted-in contacts, or `=true` to find opted-out contacts.
