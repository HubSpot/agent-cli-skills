#!/bin/bash
# pagination-loop.sh
#
# Generic pagination loop for hubspot CLI commands.
#
# The CLI returns at most 100 records per call. When --format json is used,
# the response envelope looks like:
#   { "data": [...], "meta": { "next": "<cursor>" } }
#
# When meta.next is absent or null, there are no more pages.
# Pass the cursor value back as --after on the next call.
#
# USAGE:
#   Edit OBJECT_TYPE, OUTPUT_FILE, and optionally PROPERTIES / EXTRA_FLAGS below,
#   then run:
#     bash pagination-loop.sh
#
# To adapt for search instead of list, swap the hubspot command in the loop body
# and add --filter flags to EXTRA_FLAGS.

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

OBJECT_TYPE="contacts"          # contacts | companies | deals | tickets | ...
OUTPUT_FILE="all_${OBJECT_TYPE}.jsonl"
LIMIT=100                       # max per page; CLI cap is 100

# Optional: comma-separated list of properties to fetch.
# Leave empty to get the default property set.
PROPERTIES=""                   # e.g. "email,firstname,lastname,hubspot_owner_id"

# Optional: extra flags appended to each hubspot call.
# For search-based pagination, replace "objects list" with "objects search"
# and add --filter flags here, e.g.: EXTRA_FLAGS="--filter lifecyclestage=lead"
EXTRA_FLAGS=""

# ── Build base command ───────────────────────────────────────────────────────

BASE_CMD="hubspot objects list --type ${OBJECT_TYPE} --limit ${LIMIT} --format json"

if [ -n "$PROPERTIES" ]; then
  BASE_CMD="${BASE_CMD} --properties ${PROPERTIES}"
fi

if [ -n "$EXTRA_FLAGS" ]; then
  BASE_CMD="${BASE_CMD} ${EXTRA_FLAGS}"
fi

# ── Pagination loop ──────────────────────────────────────────────────────────

# Truncate output file at start (not append, so reruns are safe)
> "$OUTPUT_FILE"

after=""
page=0

echo "Paginating ${OBJECT_TYPE} → ${OUTPUT_FILE}" >&2

while true; do
  page=$((page + 1))

  if [ -z "$after" ]; then
    result=$(eval "$BASE_CMD")
  else
    result=$(eval "$BASE_CMD --after '$after'")
  fi

  # Write each record as a single JSONL line
  count=$(echo "$result" | jq '.data | length')
  echo "$result" | jq -c '.data[]' >> "$OUTPUT_FILE"

  echo "  page ${page}: ${count} records" >&2

  # Extract cursor for next page; empty string if absent
  next=$(echo "$result" | jq -r '.meta.next // empty')

  if [ -z "$next" ]; then
    break
  fi

  after="$next"
done

total=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
echo "Done. ${total} total records written to ${OUTPUT_FILE}" >&2

# ── Example: pipe accumulated results into a bulk update ────────────────────
#
# After this script finishes you can process the file in a second pass:
#
#   cat all_contacts.jsonl \
#   | jq -c '{id, properties: {lifecyclestage: "marketingqualifiedlead"}}' \
#   | hubspot objects update --type contacts --dry-run
#
# Or chain directly without saving to file by replacing the loop body with
# a direct pipe — but saving first is safer for large datasets because it
# lets you inspect before mutating.
