# Contact Segmentation Filters Reference

All examples use `hubspot objects search --type contacts`. Add `--properties` flags to control
which fields are returned. Results are JSONL by default.

---

## By Lifecycle Stage

Each stage is an exact-match enum value (lowercase).

```bash
# Subscribers
--filter "lifecyclestage=subscriber"

# Leads
--filter "lifecyclestage=lead"

# Marketing Qualified Leads
--filter "lifecyclestage=marketingqualifiedlead"

# Sales Qualified Leads
--filter "lifecyclestage=salesqualifiedlead"

# Opportunities
--filter "lifecyclestage=opportunity"

# Customers
--filter "lifecyclestage=customer"

# Evangelists
--filter "lifecyclestage=evangelist"

# Other
--filter "lifecyclestage=other"
```

---

## By Lead Status

Lead status is set on contacts with `lifecyclestage=lead` or further along the funnel.

```bash
--filter "hs_lead_status=NEW"
--filter "hs_lead_status=OPEN"
--filter "hs_lead_status=IN_PROGRESS"
--filter "hs_lead_status=OPEN_DEAL"
--filter "hs_lead_status=UNQUALIFIED"
--filter "hs_lead_status=ATTEMPTED_TO_CONTACT"
--filter "hs_lead_status=CONNECTED"
--filter "hs_lead_status=BAD_TIMING"

# Combine with lifecycle stage
--filter "lifecyclestage=lead AND hs_lead_status=NEW"
```

---

## By Email Engagement

```bash
# Contacts who have opened any marketing email (field is present)
--filter "hs_email_last_open_date"

# Contacts who have never opened a marketing email (field is absent)
--filter "!hs_email_last_open_date"

# Contacts who opened an email after a specific date
--filter "hs_email_last_open_date>2024-01-01"

# Contacts who have NOT opened email since a date (unengaged)
--filter "hs_email_last_open_date<2024-01-01"

# Bounced contacts (hard bounce on file)
--filter "hs_email_bounce=true"

# Opted out of all marketing email
--filter "hs_email_optout=true"

# Opted in (have NOT opted out) — preferred for campaign targeting
--filter "hs_email_optout!=true"

# Email was sent but never opened (received email, low engagement)
--filter "hs_email_last_send_date AND !hs_email_last_open_date"
```

---

## By Activity Recency

Dates use `YYYY-MM-DD` format in filter expressions.

```bash
# Contacted within the last 30 days (substitute today's date minus 30)
--filter "notes_last_contacted>2024-11-01"

# Not contacted in the last 90 days (stale contacts)
--filter "notes_last_contacted<2024-09-01"

# Never contacted (field is absent)
--filter "!notes_last_contacted"

# Last sales activity within 14 days
--filter "hs_last_sales_activity_date>2024-11-17"

# No sales activity ever
--filter "!hs_last_sales_activity_date"
```

---

## By Deal Association

```bash
# Has at least one associated deal
--filter "num_associated_deals>=1"

# Has no deals (net-new prospect, no active pipeline)
--filter "num_associated_deals=0"

# Has multiple deals (expansion / upsell candidates)
--filter "num_associated_deals>=2"
```

---

## By Owner

```bash
# Assigned to a specific owner (use hubspot owners list to get ID)
--filter "hubspot_owner_id=12345"

# Unassigned (no owner)
--filter "!hubspot_owner_id"

# Has any owner (owned records)
--filter "hubspot_owner_id"
```

---

## Combining Multiple Conditions (AND)

Put all AND conditions inside a single `--filter` flag, separated by ` AND `.

```bash
# MQLs with no owner and no deals (unworked leads)
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND !hubspot_owner_id AND num_associated_deals=0" \
  --properties email,firstname,lastname

# Opted-in leads in a specific country not contacted in 60 days
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead AND country=United States AND hs_email_optout!=true AND notes_last_contacted<2024-10-01" \
  --properties email,firstname,lastname,notes_last_contacted

# SQLs with an open deal and a sales activity this month
hubspot objects search --type contacts \
  --filter "lifecyclestage=salesqualifiedlead AND num_associated_deals>=1 AND hs_last_sales_activity_date>2024-11-01" \
  --properties email,firstname,lastname

# Customers who have opened recent email (re-engagement candidates)
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_email_last_open_date>2024-10-01 AND hs_email_optout!=true" \
  --properties email,firstname,lastname
```

---

## OR Between Groups (Multiple --filter Flags)

Each `--filter` flag is an independent OR group. Records matching **any** group are returned.

```bash
# Leads OR MQLs (top of funnel)
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead" \
  --filter "lifecyclestage=marketingqualifiedlead" \
  --properties email,lifecyclestage

# Contacts in any active sales status
hubspot objects search --type contacts \
  --filter "hs_lead_status=IN_PROGRESS" \
  --filter "hs_lead_status=OPEN" \
  --filter "hs_lead_status=CONNECTED" \
  --properties email,firstname,hs_lead_status

# Contacts who recently opened email OR were recently contacted by sales
hubspot objects search --type contacts \
  --filter "hs_email_last_open_date>2024-11-01" \
  --filter "notes_last_contacted>2024-11-01" \
  --properties email,firstname,lastname

# Never contacted leads OR subscribers (nurture re-entry)
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead AND !notes_last_contacted" \
  --filter "lifecyclestage=subscriber AND !notes_last_contacted" \
  --properties email,firstname,lastname
```

---

## Full Command Examples

```bash
# Export opted-in leads to a file for a campaign
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead AND hs_email_optout!=true" \
  --properties email,firstname,lastname,jobtitle \
  > campaign_leads.jsonl

# Convert to CSV
cat campaign_leads.jsonl \
| jq -r '[.properties.email, .properties.firstname, .properties.lastname, .properties.jobtitle] | @csv'

# Count unengaged MQLs
hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead AND !hs_email_last_open_date" \
| wc -l

# Dry-run advancing stale leads to MQL
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead AND notes_last_contacted<2024-09-01 AND num_associated_deals=0" \
| jq -c '{id, properties: {lifecyclestage: "marketingqualifiedlead"}}' \
| hubspot objects update --type contacts --dry-run
```
