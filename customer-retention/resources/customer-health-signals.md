# Customer Health Signals

CRM properties and CLI filter expressions organized by churn risk tier. Run these queries to build a retention watchlist.

---

## Tier 1 — Strong Churn Signals (Check These First)

### Subscription past due or cancelled

```bash
# Past due subscriptions — revenue at immediate risk
hubspot objects search --type subscriptions \
  --filter "hs_subscription_status=PAST_DUE" \
  --properties hs_mrr,hs_arr,hs_subscription_status

# Cancelled subscriptions — candidates for win-back outreach
hubspot objects search --type subscriptions \
  --filter "hs_subscription_status=CANCELLED" \
  --properties hs_mrr,hs_subscription_status
```

**Property:** `hs_subscription_status`
**Values:** `ACTIVE` `CANCELLED` `PAST_DUE` `TRIALING`

---

### No outreach in 60+ days

`notes_last_contacted` is updated whenever a call, note, or meeting is logged and associated to the contact.

```bash
# macOS
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND notes_last_contacted<$(date -v-60d +%Y-%m-%d)" \
  --properties email,firstname,lastname,notes_last_contacted,hubspot_owner_id

# Linux
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND notes_last_contacted<$(date -d '60 days ago' +%Y-%m-%d)" \
  --properties email,firstname,lastname,notes_last_contacted,hubspot_owner_id

# Customers who have NEVER been contacted
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND !notes_last_contacted" \
  --properties email,firstname,lastname,hubspot_owner_id
```

**Property:** `notes_last_contacted` (datetime)

---

### High-priority open tickets older than 7 days

Requires knowing your ticket pipeline stage ID for open/in-progress stages.

```bash
# macOS
hubspot objects search --type tickets \
  --filter "hs_ticket_priority=URGENT AND createdate<$(date -v-7d +%Y-%m-%d)" \
  --properties subject,hs_ticket_priority,createdate,hubspot_owner_id

hubspot objects search --type tickets \
  --filter "hs_ticket_priority=HIGH AND createdate<$(date -v-7d +%Y-%m-%d)" \
  --properties subject,hs_ticket_priority,createdate,hubspot_owner_id

# Linux
hubspot objects search --type tickets \
  --filter "hs_ticket_priority=URGENT AND createdate<$(date -d '7 days ago' +%Y-%m-%d)" \
  --properties subject,hs_ticket_priority,createdate,hubspot_owner_id
```

**Property:** `hs_ticket_priority` — values: `LOW` `MEDIUM` `HIGH` `URGENT`

---

### Customer opted out of all email

```bash
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_email_optout=true" \
  --properties email,firstname,lastname,hs_email_optout,hubspot_owner_id
```

**Property:** `hs_email_optout` (boolean) — `true` means the contact has unsubscribed from all marketing email. This is a strong disengagement signal.

---

## Tier 2 — Moderate Risk Signals

### No sales activity in 30 days

```bash
# macOS
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_last_sales_activity_date<$(date -v-30d +%Y-%m-%d) AND hs_email_optout!=true" \
  --properties email,firstname,lastname,hs_last_sales_activity_date,hubspot_owner_id

# Linux
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_last_sales_activity_date<$(date -d '30 days ago' +%Y-%m-%d) AND hs_email_optout!=true" \
  --properties email,firstname,lastname,hs_last_sales_activity_date,hubspot_owner_id
```

**Property:** `hs_last_sales_activity_date` (read-only datetime)

---

### No email engagement in 45 days

```bash
# macOS
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_email_last_open_date<$(date -v-45d +%Y-%m-%d) AND hs_email_optout!=true" \
  --properties email,firstname,hs_email_last_open_date,hubspot_owner_id

# Linux
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_email_last_open_date<$(date -d '45 days ago' +%Y-%m-%d) AND hs_email_optout!=true" \
  --properties email,firstname,hs_email_last_open_date,hubspot_owner_id
```

**Property:** `hs_email_last_open_date` (datetime)

---

### Company with no active deals in the pipeline

`num_associated_deals` on a company counts all associated deals. A value of 0 means no open pipeline — the account has no expansion or renewal in motion.

```bash
hubspot objects search --type companies \
  --filter "num_associated_deals<1" \
  --properties name,annualrevenue,hs_last_sales_activity_date,hs_num_associated_contacts
```

**Property:** `num_associated_deals` (read-only number) — counts all associated deals; `<1` finds companies with nothing in the pipeline.

---

### No calls or notes logged in 30 days

Run a combined query on `notes_last_contacted` as a proxy for logged activity:

```bash
# macOS
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND notes_last_updated<$(date -v-30d +%Y-%m-%d)" \
  --properties email,firstname,notes_last_contacted,notes_last_updated,hubspot_owner_id

# Linux
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND notes_last_updated<$(date -d '30 days ago' +%Y-%m-%d)" \
  --properties email,firstname,notes_last_contacted,notes_last_updated,hubspot_owner_id
```

**Properties:** `notes_last_contacted`, `notes_last_updated`

---

## Tier 3 — Engagement Indicators (Positive)

These indicate an active, healthy customer relationship.

### Recent email engagement (within 14 days)

```bash
# macOS
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_email_last_open_date>$(date -v-14d +%Y-%m-%d)" \
  --properties email,firstname,hs_email_last_open_date

# Linux
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_email_last_open_date>$(date -d '14 days ago' +%Y-%m-%d)" \
  --properties email,firstname,hs_email_last_open_date
```

### Open deals with high probability

```bash
hubspot objects search --type deals \
  --filter "hs_deal_stage_probability>70 AND hs_is_closed!=true" \
  --properties dealname,hs_deal_stage_probability,amount,closedate,hubspot_owner_id
```

### Recent calls or meetings logged

Check via associations — get all calls for a contact logged after a date:

```bash
hubspot associations list --from contacts:<contact_id> --to calls --format jsonl \
| jq -r '.id' \
| xargs -I{} hubspot objects get --type calls {} \
    --properties hs_call_title,hs_call_status,hs_timestamp
```

---

## Dynamic Date Snippets

```bash
# macOS
DAYS_60_AGO=$(date -v-60d +%Y-%m-%d)
DAYS_30_AGO=$(date -v-30d +%Y-%m-%d)
DAYS_45_AGO=$(date -v-45d +%Y-%m-%d)
DAYS_14_AGO=$(date -v-14d +%Y-%m-%d)
DAYS_7_AGO=$(date -v-7d +%Y-%m-%d)

# Linux
DAYS_60_AGO=$(date -d '60 days ago' +%Y-%m-%d)
DAYS_30_AGO=$(date -d '30 days ago' +%Y-%m-%d)
DAYS_45_AGO=$(date -d '45 days ago' +%Y-%m-%d)
DAYS_14_AGO=$(date -d '14 days ago' +%Y-%m-%d)
DAYS_7_AGO=$(date -d '7 days ago' +%Y-%m-%d)
```
