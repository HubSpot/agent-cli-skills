# Contact segmentation filter cookbook

Filter expressions for `hubspot objects search --type contacts`. Add `--properties` to control output. See `audience-targeting/SKILL.md` for syntax rules and `bulk-operations/SKILL.md` for pagination, piping, and destructive-op flow. Discover enum option values per portal with `hubspot objects list --type contacts --properties <name> --limit 100 --format json | jq -r '.data[].properties.<name> // empty' | sort -u`.

---

## Lifecycle stage

Standard enum values are lowercase, exact match. Confirm options for this portal via the discovery one-liner above.

```bash
--filter "lifecyclestage=subscriber"
--filter "lifecyclestage=lead"
--filter "lifecyclestage=marketingqualifiedlead"
--filter "lifecyclestage=salesqualifiedlead"
--filter "lifecyclestage=opportunity"
--filter "lifecyclestage=customer"
--filter "lifecyclestage=evangelist"
```

## Lead status

`hs_lead_status` is itself an enum with portal-customizable options. Standard values:

```bash
--filter "hs_lead_status=NEW"
--filter "hs_lead_status=OPEN"
--filter "hs_lead_status=IN_PROGRESS"
--filter "hs_lead_status=OPEN_DEAL"
--filter "hs_lead_status=UNQUALIFIED"
--filter "hs_lead_status=ATTEMPTED_TO_CONTACT"
--filter "hs_lead_status=CONNECTED"
--filter "hs_lead_status=BAD_TIMING"

# Combine with stage
--filter "lifecyclestage=lead AND hs_lead_status=NEW"
```

## Email engagement

```bash
# Has opened at least once (field present)
--filter "hs_email_last_open_date"

# Never opened (field absent)
--filter "!hs_email_last_open_date"

# Opened after a date
--filter "hs_email_last_open_date>2026-01-01"

# Not opened since a date (unengaged)
--filter "hs_email_last_open_date<2026-01-01"

# Hard bounce on file
--filter "hs_email_bounce=true"

# Opted out
--filter "hs_email_optout=true"

# Opted in (preferred for campaigns)
--filter "hs_email_optout!=true"

# Email sent but never opened (low engagement)
--filter "hs_email_last_send_date AND !hs_email_last_open_date"
```

## Activity recency

Dates use `YYYY-MM-DD`.

```bash
# Contacted in the last 30 days (substitute today minus 30)
--filter "notes_last_contacted>2026-04-15"

# Not contacted in the last 90 days
--filter "notes_last_contacted<2026-02-15"

# Never contacted
--filter "!notes_last_contacted"

# Last sales activity within 14 days
--filter "hs_last_sales_activity_date>2026-05-01"

# No sales activity ever
--filter "!hs_last_sales_activity_date"
```

## Deal association

```bash
--filter "num_associated_deals>=1"   # has pipeline
--filter "num_associated_deals=0"    # net-new prospect
--filter "num_associated_deals>=2"   # upsell candidates
```

## Owner

```bash
--filter "hubspot_owner_id=12345"    # assigned to specific owner
--filter "!hubspot_owner_id"         # unassigned
--filter "hubspot_owner_id"          # any owner set
```

## Combined AND in one --filter

```bash
# MQLs with no owner and no deals (unworked)
--filter "lifecyclestage=marketingqualifiedlead AND !hubspot_owner_id AND num_associated_deals=0"

# Opted-in US leads not contacted in 60 days
--filter "lifecyclestage=lead AND country=United States AND hs_email_optout!=true AND notes_last_contacted<2026-03-15"

# SQLs with an open deal and recent sales activity
--filter "lifecyclestage=salesqualifiedlead AND num_associated_deals>=1 AND hs_last_sales_activity_date>2026-05-01"

# Customers re-engaged on email
--filter "lifecyclestage=customer AND hs_email_last_open_date>2026-04-01 AND hs_email_optout!=true"
```

## OR across --filter flags

Each flag is a group; records matching any group are returned.

```bash
# Top of funnel (leads OR MQLs)
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead" \
  --filter "lifecyclestage=marketingqualifiedlead"

# Any active sales status
hubspot objects search --type contacts \
  --filter "hs_lead_status=IN_PROGRESS" \
  --filter "hs_lead_status=OPEN" \
  --filter "hs_lead_status=CONNECTED"

# Engaged via email OR via sales touch
hubspot objects search --type contacts \
  --filter "hs_email_last_open_date>2026-04-15" \
  --filter "notes_last_contacted>2026-04-15"

# Never-contacted leads OR subscribers (nurture re-entry)
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead AND !notes_last_contacted" \
  --filter "lifecyclestage=subscriber AND !notes_last_contacted"
```
