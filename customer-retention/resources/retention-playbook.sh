#!/bin/bash
# retention-playbook.sh
#
# Daily retention health check.
# Finds at-risk customers and creates follow-up tasks for each.
#
# Checks performed:
#   1. Customers with no contact in DAYS_INACTIVE days
#   2. Subscriptions that are PAST_DUE
#   3. High-priority open tickets older than TICKET_AGE_DAYS days
#
# Required:
#   - hubspot CLI authenticated (run `hubspot auth` if needed)
#   - jq installed
#
# Optional env vars:
#   DAYS_INACTIVE     — inactivity threshold in days (default: 60)
#   TICKET_AGE_DAYS   — age threshold for high-priority open tickets (default: 7)
#   TASK_DUE_DAYS     — days from now for follow-up task due date (default: 2)
#   TASK_PRIORITY     — priority for created tasks (default: HIGH)
#   OWNER_ID          — if set, assign created tasks to this owner
#   DRY_RUN           — set to "true" to print what would be done without creating tasks

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
DAYS_INACTIVE="${DAYS_INACTIVE:-60}"
TICKET_AGE_DAYS="${TICKET_AGE_DAYS:-7}"
TASK_DUE_DAYS="${TASK_DUE_DAYS:-2}"
TASK_PRIORITY="${TASK_PRIORITY:-HIGH}"
OWNER_ID="${OWNER_ID:-}"
DRY_RUN="${DRY_RUN:-false}"

# ── Date helpers ──────────────────────────────────────────────────────────────
if [[ "$(uname)" == "Darwin" ]]; then
  cutoff_date() { date -v-${1}d +%Y-%m-%d; }
  due_ms()      { echo "$(date -v+${TASK_DUE_DAYS}d +%s)000"; }
else
  cutoff_date() { date -d "${1} days ago" +%Y-%m-%d; }
  due_ms()      { echo "$(date -d "${TASK_DUE_DAYS} days" +%s)000"; }
fi

DUE_MS=$(due_ms)
INACTIVE_CUTOFF=$(cutoff_date "$DAYS_INACTIVE")
TICKET_CUTOFF=$(cutoff_date "$TICKET_AGE_DAYS")

echo "========================================"
echo "  Retention Health Check — $(date +%Y-%m-%d)"
echo "========================================"
echo "  Inactive threshold:    $DAYS_INACTIVE days (cutoff: $INACTIVE_CUTOFF)"
echo "  Ticket age threshold:  $TICKET_AGE_DAYS days (cutoff: $TICKET_CUTOFF)"
echo "  Task due in:           $TASK_DUE_DAYS days"
echo "  Dry run:               $DRY_RUN"
echo ""

TOTAL_TASKS_CREATED=0

# ── Helper: create a task and optionally associate it ─────────────────────────
create_followup_task() {
  local subject="$1"
  local target_type="$2"
  local target_id="$3"
  local body="${4:-}"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "    [DRY RUN] Would create task: '$subject' -> $target_type:$target_id"
    return 0
  fi

  local task_args=(
    --property "hs_task_subject=$subject"
    --property "hs_task_priority=$TASK_PRIORITY"
    --property "hs_task_status=NOT_STARTED"
    --property "hs_task_type=CALL"
    --property "hs_timestamp=$DUE_MS"
  )

  [[ -n "$body" ]]     && task_args+=(--property "hs_task_body=$body")
  [[ -n "$OWNER_ID" ]] && task_args+=(--property "hubspot_owner_id=$OWNER_ID")

  local task_id
  task_id=$(
    hubspot objects create --type tasks \
      "${task_args[@]}" \
      --format json 2>/dev/null \
    | jq -r '.data.id // .id'
  )

  if [[ -n "$task_id" && "$task_id" != "null" ]]; then
    hubspot associations create \
      --from "tasks:$task_id" \
      --to "$target_type:$target_id" \
      2>/dev/null || true
    echo "    Created task $task_id -> $target_type:$target_id"
    TOTAL_TASKS_CREATED=$(( TOTAL_TASKS_CREATED + 1 ))
  else
    echo "    WARNING: Failed to create task for $target_type:$target_id" >&2
  fi
}

# ── Check 1: Customers with no contact in DAYS_INACTIVE days ─────────────────
echo "----------------------------------------"
echo "Check 1: Customers inactive for ${DAYS_INACTIVE}+ days"
echo "----------------------------------------"

INACTIVE_FILE=$(mktemp)
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND notes_last_contacted<$INACTIVE_CUTOFF" \
  --properties email,firstname,lastname,notes_last_contacted,hubspot_owner_id \
  > "$INACTIVE_FILE" 2>/dev/null || true

INACTIVE_COUNT=$(wc -l < "$INACTIVE_FILE" | tr -d ' ')
echo "Found $INACTIVE_COUNT inactive customer(s)"
echo ""

if [[ $INACTIVE_COUNT -gt 0 ]]; then
  while IFS= read -r line; do
    contact_id=$(echo "$line" | jq -r '.id')
    firstname=$(echo "$line" | jq -r '.prop_firstname // "Customer"')
    lastname=$(echo "$line" | jq -r '.prop_lastname // ""')
    last_contacted=$(echo "$line" | jq -r '.prop_notes_last_contacted // "never"')
    echo "  Contact $contact_id — $firstname $lastname (last contacted: $last_contacted)"
    create_followup_task \
      "Re-engage: $firstname $lastname — no contact in ${DAYS_INACTIVE}+ days" \
      "contacts" \
      "$contact_id" \
      "Customer has not been contacted since $last_contacted. Schedule a check-in call."
  done < "$INACTIVE_FILE"
fi
rm -f "$INACTIVE_FILE"

echo ""

# ── Check 2: Past-due subscriptions ──────────────────────────────────────────
echo "----------------------------------------"
echo "Check 2: Past-due subscriptions"
echo "----------------------------------------"

PASTDUE_FILE=$(mktemp)
hubspot objects search --type subscriptions \
  --filter "hs_subscription_status=PAST_DUE" \
  --properties hs_mrr,hs_arr,hs_subscription_status \
  > "$PASTDUE_FILE" 2>/dev/null || true

PASTDUE_COUNT=$(wc -l < "$PASTDUE_FILE" | tr -d ' ')
echo "Found $PASTDUE_COUNT past-due subscription(s)"
echo ""

if [[ $PASTDUE_COUNT -gt 0 ]]; then
  while IFS= read -r line; do
    sub_id=$(echo "$line" | jq -r '.id')
    mrr=$(echo "$line" | jq -r '.prop_hs_mrr // "unknown"')
    echo "  Subscription $sub_id — MRR: $mrr"

    # Attempt to find associated contact for the subscription
    contact_ids=$(
      hubspot associations list \
        --from "subscriptions:$sub_id" \
        --to contacts \
        --format jsonl 2>/dev/null \
      | jq -r '.id' || true
    )

    if [[ -n "$contact_ids" ]]; then
      while IFS= read -r contact_id; do
        echo "    -> Associated contact: $contact_id"
        create_followup_task \
          "PAST DUE subscription — contact customer (MRR: $mrr)" \
          "contacts" \
          "$contact_id" \
          "Subscription $sub_id is PAST_DUE. MRR at risk: $mrr. Reach out immediately to resolve payment."
      done <<< "$contact_ids"
    else
      echo "    No associated contacts found — task not created"
    fi
  done < "$PASTDUE_FILE"
fi
rm -f "$PASTDUE_FILE"

echo ""

# ── Check 3: High-priority open tickets older than TICKET_AGE_DAYS ────────────
echo "----------------------------------------"
echo "Check 3: High-priority tickets older than ${TICKET_AGE_DAYS} days"
echo "----------------------------------------"

for priority in URGENT HIGH; do
  TICKET_FILE=$(mktemp)
  hubspot objects search --type tickets \
    --filter "hs_ticket_priority=$priority AND createdate<$TICKET_CUTOFF" \
    --properties subject,hs_ticket_priority,createdate,hubspot_owner_id \
    > "$TICKET_FILE" 2>/dev/null || true

  TICKET_COUNT=$(wc -l < "$TICKET_FILE" | tr -d ' ')
  echo "  $priority: $TICKET_COUNT ticket(s)"

  if [[ $TICKET_COUNT -gt 0 ]]; then
    while IFS= read -r line; do
      ticket_id=$(echo "$line" | jq -r '.id')
      subject=$(echo "$line" | jq -r '.prop_subject // "Ticket"')
      created=$(echo "$line" | jq -r '.prop_createdate // "unknown"')
      owner_id=$(echo "$line" | jq -r '.prop_hubspot_owner_id // ""')

      echo "    Ticket $ticket_id — '$subject' (created: $created)"

      # Find associated contacts
      contact_ids=$(
        hubspot associations list \
          --from "tickets:$ticket_id" \
          --to contacts \
          --format jsonl 2>/dev/null \
        | jq -r '.id' || true
      )

      if [[ -n "$contact_ids" ]]; then
        while IFS= read -r contact_id; do
          create_followup_task \
            "$priority ticket unresolved: $subject" \
            "contacts" \
            "$contact_id" \
            "Ticket $ticket_id has been open since $created with no resolution. Priority: $priority."
        done <<< "$contact_ids"
      fi

      # Also create a task on the ticket itself
      create_followup_task \
        "Escalate: $priority ticket open ${TICKET_AGE_DAYS}+ days — $subject" \
        "tickets" \
        "$ticket_id" \
        "This $priority ticket has been open since $created. Requires immediate attention."
    done < "$TICKET_FILE"
  fi
  rm -f "$TICKET_FILE"
done

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "========================================"
echo "  Retention check complete"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  Mode: DRY RUN — no tasks were created"
else
  echo "  Tasks created: $TOTAL_TASKS_CREATED"
fi
echo "========================================"
