#!/bin/bash
# bulk-reassignment.sh
#
# Reassigns all CRM records of a given type from one owner to another.
#
# USAGE:
#   1. Set OLD_OWNER_ID, NEW_OWNER_ID, and OBJECT_TYPE below.
#   2. Run the script: bash bulk-reassignment.sh
#   3. Review the dry-run output (printed to stdout).
#   4. Confirm the prompt to execute the real update.
#
# For transfers involving > 100 records, the script automatically paginates
# using the --after cursor pattern so every record is reassigned.
#
# REQUIREMENTS:
#   - hubspot CLI authenticated (run `hubspot auth` if needed)
#   - jq installed
#
# NOTE: Owner IDs are portal-specific numeric strings.
# Run `hubspot owners list --format table` to look up the correct IDs.

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

OLD_OWNER_ID="12345"            # Owner ID of the rep you are replacing
NEW_OWNER_ID="67890"            # Owner ID of the rep taking over
OBJECT_TYPE="contacts"          # contacts | deals | companies | tickets

# Optional: extra --properties to fetch during the search (for dry-run display)
DISPLAY_PROPERTIES="email,firstname,lastname"   # adjust per object type

# ── Helpers ──────────────────────────────────────────────────────────────────

die() { echo "ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" &>/dev/null || die "'$1' is required but not installed."
}

require_cmd jq
require_cmd hubspot

# ── Validate inputs ──────────────────────────────────────────────────────────

[[ -z "$OLD_OWNER_ID" ]] && die "OLD_OWNER_ID is not set."
[[ -z "$NEW_OWNER_ID" ]] && die "NEW_OWNER_ID is not set."
[[ -z "$OBJECT_TYPE"  ]] && die "OBJECT_TYPE is not set."

echo "Reassigning ${OBJECT_TYPE} from owner ${OLD_OWNER_ID} → ${NEW_OWNER_ID}" >&2
echo "" >&2

# ── Step 1: Collect all matching records (with pagination) ───────────────────

TMP_RECORDS=$(mktemp /tmp/reassign_records_XXXXXX.jsonl)
trap 'rm -f "$TMP_RECORDS"' EXIT

after=""
page=0

echo "Fetching ${OBJECT_TYPE} owned by ${OLD_OWNER_ID}..." >&2

while true; do
  page=$((page + 1))

  if [ -z "$after" ]; then
    result=$(hubspot objects search \
      --type "$OBJECT_TYPE" \
      --filter "hubspot_owner_id=${OLD_OWNER_ID}" \
      --properties "hubspot_owner_id,${DISPLAY_PROPERTIES}" \
      --limit 100 \
      --format json)
  else
    result=$(hubspot objects search \
      --type "$OBJECT_TYPE" \
      --filter "hubspot_owner_id=${OLD_OWNER_ID}" \
      --properties "hubspot_owner_id,${DISPLAY_PROPERTIES}" \
      --limit 100 \
      --after "$after" \
      --format json)
  fi

  count=$(echo "$result" | jq '.data | length')
  echo "$result" | jq -c '.data[]' >> "$TMP_RECORDS"
  echo "  page ${page}: ${count} records" >&2

  next=$(echo "$result" | jq -r '.meta.next // empty')
  if [ -z "$next" ]; then
    break
  fi
  after="$next"
done

total=$(wc -l < "$TMP_RECORDS" | tr -d ' ')
echo "" >&2
echo "Found ${total} ${OBJECT_TYPE} owned by ${OLD_OWNER_ID}." >&2

if [ "$total" -eq 0 ]; then
  echo "Nothing to reassign. Exiting." >&2
  exit 0
fi

# ── Step 2: Dry-run ──────────────────────────────────────────────────────────

echo "" >&2
echo "── DRY-RUN (no changes made) ──────────────────────────────────────────" >&2

cat "$TMP_RECORDS" \
| jq -c "{id, properties: {hubspot_owner_id: \"${NEW_OWNER_ID}\"}}" \
| hubspot objects update --type "$OBJECT_TYPE" --dry-run

echo "" >&2
echo "── END DRY-RUN ────────────────────────────────────────────────────────" >&2
echo "" >&2

# ── Step 3: Confirm before executing ────────────────────────────────────────

read -r -p "Reassign ${total} ${OBJECT_TYPE} to owner ${NEW_OWNER_ID}? [y/N] " confirm
echo "" >&2

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted. No changes were made." >&2
  exit 0
fi

# ── Step 4: Execute the reassignment ────────────────────────────────────────

echo "Executing reassignment..." >&2

cat "$TMP_RECORDS" \
| jq -c "{id, properties: {hubspot_owner_id: \"${NEW_OWNER_ID}\"}}" \
| hubspot objects update --type "$OBJECT_TYPE"

echo "" >&2
echo "Done. ${total} ${OBJECT_TYPE} reassigned from ${OLD_OWNER_ID} to ${NEW_OWNER_ID}." >&2

# ── To reassign multiple object types ────────────────────────────────────────
#
# Run this script once per object type, changing OBJECT_TYPE and
# DISPLAY_PROPERTIES each time, or wrap in a loop:
#
#   for obj in contacts deals companies; do
#     OBJECT_TYPE="$obj" bash bulk-reassignment.sh
#   done
#
# For companies, set: DISPLAY_PROPERTIES="name,domain"
# For deals, set:     DISPLAY_PROPERTIES="dealname,dealstage,amount"
# For tickets, set:   DISPLAY_PROPERTIES="subject,hs_pipeline_stage"
