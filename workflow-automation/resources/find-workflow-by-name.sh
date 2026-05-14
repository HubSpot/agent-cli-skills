#!/bin/bash
# find-workflow-by-name.sh
#
# Lists all workflows and filters by a name substring (case-insensitive).
# The HubSpot API has no workflow search endpoint — filtering must be done locally.
#
# Usage:
#   ./find-workflow-by-name.sh "Welcome"
#   ./find-workflow-by-name.sh "mql nurture"
#
# One-liner equivalent:
#   hubspot workflows list --format jsonl | jq -c 'select(.name | test("Welcome"; "i"))'

set -euo pipefail

QUERY="${1:-}"

if [[ -z "${QUERY}" ]]; then
  echo "Usage: $0 <name-substring>"
  echo ""
  echo "Example: $0 \"Welcome\""
  exit 1
fi

hubspot workflows list --format jsonl \
  | jq -c --arg q "${QUERY}" 'select(.name | test($q; "i"))'
