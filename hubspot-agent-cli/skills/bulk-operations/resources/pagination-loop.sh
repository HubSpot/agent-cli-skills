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
#   bash pagination-loop.sh <object_type> <output_file> [properties] [extra_flags...]
#
# EXAMPLES:
#   bash pagination-loop.sh contacts /tmp/contacts.jsonl
#   bash pagination-loop.sh contacts /tmp/contacts.jsonl email,firstname,lastname
#   bash pagination-loop.sh contacts /tmp/leads.jsonl email,firstname '--filter lifecyclestage=lead'
#
# To use search instead of list, pass --filter flags as extra_flags.

set -eo pipefail

OBJECT_TYPE="${1:?Usage: pagination-loop.sh <object_type> <output_file> [properties] [extra_flags...]}"
OUTPUT_FILE="${2:?Usage: pagination-loop.sh <object_type> <output_file> [properties] [extra_flags...]}"
PROPERTIES="${3:-}"
shift 3 2>/dev/null || shift $#
EXTRA_FLAGS=("$@")

LIMIT=100

# ── Build base command args ──────────────────────────────────────────────────

# Auto-detect: use "objects search" when --filter is present, "objects list" otherwise
SUBCOMMAND="list"
for flag in "${EXTRA_FLAGS[@]}"; do
  if [ "$flag" = "--filter" ]; then
    SUBCOMMAND="search"
    break
  fi
done

BASE_ARGS=(hubspot objects "$SUBCOMMAND" --type "$OBJECT_TYPE" --limit "$LIMIT" --format json)

if [ -n "$PROPERTIES" ]; then
  BASE_ARGS+=(--properties "$PROPERTIES")
fi

if [ ${#EXTRA_FLAGS[@]} -gt 0 ]; then
  BASE_ARGS+=("${EXTRA_FLAGS[@]}")
fi

# ── Pagination loop ──────────────────────────────────────────────────────────

> "$OUTPUT_FILE"

after=""
page=0

echo "Paginating ${OBJECT_TYPE} → ${OUTPUT_FILE}" >&2

while true; do
  page=$((page + 1))

  if [ -z "$after" ]; then
    result=$("${BASE_ARGS[@]}")
  else
    result=$("${BASE_ARGS[@]}" --after "$after")
  fi

  count=$(echo "$result" | jq '.data | length')
  echo "$result" | jq -c '.data[]' >> "$OUTPUT_FILE"

  echo "  page ${page}: ${count} records" >&2

  next=$(echo "$result" | jq -r '.meta.next // empty')

  if [ -z "$next" ]; then
    break
  fi

  after="$next"
done

total=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
echo "Done. ${total} total records written to ${OUTPUT_FILE}" >&2
