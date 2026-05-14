#!/bin/bash
# batch-ticket-intake.sh
#
# Reads a CSV file of support requests and bulk-creates tickets in HubSpot.
# Optionally associates each ticket to a contact found by email.
#
# CSV format (with header row):
#   subject,description,priority,email
#   "Login error","User cannot log in since v3.2","HIGH","user@example.com"
#   "Billing question","Charged twice in April","MEDIUM","billing@acme.com"
#   "Export broken","CSV export produces empty file","URGENT",""
#
# The email column is optional — if blank, the contact association step is skipped.
#
# Required env vars:
#   PIPELINE_ID       — from: hubspot pipelines list --object tickets
#   PIPELINE_STAGE_ID — from: hubspot pipelines stages --object tickets --pipeline <id>
#
# Optional env vars:
#   DEFAULT_PRIORITY  — LOW | MEDIUM | HIGH | URGENT (default: MEDIUM)
#   DEFAULT_CATEGORY  — PRODUCT_ISSUE | BILLING_ISSUE | FEATURE_REQUEST | GENERAL_INQUIRY | OTHER (default: GENERAL_INQUIRY)
#   CSV_FILE          — path to input CSV (default: support_requests.csv)
#   OWNER_ID          — hubspot_owner_id to assign all created tickets (optional)
#
# Usage:
#   PIPELINE_ID=123 PIPELINE_STAGE_ID=456 ./batch-ticket-intake.sh
#   PIPELINE_ID=123 PIPELINE_STAGE_ID=456 CSV_FILE=my_tickets.csv ./batch-ticket-intake.sh

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
PIPELINE_ID="${PIPELINE_ID:?Set PIPELINE_ID — run: hubspot pipelines list --object tickets}"
PIPELINE_STAGE_ID="${PIPELINE_STAGE_ID:?Set PIPELINE_STAGE_ID — run: hubspot pipelines stages --object tickets --pipeline <id>}"
DEFAULT_PRIORITY="${DEFAULT_PRIORITY:-MEDIUM}"
DEFAULT_CATEGORY="${DEFAULT_CATEGORY:-GENERAL_INQUIRY}"
CSV_FILE="${CSV_FILE:-support_requests.csv}"
OWNER_ID="${OWNER_ID:-}"

CREATED_TICKETS_FILE="created_tickets_$(date +%Y%m%d_%H%M%S).jsonl"

echo "==> Batch ticket intake"
echo "    CSV file:        $CSV_FILE"
echo "    Pipeline ID:     $PIPELINE_ID"
echo "    Stage ID:        $PIPELINE_STAGE_ID"
echo "    Default priority: $DEFAULT_PRIORITY"
echo "    Output file:     $CREATED_TICKETS_FILE"
echo ""

if [[ ! -f "$CSV_FILE" ]]; then
  echo "ERROR: CSV file not found: $CSV_FILE" >&2
  exit 1
fi

# ── Helper: find contact ID by email ─────────────────────────────────────────
find_contact_by_email() {
  local email="$1"
  if [[ -z "$email" ]]; then
    echo ""
    return 0
  fi

  hubspot objects search --type contacts \
    --filter "email=$email" \
    --properties email \
    --format json 2>/dev/null \
  | jq -r '(.data // .)[0].id // empty' 2>/dev/null || true
}

# ── Process CSV ───────────────────────────────────────────────────────────────
# Skip the header row
HEADER_SKIPPED=false
LINE_NUMBER=0
SUCCESS_COUNT=0
FAIL_COUNT=0

while IFS=',' read -r subject description priority email; do
  LINE_NUMBER=$(( LINE_NUMBER + 1 ))

  if [[ "$HEADER_SKIPPED" == "false" ]]; then
    HEADER_SKIPPED=true
    continue
  fi

  # Strip surrounding quotes if present
  subject="${subject//\"/}"
  description="${description//\"/}"
  priority="${priority//\"/}"
  email="${email//\"/}"

  # Use defaults if fields are empty
  [[ -z "$priority" ]] && priority="$DEFAULT_PRIORITY"

  echo "==> [Line $LINE_NUMBER] Creating ticket: '$subject' (priority: $priority) ..."

  # Build the create command arguments
  CREATE_ARGS=(
    --property "subject=$subject"
    --property "content=$description"
    --property "hs_pipeline=$PIPELINE_ID"
    --property "hs_pipeline_stage=$PIPELINE_STAGE_ID"
    --property "hs_ticket_priority=$priority"
    --property "hs_ticket_category=$DEFAULT_CATEGORY"
  )

  if [[ -n "$OWNER_ID" ]]; then
    CREATE_ARGS+=(--property "hubspot_owner_id=$OWNER_ID")
  fi

  ticket_json=$(
    hubspot objects create --type tickets \
      "${CREATE_ARGS[@]}" \
      --format json 2>&1
  ) || {
    echo "    ERROR: Failed to create ticket for '$subject'" >&2
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
    continue
  }

  ticket_id=$(echo "$ticket_json" | jq -r '.data.id // .id')

  if [[ -z "$ticket_id" || "$ticket_id" == "null" ]]; then
    echo "    ERROR: Could not parse ticket ID from response" >&2
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
    continue
  fi

  echo "    Created ticket ID: $ticket_id"

  # Save to output file for reference
  echo "$ticket_json" | jq -c "{id: \"$ticket_id\", subject: \"$subject\", email: \"$email\"}" \
    >> "$CREATED_TICKETS_FILE"

  # Associate to contact by email if provided
  if [[ -n "$email" ]]; then
    echo "    Looking up contact for email: $email ..."
    contact_id=$(find_contact_by_email "$email")

    if [[ -n "$contact_id" ]]; then
      echo "    Found contact ID: $contact_id — associating ..."
      hubspot associations create \
        --from "tickets:$ticket_id" \
        --to "contacts:$contact_id" \
        && echo "    Association created." \
        || echo "    WARNING: Association failed (ticket still created)" >&2
    else
      echo "    No contact found for email '$email' — skipping association."
    fi
  fi

  SUCCESS_COUNT=$(( SUCCESS_COUNT + 1 ))
  echo ""

done < "$CSV_FILE"

# ── Summary ───────────────────────────────────────────────────────────────────
echo "==> Done."
echo "    Created:  $SUCCESS_COUNT ticket(s)"
echo "    Failed:   $FAIL_COUNT ticket(s)"
echo "    Output:   $CREATED_TICKETS_FILE"
echo ""

if [[ $SUCCESS_COUNT -gt 0 ]]; then
  echo "Created ticket IDs:"
  jq -r '.id' "$CREATED_TICKETS_FILE"
fi
