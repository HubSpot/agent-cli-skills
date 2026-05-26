---
name: customer-retention
description: Identify inactive/at-risk customers via CRM filters and create follow-up tasks at scale. Builds on `bulk-operations`; defers activity-creation specifics to `sales-execution`.
triggers:
  - "customer retention"
  - "churn risk"
  - "inactive customers"
  - "customer follow-up"
  - "at-risk accounts"
  - "customers not contacted"
  - "renewal"
  - "account health"
---

## Resources

| File | When to use |
|---|---|
| `resources/customer-health-signals.md` | Filter cookbook of churn signals — `--filter` expressions for `notes_last_contacted`, `hs_last_sales_activity_date`, `hs_email_optout`, stale tickets, subscription status. |

## Prereqs

Read `bulk-operations/SKILL.md` first — every read/write below uses its JSONL pipe, pagination, and dry-run/digest patterns. Activity-property tables and association rules live in `sales-execution/SKILL.md`.

Schema is portal-specific. Verify each property before filtering — e.g. `hubspot properties get --type contacts notes_last_contacted`, `... hs_last_sales_activity_date`, `... --type subscriptions hs_subscription_status`. If `subscriptions` returns 403, your token lacks `subscriptions-read` — use a private-app token with that scope.

## 1 — Find inactive customers

What "inactive" means is team-specific — pick a cutoff based on the team's touch cadence (monthly check-ins? quarterly reviews?). Ask if the user hasn't said.

```bash
# Substitute N for the cutoff the user/context justifies
CUTOFF=$(date -v-${N}d +%Y-%m-%d 2>/dev/null || date -d "${N} days ago" +%Y-%m-%d)

# No outreach since $CUTOFF (calls/notes/meetings update notes_last_contacted)
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND notes_last_contacted<$CUTOFF" \
  --properties email,firstname,notes_last_contacted,hubspot_owner_id

# No sales activity since $CUTOFF (broader — also catches emails/tasks)
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_last_sales_activity_date<$CUTOFF" \
  --properties email,firstname,hs_last_sales_activity_date

# Never contacted
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND !notes_last_contacted" \
  --properties email,firstname
```

For more signals (email opt-out, stale tickets, no open deals) see `resources/customer-health-signals.md`. For >100 hits, use the pagination loop from `bulk-operations`.

## 2 — Flag at-risk subscriptions

`subscriptions` is a standard object (`hubspot objects types` confirms). Enum values for `hs_subscription_status` are portal-specific — verify before filtering, then plug the exact value in:

```bash
hubspot properties get --type subscriptions hs_subscription_status   # lists allowed values

# Past-due — revenue at immediate risk (substitute your verified value)
hubspot objects search --type subscriptions \
  --filter "hs_subscription_status=past_due" \
  --properties hs_recurring_billing_total,hs_subscription_status

# Map an at-risk subscription to its contact for outreach
hubspot associations list --from subscriptions:<sub_id> --to contacts --format jsonl
```

## 3 — Create a follow-up task or check-in note

Activity creation lives in `sales-execution` (full property tables, note + meeting flows). One anchor example — unassociated tasks are invisible in the CRM UI, so always associate:

```bash
task_id=$(hubspot objects create --type tasks \
  --property hs_task_subject="Q1 retention check-in" \
  --property hs_task_priority=HIGH --property hs_task_status=NOT_STARTED \
  --property hs_task_type=CALL --property hs_timestamp=$(date +%s)000 \
  --format json | jq -r '.id')
hubspot associations create --from tasks:$task_id --to contacts:<contact_id>
```

## 4 — Bulk task creation for a cohort

Pipe a search through `jq` into one `objects create` call, then associate. Preview with `--dry-run` first (`bulk-operations` covers digest/confirm for >100 rows).

```bash
# Pick DUE_DAYS based on the team's follow-up SLA (ask if unknown)
DUE_DAYS=<N>   # substitute the number of days
DUE_MS=$(( ($(date +%s) + DUE_DAYS*86400) * 1000 ))

# 1. Capture the cohort (same file feeds both create + associate)
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND notes_last_contacted<$CUTOFF" \
  --properties firstname > /tmp/inactive.jsonl

# 2. Build task payloads — one per contact
jq -c --arg due "$DUE_MS" '{
  contact_id: .id,
  properties: {
    hs_task_subject: ("Re-engage: " + (.properties.firstname // "customer")),
    hs_task_priority: "HIGH", hs_task_status: "NOT_STARTED",
    hs_task_type: "CALL", hs_timestamp: $due
  }
}' /tmp/inactive.jsonl > /tmp/task_payloads.jsonl

# 3. Dry-run, then create (drop contact_id before piping)
jq -c '{properties}' /tmp/task_payloads.jsonl | hubspot objects create --type tasks --dry-run | head
jq -c '{properties}' /tmp/task_payloads.jsonl | hubspot objects create --type tasks > /tmp/created.jsonl

# 4. Associate each new task to its contact (paste preserves order)
paste <(jq -r '.id' /tmp/created.jsonl) <(jq -r '.contact_id' /tmp/task_payloads.jsonl) \
  | while read task_id contact_id; do
      hubspot associations create --from tasks:$task_id --to contacts:$contact_id
    done
```

One CLI call for the search, one for the create, then N for associations — no `xargs -I{}` per record. The output-order guarantee of `objects create` (one result per stdin line, in order — see `bulk-operations` "Output shape") is what makes the `paste` correct.

## Known gaps

- No native churn-score / health-score property — track via a custom property.
- No Lists API, no sequences/cadences API — re-engagement enrollment is not CLI-available.
- `hubspot associations create` does not batch — one CLI call per pair.
