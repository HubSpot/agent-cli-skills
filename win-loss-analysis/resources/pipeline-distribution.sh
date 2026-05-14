#!/bin/bash
# pipeline-distribution.sh
#
# Fetches all open deals and prints a stage-by-stage breakdown:
# deal count and total ARR per stage.
#
# Usage:
#   ./pipeline-distribution.sh
#
# Optional env vars:
#   PIPELINE_ID   — filter to a specific pipeline ID (default: all pipelines)
#   INCLUDE_CLOSED — set to "true" to include closed deals (default: false)

set -euo pipefail

INCLUDE_CLOSED="${INCLUDE_CLOSED:-false}"
PIPELINE_ID="${PIPELINE_ID:-}"

echo "Pipeline Distribution"
echo "Generated: $(date '+%Y-%m-%d %H:%M')"
echo ""

# Build filter
if [[ "$INCLUDE_CLOSED" == "true" ]]; then
  base_filter=""
else
  base_filter="hs_is_closed!=true"
fi

if [[ -n "$PIPELINE_ID" ]]; then
  if [[ -n "$base_filter" ]]; then
    filter="$base_filter AND pipeline=$PIPELINE_ID"
  else
    filter="pipeline=$PIPELINE_ID"
  fi
else
  filter="$base_filter"
fi

echo "Fetching deals (filter: ${filter:-none})..."
echo ""

# Collect all deals (up to 100 — for larger pipelines use the pagination loop)
if [[ -n "$filter" ]]; then
  deals=$(
    hubspot objects search --type deals \
      --filter "$filter" \
      --properties dealstage,amount,pipeline \
      --limit 100
  )
else
  deals=$(
    hubspot objects list --type deals \
      --properties dealstage,amount,pipeline \
      --limit 100
  )
fi

if [[ -z "$deals" ]]; then
  echo "No deals found."
  exit 0
fi

deal_count=$(echo "$deals" | wc -l | tr -d ' ')
echo "Total deals fetched: $deal_count"
echo "(Note: limited to 100 — use the bulk-operations pagination loop for larger pipelines)"
echo ""

echo "$deals" | jq -rs '
  group_by(.prop_dealstage)
  | sort_by(.[0].prop_dealstage)
  | map({
      stage: (.[0].prop_dealstage // "(none)"),
      count: length,
      total_value: ([.[].prop_amount | select(. != null and . != "") | tonumber] | add // 0 | round)
    })
  | ["Stage", "Count", "Total Value ($)"],
    ["─────────────────────────────", "─────", "──────────────"],
    (.[] | [.stage, (.count | tostring), (.total_value | tostring)])
  | @tsv
' | column -t -s $'\t'

echo ""

# Summary totals
echo "$deals" | jq -rs '
  {
    total_deals: length,
    total_value: ([.[].prop_amount | select(. != null and . != "") | tonumber] | add // 0 | round)
  }
  | "Total open deals: \(.total_deals)",
    "Total pipeline value: $\(.total_value)"
' -r

echo ""
echo "Tip: run 'hubspot pipelines stages --object deals --pipeline <id> --format table'"
echo "     to map stage IDs above to human-readable stage names."
