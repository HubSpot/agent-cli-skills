#!/bin/bash
# mql-to-deal-pipeline.sh
#
# Creates deals for all MQL contacts and associates them, then promotes
# each contact's lifecyclestage to salesqualifiedlead.
#
# Usage:
#   PIPELINE_ID=abc123 STAGE_ID=xyz456 ./mql-to-deal-pipeline.sh
#   DRY_RUN=1 PIPELINE_ID=abc123 STAGE_ID=xyz456 ./mql-to-deal-pipeline.sh
#
# If PIPELINE_ID or STAGE_ID are not set, the script will prompt for them.

set -euo pipefail

# --- Resolve pipeline and stage IDs ---

if [[ -z "${PIPELINE_ID:-}" ]]; then
  echo "Available deal pipelines:"
  hubspot pipelines list --object deals --format table
  echo ""
  read -rp "Enter PIPELINE_ID: " PIPELINE_ID
fi

if [[ -z "${STAGE_ID:-}" ]]; then
  echo ""
  echo "Stages for pipeline ${PIPELINE_ID}:"
  hubspot pipelines stages --object deals --pipeline "${PIPELINE_ID}" --format table
  echo ""
  read -rp "Enter STAGE_ID for new deals: " STAGE_ID
fi

echo ""
echo "Pipeline ID : ${PIPELINE_ID}"
echo "Stage ID    : ${STAGE_ID}"
if [[ -n "${DRY_RUN:-}" ]]; then
  echo "Mode        : DRY RUN (no changes will be made)"
else
  echo "Mode        : LIVE"
fi
echo ""

# --- Fetch all MQL contacts ---

echo "Fetching MQL contacts..."
MQL_CONTACTS=$(hubspot objects search --type contacts \
  --filter "lifecyclestage=marketingqualifiedlead" \
  --properties email,firstname,lastname,company,hubspot_owner_id \
  --format jsonl)

if [[ -z "${MQL_CONTACTS}" ]]; then
  echo "No MQL contacts found. Nothing to do."
  exit 0
fi

TOTAL=$(echo "${MQL_CONTACTS}" | wc -l | tr -d ' ')
echo "Found ${TOTAL} MQL contact(s)."
echo ""

# --- Process each contact ---

CREATED=0
SKIPPED=0
FAILED=0

while IFS= read -r contact; do
  CONTACT_ID=$(echo "${contact}" | jq -r '.id')
  FIRSTNAME=$(echo "${contact}" | jq -r '.prop_firstname // ""')
  LASTNAME=$(echo "${contact}" | jq -r '.prop_lastname // ""')
  COMPANY=$(echo "${contact}" | jq -r '.prop_company // "Unknown Company"')
  EMAIL=$(echo "${contact}" | jq -r '.prop_email // ""')
  OWNER_ID=$(echo "${contact}" | jq -r '.prop_hubspot_owner_id // ""')

  DEAL_NAME="${FIRSTNAME} ${LASTNAME} - ${COMPANY} - New Business"
  DEAL_NAME=$(echo "${DEAL_NAME}" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

  echo "Processing contact ${CONTACT_ID} | ${EMAIL}"

  if [[ -n "${DRY_RUN:-}" ]]; then
    echo "  [DRY RUN] Would create deal: '${DEAL_NAME}'"
    echo "  [DRY RUN] Would associate deal to contact ${CONTACT_ID}"
    echo "  [DRY RUN] Would update contact lifecyclestage -> salesqualifiedlead"
    CREATED=$((CREATED + 1))
    continue
  fi

  # Create the deal
  CREATE_ARGS=(
    --type deals
    --property "dealname=${DEAL_NAME}"
    --property "pipeline=${PIPELINE_ID}"
    --property "dealstage=${STAGE_ID}"
    --property "amount=0"
    --property "dealtype=newbusiness"
  )
  if [[ -n "${OWNER_ID}" ]]; then
    CREATE_ARGS+=(--property "hubspot_owner_id=${OWNER_ID}")
  fi

  DEAL_RESULT=$(hubspot objects create "${CREATE_ARGS[@]}" 2>&1) || {
    echo "  ERROR creating deal for contact ${CONTACT_ID}: ${DEAL_RESULT}"
    FAILED=$((FAILED + 1))
    continue
  }

  DEAL_ID=$(echo "${DEAL_RESULT}" | jq -r '.id')
  if [[ -z "${DEAL_ID}" || "${DEAL_ID}" == "null" ]]; then
    echo "  ERROR: could not extract deal ID from create response"
    FAILED=$((FAILED + 1))
    continue
  fi

  echo "  Created deal ${DEAL_ID}: '${DEAL_NAME}'"

  # Associate deal to contact
  hubspot associations create --from "deals:${DEAL_ID}" --to "contacts:${CONTACT_ID}" >/dev/null 2>&1 || {
    echo "  WARNING: failed to associate deal ${DEAL_ID} to contact ${CONTACT_ID}"
  }

  # Look up company association for the contact and associate deal to company
  COMPANY_ASSOC=$(hubspot associations list --from "contacts:${CONTACT_ID}" --to companies --format jsonl 2>/dev/null | head -1)
  if [[ -n "${COMPANY_ASSOC}" ]]; then
    COMPANY_ID=$(echo "${COMPANY_ASSOC}" | jq -r '.id // empty')
    if [[ -n "${COMPANY_ID}" ]]; then
      hubspot associations create --from "deals:${DEAL_ID}" --to "companies:${COMPANY_ID}" >/dev/null 2>&1 || {
        echo "  WARNING: failed to associate deal ${DEAL_ID} to company ${COMPANY_ID}"
      }
      echo "  Associated to company ${COMPANY_ID}"
    fi
  fi

  # Promote contact lifecycle stage
  hubspot objects update --type contacts "${CONTACT_ID}" \
    --property "lifecyclestage=salesqualifiedlead" \
    --property "hs_lead_status=OPEN_DEAL" >/dev/null 2>&1 || {
    echo "  WARNING: failed to update lifecyclestage for contact ${CONTACT_ID}"
  }

  echo "  Updated contact ${CONTACT_ID} -> salesqualifiedlead / OPEN_DEAL"
  CREATED=$((CREATED + 1))

done <<< "${MQL_CONTACTS}"

# --- Summary ---

echo ""
echo "============================="
echo "  Summary"
echo "============================="
echo "  Total MQLs processed : ${TOTAL}"
if [[ -n "${DRY_RUN:-}" ]]; then
  echo "  Would create deals   : ${CREATED}"
else
  echo "  Deals created        : ${CREATED}"
  echo "  Failed               : ${FAILED}"
fi
echo "============================="
