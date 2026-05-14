#!/bin/bash
# bulk-stage-update.sh
#
# Moves all deals currently in SOURCE_STAGE_ID to TARGET_STAGE_ID.
#
# Usage:
#   SOURCE_STAGE_ID=<id> TARGET_STAGE_ID=<id> ./bulk-stage-update.sh
#
# Get stage IDs first:
#   hubspot pipelines list --object deals --format table
#   hubspot pipelines stages --object deals --pipeline <pipeline_id> --format table

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
SOURCE_STAGE_ID="${SOURCE_STAGE_ID:?Set SOURCE_STAGE_ID to the stage you are moving deals FROM}"
TARGET_STAGE_ID="${TARGET_STAGE_ID:?Set TARGET_STAGE_ID to the stage you are moving deals TO}"

echo "Source stage: $SOURCE_STAGE_ID"
echo "Target stage: $TARGET_STAGE_ID"
echo ""

# ── Step 1: Dry-run — count deals that would be affected ──────────────────────
echo "==> Dry-run: finding deals in stage '$SOURCE_STAGE_ID'..."

DRY_RUN_OUTPUT=$(
  hubspot objects search --type deals \
    --filter "dealstage=$SOURCE_STAGE_ID AND hs_is_closed!=true" \
    --properties dealname,closedate,hubspot_owner_id,amount \
    2>&1
)

if [[ -z "$DRY_RUN_OUTPUT" ]]; then
  echo "No open deals found in stage '$SOURCE_STAGE_ID'. Nothing to do."
  exit 0
fi

DEAL_COUNT=$(echo "$DRY_RUN_OUTPUT" | wc -l | tr -d ' ')
echo ""
echo "Found $DEAL_COUNT deal(s) that would be moved:"
echo ""
echo "$DRY_RUN_OUTPUT" | jq -r '"  \(.id)  \(.prop_dealname // "(no name)")  close: \(.prop_closedate // "none")"' 2>/dev/null \
  || echo "$DRY_RUN_OUTPUT"

echo ""

# ── Step 2: Confirmation prompt ───────────────────────────────────────────────
read -r -p "Move all $DEAL_COUNT deal(s) from stage '$SOURCE_STAGE_ID' to '$TARGET_STAGE_ID'? [y/N] " CONFIRM

if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted. No changes made."
  exit 0
fi

echo ""

# ── Step 3: Execute the stage update ─────────────────────────────────────────
echo "==> Updating deal stages..."
# Note: search returns at most 100 records. If you have more than 100 deals
# in this stage, use the pagination loop from the bulk-operations skill to
# collect all IDs first, then pipe to update.

hubspot objects search --type deals \
  --filter "dealstage=$SOURCE_STAGE_ID AND hs_is_closed!=true" \
| jq -c "{id, properties: {dealstage: \"$TARGET_STAGE_ID\"}}" \
| hubspot objects update --type deals

echo ""
echo "Done. All deals moved from '$SOURCE_STAGE_ID' to '$TARGET_STAGE_ID'."
echo ""
echo "Verify by running:"
echo "  hubspot objects search --type deals --filter \"dealstage=$TARGET_STAGE_ID\" --properties dealname,dealstage"
