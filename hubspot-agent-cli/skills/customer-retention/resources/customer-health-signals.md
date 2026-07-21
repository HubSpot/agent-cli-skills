# Customer Health Signals — Filter Cookbook

The signals HubSpot exposes for identifying churn risk, and how to query them. **No thresholds are prescribed** — what counts as "stale" or "at-risk" depends on the customer's sales cycle, support SLAs, and renewal cadence. Ask the user (or infer from their pipeline) before plugging in a cutoff.

Verify every property and enum in the target portal first: `hubspot properties get --type <type> <name>`. The SKILL.md "Verify properties" step is mandatory.

## Picking a cutoff

Before running any time-based filter, you need a cutoff date. Don't invent one — ask, or derive from context:

- **Outreach gaps** — what's a normal touch cadence for this team? (Monthly check-ins? Quarterly business reviews?) Stale = some multiple of that.
- **Ticket age** — what's the support SLA? "Old" should mean "past SLA," not a round number.
- **Engagement gaps** — how often does the team email customers? If it's a monthly newsletter, 45 days is two missed sends; if it's weekly, 45 days is six.
- **Subscription / renewal** — what's the billing cycle and renewal window?

If the user hasn't told you and you can't infer it, ask. A confident-sounding "60 days" with no basis is worse than a one-line clarifying question.

Date macros (work on macOS and Linux):

```bash
# Substitute N for whatever cutoff the user/context justifies
CUTOFF=$(date -v-${N}d +%Y-%m-%d 2>/dev/null || date -d "${N} days ago" +%Y-%m-%d)
```

---

## Signals HubSpot exposes

### Outreach recency — `notes_last_contacted`

Updates whenever a call, note, or meeting is logged and associated to the contact. Best signal for "has anyone actually talked to this customer."

```bash
# Customers not contacted since $CUTOFF
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND notes_last_contacted<$CUTOFF" \
  --properties email,firstname,notes_last_contacted,hubspot_owner_id

# Never contacted
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND !notes_last_contacted" \
  --properties email,firstname,hubspot_owner_id
```

### Broader sales activity — `hs_last_sales_activity_date`

Wider net than `notes_last_contacted` — also catches logged emails and tasks. Use when you want any rep touch, not just live conversation.

```bash
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_last_sales_activity_date<$CUTOFF AND hs_email_optout!=true" \
  --properties email,firstname,hs_last_sales_activity_date,hubspot_owner_id
```

### Email engagement — `hs_email_last_open_date`, `hs_email_last_click_date`

Customer-side signal: are they reading what's sent? Combine with `hs_email_optout!=true` so you don't double-count opt-outs as "unengaged."

```bash
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_email_last_open_date<$CUTOFF AND hs_email_optout!=true" \
  --properties email,firstname,hs_email_last_open_date
```

### Email opt-out — `hs_email_optout`

Hard signal — customer asked to stop hearing from you. Worth surfacing on its own, separate from engagement gaps.

```bash
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_email_optout=true" \
  --properties email,firstname,hubspot_owner_id
```

### Subscription status — `hs_subscription_status`

Enum is portal-specific. Run `hubspot properties get --type subscriptions hs_subscription_status` to list the exact values. Requires `subscriptions-read` scope on the token.

```bash
# Substitute the verified enum value (commonly past_due, cancelled, etc.)
hubspot objects search --type subscriptions \
  --filter "hs_subscription_status=<value>" \
  --properties hs_recurring_billing_total,hs_subscription_status
```

### Ticket pressure — `hs_ticket_priority` + `createdate`

`hs_ticket_priority` enum typically `LOW` / `MEDIUM` / `HIGH` / `URGENT` (verify). Multiple `--filter` flags are OR'd, so you can union priorities in one search. The cutoff here should map to the team's SLA, not a default.

```bash
hubspot objects search --type tickets \
  --filter "hs_ticket_priority=URGENT AND createdate<$CUTOFF" \
  --filter "hs_ticket_priority=HIGH    AND createdate<$CUTOFF" \
  --properties subject,hs_ticket_priority,createdate,hubspot_owner_id
```

To restrict to open tickets, discover the closed-stage ID first (it's pipeline-specific — `hubspot pipelines stages --type tickets --pipeline <id>`) and add `AND hs_pipeline_stage!=<closed_id>` to each clause.

### Open-deal pipeline — `hs_num_open_deals`

Read-only rollup on companies. Zero open deals means no expansion or renewal is currently in motion — a leading indicator, not an immediate risk.

```bash
hubspot objects search --type companies \
  --filter "hs_num_open_deals=0" \
  --properties name,annualrevenue,hs_last_sales_activity_date,hs_num_associated_contacts
```

---

## Known gaps

- **No native health/churn score.** HubSpot doesn't ship a built-in score — teams that have one use a custom property. Ask whether the portal has one before building from raw signals.
- **No Lists API, no sequences API.** You can identify at-risk customers via CLI, but enrolling them in re-engagement automation has to happen in the UI.

## Combining signals

Use multiple `--filter` flags (OR'd) to union signals into one watchlist, or chain conditions inside one `--filter` with `AND` for must-all-match. Pipe through `jq 'unique_by(.id)'` to dedupe across unioned queries before downstream task creation.

When in doubt about which signals to combine, ask the user what "at-risk" means for their business — different teams weight outreach gaps, ticket pressure, and engagement very differently.
