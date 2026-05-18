# Customer Health Signals — Filter Cookbook

Churn-risk filter expressions organized by tier. Drop these into `hubspot objects search --filter "..."`. Verify every property/enum in your portal first via `hubspot properties get --object <type> <name>` — the SKILL.md "Verify properties" step is mandatory.

Date macros below work on both macOS and Linux:

```bash
CUTOFF_60=$(date -v-60d +%Y-%m-%d 2>/dev/null || date -d '60 days ago' +%Y-%m-%d)
CUTOFF_30=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d)
CUTOFF_7=$(date -v-7d  +%Y-%m-%d 2>/dev/null || date -d '7 days ago'  +%Y-%m-%d)
```

---

## Tier 1 — Strong churn signals

### No outreach in 60+ days

`notes_last_contacted` updates whenever a call/note/meeting is logged and associated to the contact.

```bash
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND notes_last_contacted<$CUTOFF_60" \
  --properties email,firstname,notes_last_contacted,hubspot_owner_id

# Never contacted
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND !notes_last_contacted" \
  --properties email,firstname,hubspot_owner_id
```

### Subscription past-due / cancelled

`hs_subscription_status` enum is portal-specific — run `hubspot properties get --object subscriptions hs_subscription_status` and substitute the exact value. Requires the `subscriptions-read` scope on your token.

```bash
hubspot objects search --type subscriptions \
  --filter "hs_subscription_status=past_due" \
  --properties hs_recurring_billing_total,hs_subscription_status

hubspot objects search --type subscriptions \
  --filter "hs_subscription_status=cancelled" \
  --properties hs_recurring_billing_total,hs_subscription_status
```

### High-priority open tickets older than 7 days

`hs_ticket_priority` enum: `LOW` / `MEDIUM` / `HIGH` / `URGENT` (verify in your portal). Multiple `--filter` flags are OR'd:

```bash
hubspot objects search --type tickets \
  --filter "hs_ticket_priority=URGENT AND createdate<$CUTOFF_7" \
  --filter "hs_ticket_priority=HIGH AND createdate<$CUTOFF_7" \
  --properties subject,hs_ticket_priority,createdate,hubspot_owner_id
```

### Contact opted out of all email

```bash
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_email_optout=true" \
  --properties email,firstname,hubspot_owner_id
```

---

## Tier 2 — Moderate risk

### No sales activity in 30 days

```bash
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_last_sales_activity_date<$CUTOFF_30 AND hs_email_optout!=true" \
  --properties email,firstname,hs_last_sales_activity_date,hubspot_owner_id
```

### No email engagement in 45 days

```bash
CUTOFF_45=$(date -v-45d +%Y-%m-%d 2>/dev/null || date -d '45 days ago' +%Y-%m-%d)
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_email_last_open_date<$CUTOFF_45 AND hs_email_optout!=true" \
  --properties email,firstname,hs_email_last_open_date
```

### Company with no open deals

`hs_num_open_deals` is a read-only rollup. Zero = no expansion or renewal in motion.

```bash
hubspot objects search --type companies \
  --filter "hs_num_open_deals=0" \
  --properties name,annualrevenue,hs_last_sales_activity_date,hs_num_associated_contacts
```

---

## Combining signals

Use multiple `--filter` flags (OR'd) to build a single watchlist of any-of matches, or chain conditions inside one `--filter` with `AND` for must-all-match. Pipe the unioned output through `jq 'unique_by(.id)'` if you want to dedupe before downstream task creation.
