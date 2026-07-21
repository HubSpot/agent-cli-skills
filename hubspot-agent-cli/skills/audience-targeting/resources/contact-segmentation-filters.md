# Contact segmentation filter cookbook

Filter primitives for `hubspot objects search --type contacts`. Add `--properties` to control output. See `audience-targeting/SKILL.md` for syntax rules and `bulk-operations/SKILL.md` for pagination, piping, and destructive-op flow.

**Date thresholds, deal counts, and "engaged"/"unworked" cutoffs are not prescribed here** — what counts as recent, stale, or qualified depends on the team's cadence, cycle length, and definitions. Ask the user or derive from context (touch cadence, SLA, sales cycle) before plugging in a number.

Discover enum option values per portal:

```bash
hubspot objects list --type contacts --properties <name> --limit 100 --format json \
  | jq -r '.data[].properties.<name> // empty' | sort -u
```

Cutoff macro used in examples below (substitute `${N}` per query):

```bash
CUTOFF=$(date -v-${N}d +%Y-%m-%d 2>/dev/null || date -d "${N} days ago" +%Y-%m-%d)
```

---

## Lifecycle stage

Standard enum values are lowercase, exact match. Confirm options for this portal via the discovery one-liner above — portals can extend/rename stages.

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

`hs_lead_status` is itself an enum with portal-customizable options. Common default values (verify in portal):

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

# Opened since $CUTOFF
--filter "hs_email_last_open_date>$CUTOFF"

# Not opened since $CUTOFF
--filter "hs_email_last_open_date<$CUTOFF"

# Hard bounce on file
--filter "hs_email_bounce=true"

# Opted out
--filter "hs_email_optout=true"

# Opted in (use for campaign-eligible cohorts)
--filter "hs_email_optout!=true"

# Email sent but never opened
--filter "hs_email_last_send_date AND !hs_email_last_open_date"
```

## Activity recency

Dates use `YYYY-MM-DD`. The cutoff value is the caller's call — derive from the team's touch cadence.

```bash
# Contacted since $CUTOFF
--filter "notes_last_contacted>$CUTOFF"

# Not contacted since $CUTOFF
--filter "notes_last_contacted<$CUTOFF"

# Never contacted
--filter "!notes_last_contacted"

# Last sales activity since $CUTOFF
--filter "hs_last_sales_activity_date>$CUTOFF"

# No sales activity ever
--filter "!hs_last_sales_activity_date"
```

## Deal association

`num_associated_deals` is a numeric rollup. The semantic meaning of "0", "≥1", "≥2" depends on the team's pipeline shape — don't assume "≥2 = upsell candidate" without confirming.

```bash
--filter "num_associated_deals=0"
--filter "num_associated_deals>=1"
--filter "num_associated_deals>=2"
```

## Owner

```bash
--filter "hubspot_owner_id=<id>"   # assigned to specific owner
--filter "!hubspot_owner_id"       # unassigned
--filter "hubspot_owner_id"        # any owner set
```

## Combined AND in one --filter

Examples below are illustrative shapes — the *threshold values* should come from the caller's definition of "stale," "engaged," etc.

```bash
# MQLs with no owner and no deals
--filter "lifecyclestage=marketingqualifiedlead AND !hubspot_owner_id AND num_associated_deals=0"

# Opted-in US leads not contacted since $CUTOFF
--filter "lifecyclestage=lead AND country=United States AND hs_email_optout!=true AND notes_last_contacted<$CUTOFF"

# SQLs with an open deal and recent sales activity (since $CUTOFF)
--filter "lifecyclestage=salesqualifiedlead AND num_associated_deals>=1 AND hs_last_sales_activity_date>$CUTOFF"

# Customers who opened email since $CUTOFF
--filter "lifecyclestage=customer AND hs_email_last_open_date>$CUTOFF AND hs_email_optout!=true"
```

## OR across --filter flags

Each flag is a group; records matching any group are returned.

```bash
# Top-of-funnel union (leads OR MQLs)
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead" \
  --filter "lifecyclestage=marketingqualifiedlead"

# Any active sales status
hubspot objects search --type contacts \
  --filter "hs_lead_status=IN_PROGRESS" \
  --filter "hs_lead_status=OPEN" \
  --filter "hs_lead_status=CONNECTED"

# Engaged via email OR sales touch (since $CUTOFF)
hubspot objects search --type contacts \
  --filter "hs_email_last_open_date>$CUTOFF" \
  --filter "notes_last_contacted>$CUTOFF"

# Never-contacted leads OR subscribers
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead AND !notes_last_contacted" \
  --filter "lifecyclestage=subscriber AND !notes_last_contacted"
```
