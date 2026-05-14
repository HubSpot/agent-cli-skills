#!/bin/bash
# log-activity-and-associate.sh
#
# Utility functions demonstrating the full create-then-associate pattern
# for all four HubSpot activity types.
#
# Usage:
#   source log-activity-and-associate.sh
#   log_call contacts 12345 "Discovery call" "Discussed budget" OUTBOUND COMPLETED 1800000
#   log_note deals 67890 "Sent proposal via email"
#   log_meeting contacts 12345 "Demo Call" "Showed product" COMPLETED
#   create_task contacts 12345 "Follow up on proposal" HIGH CALL 7
#
# All functions print the created activity ID on success.

set -euo pipefail

# ── Timestamp helpers ─────────────────────────────────────────────────────────

now_ms() {
  # Returns current Unix time in milliseconds
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "$(date +%s)000"
  else
    date +%s%3N
  fi
}

future_ms() {
  # Returns Unix time in milliseconds N days from now
  local days="${1:?Provide number of days}"
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "$(date -v+${days}d +%s)000"
  else
    echo "$(date -d "${days} days" +%s)000"
  fi
}

# ── log_call ──────────────────────────────────────────────────────────────────
# Args: record_type record_id title body direction status duration_ms
#
# record_type: contacts | deals | companies | tickets
# direction:   INBOUND | OUTBOUND
# status:      COMPLETED | MISSED | NO_ANSWER | BUSY | CANCELED | FAILED
# duration_ms: milliseconds (60000 = 1 min, 1800000 = 30 min)
log_call() {
  local record_type="${1:?Provide record type (contacts|deals|companies|tickets)}"
  local record_id="${2:?Provide record ID}"
  local title="${3:?Provide call title}"
  local body="${4:?Provide call body/notes}"
  local direction="${5:-OUTBOUND}"
  local status="${6:-COMPLETED}"
  local duration_ms="${7:-0}"

  echo "==> Creating call: '$title' ..."

  local call_id
  call_id=$(
    hubspot objects create --type calls \
      --property "hs_call_title=$title" \
      --property "hs_call_body=$body" \
      --property "hs_call_direction=$direction" \
      --property "hs_call_status=$status" \
      --property "hs_call_duration=$duration_ms" \
      --property "hs_timestamp=$(now_ms)" \
      --format json \
    | jq -r '.data.id // .id'
  )

  if [[ -z "$call_id" || "$call_id" == "null" ]]; then
    echo "ERROR: Failed to create call" >&2
    return 1
  fi

  echo "    Created call ID: $call_id"
  echo "==> Associating call to $record_type:$record_id ..."
  hubspot associations create --from "calls:$call_id" --to "$record_type:$record_id"
  echo "    Association created."
  echo "$call_id"
}

# ── log_note ──────────────────────────────────────────────────────────────────
# Args: record_type record_id body
#
# record_type: contacts | deals | companies | tickets
# body:        Plain text or HTML (e.g., "<b>Summary:</b> ...")
log_note() {
  local record_type="${1:?Provide record type (contacts|deals|companies|tickets)}"
  local record_id="${2:?Provide record ID}"
  local body="${3:?Provide note body}"

  echo "==> Creating note ..."

  local note_id
  note_id=$(
    hubspot objects create --type notes \
      --property "hs_note_body=$body" \
      --property "hs_timestamp=$(now_ms)" \
      --format json \
    | jq -r '.data.id // .id'
  )

  if [[ -z "$note_id" || "$note_id" == "null" ]]; then
    echo "ERROR: Failed to create note" >&2
    return 1
  fi

  echo "    Created note ID: $note_id"
  echo "==> Associating note to $record_type:$record_id ..."
  hubspot associations create --from "notes:$note_id" --to "$record_type:$record_id"
  echo "    Association created."
  echo "$note_id"
}

# ── log_meeting ───────────────────────────────────────────────────────────────
# Args: record_type record_id title body outcome [location]
#
# record_type: contacts | deals | companies
# outcome:     SCHEDULED | COMPLETED | RESCHEDULED | NO_SHOW | CANCELLED
log_meeting() {
  local record_type="${1:?Provide record type (contacts|deals|companies)}"
  local record_id="${2:?Provide record ID}"
  local title="${3:?Provide meeting title}"
  local body="${4:?Provide meeting notes/body}"
  local outcome="${5:-COMPLETED}"
  local location="${6:-}"

  local start_ms
  start_ms=$(now_ms)
  local end_ms
  end_ms=$(( start_ms + 3600000 ))

  echo "==> Creating meeting: '$title' ..."

  local meeting_args=(
    --property "hs_meeting_title=$title"
    --property "hs_meeting_body=$body"
    --property "hs_meeting_outcome=$outcome"
    --property "hs_meeting_start_time=$start_ms"
    --property "hs_meeting_end_time=$end_ms"
    --property "hs_timestamp=$start_ms"
  )

  if [[ -n "$location" ]]; then
    meeting_args+=(--property "hs_meeting_location=$location")
  fi

  local meeting_id
  meeting_id=$(
    hubspot objects create --type meetings \
      "${meeting_args[@]}" \
      --format json \
    | jq -r '.data.id // .id'
  )

  if [[ -z "$meeting_id" || "$meeting_id" == "null" ]]; then
    echo "ERROR: Failed to create meeting" >&2
    return 1
  fi

  echo "    Created meeting ID: $meeting_id"
  echo "==> Associating meeting to $record_type:$record_id ..."
  hubspot associations create --from "meetings:$meeting_id" --to "$record_type:$record_id"
  echo "    Association created."
  echo "$meeting_id"
}

# ── create_task ───────────────────────────────────────────────────────────────
# Args: record_type record_id subject priority type due_days_from_now [body]
#
# record_type:       contacts | deals | companies
# priority:          LOW | MEDIUM | HIGH
# type:              TODO | CALL | EMAIL
# due_days_from_now: integer number of days until due (e.g., 3 = due in 3 days)
# body:              optional task notes
create_task() {
  local record_type="${1:?Provide record type (contacts|deals|companies)}"
  local record_id="${2:?Provide record ID}"
  local subject="${3:?Provide task subject}"
  local priority="${4:-MEDIUM}"
  local task_type="${5:-TODO}"
  local due_days="${6:-3}"
  local body="${7:-}"

  local due_ms
  due_ms=$(future_ms "$due_days")

  echo "==> Creating task: '$subject' (due in $due_days days) ..."

  local task_args=(
    --property "hs_task_subject=$subject"
    --property "hs_task_priority=$priority"
    --property "hs_task_type=$task_type"
    --property "hs_task_status=NOT_STARTED"
    --property "hs_timestamp=$due_ms"
  )

  if [[ -n "$body" ]]; then
    task_args+=(--property "hs_task_body=$body")
  fi

  local task_id
  task_id=$(
    hubspot objects create --type tasks \
      "${task_args[@]}" \
      --format json \
    | jq -r '.data.id // .id'
  )

  if [[ -z "$task_id" || "$task_id" == "null" ]]; then
    echo "ERROR: Failed to create task" >&2
    return 1
  fi

  echo "    Created task ID: $task_id"
  echo "==> Associating task to $record_type:$record_id ..."
  hubspot associations create --from "tasks:$task_id" --to "$record_type:$record_id"
  echo "    Association created."
  echo "$task_id"
}

# ── associate_to_multiple ─────────────────────────────────────────────────────
# Helper to associate a single activity to multiple records at once.
# Args: activity_type activity_id target_type id1 [id2 id3 ...]
#
# Example:
#   associate_to_multiple calls 111 contacts 222 333 444
associate_to_multiple() {
  local activity_type="${1:?Provide activity type}"
  local activity_id="${2:?Provide activity ID}"
  local target_type="${3:?Provide target type}"
  shift 3

  for target_id in "$@"; do
    echo "==> Associating $activity_type:$activity_id to $target_type:$target_id ..."
    hubspot associations create \
      --from "$activity_type:$activity_id" \
      --to "$target_type:$target_id"
  done
}

# ── Example usage (commented out) ────────────────────────────────────────────
# Uncomment and substitute real IDs to test.

# CONTACT_ID=12345
# DEAL_ID=67890

# Log a completed outbound call, associate to both contact and deal
# call_id=$(log_call contacts $CONTACT_ID "Discovery Call" "Discussed budget and timeline. Budget confirmed at $50K." OUTBOUND COMPLETED 1800000)
# hubspot associations create --from calls:$call_id --to deals:$DEAL_ID

# Log a note on a deal
# note_id=$(log_note deals $DEAL_ID "Sent proposal via email. Follow-up scheduled for Friday.")
# hubspot associations create --from notes:$note_id --to contacts:$CONTACT_ID

# Log a completed meeting, associate to contact and deal
# meeting_id=$(log_meeting contacts $CONTACT_ID "Demo Call — Acme Corp" "Walked through product demo. Strong interest in enterprise plan." COMPLETED "Zoom")
# hubspot associations create --from meetings:$meeting_id --to deals:$DEAL_ID

# Create a follow-up task due in 3 days, associate to contact and deal
# task_id=$(create_task contacts $CONTACT_ID "Follow up on proposal" HIGH CALL 3 "Call to confirm receipt and answer any questions")
# hubspot associations create --from tasks:$task_id --to deals:$DEAL_ID
