#!/bin/bash
# match-and-enrich.sh
#
# Reads a JSONL file where each line has at minimum an "email" field.
# Looks up each email in HubSpot and outputs matched records with CRM
# properties merged in. Unmatched records are written to unmatched.jsonl.
#
# Usage:
#   INPUT_FILE=<path> ./match-and-enrich.sh
#
# Input format (one JSON object per line):
#   {"email":"user@example.com","name":"Jane Doe","title":"VP Sales"}
#
# Output (matched.jsonl):
#   {"email":"user@example.com","crm_id":"12345","crm_firstname":"Jane","crm_lifecyclestage":"customer",...}
#
# Output (unmatched.jsonl):
#   {"email":"unknown@example.com","name":"Unknown Person",...}
#
# Optional env vars:
#   CRM_PROPERTIES — comma-separated list of CRM properties to fetch
#                    (default: email,firstname,lastname,company,lifecyclestage,hubspot_owner_id)

set -euo pipefail

INPUT_FILE="${INPUT_FILE:?Set INPUT_FILE to path of your JSONL input file}"
CRM_PROPERTIES="${CRM_PROPERTIES:-email,firstname,lastname,company,lifecyclestage,hubspot_owner_id}"

MATCHED_FILE="matched.jsonl"
UNMATCHED_FILE="unmatched.jsonl"

> "$MATCHED_FILE"
> "$UNMATCHED_FILE"

total=0
matched=0
unmatched=0

echo "Processing $INPUT_FILE ..."
echo ""

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  total=$(( total + 1 ))

  email=$(echo "$line" | jq -r '.email // empty')
  if [[ -z "$email" ]]; then
    echo "  [SKIP] Line $total has no email field" >&2
    echo "$line" >> "$UNMATCHED_FILE"
    unmatched=$(( unmatched + 1 ))
    continue
  fi

  # Normalize email to lowercase
  email_lower=$(echo "$email" | tr '[:upper:]' '[:lower:]')

  result=$(
    hubspot objects search --type contacts \
      --filter "email=$email_lower" \
      --properties "$CRM_PROPERTIES" \
      2>/dev/null | head -1
  )

  if [[ -n "$result" ]]; then
    crm_id=$(echo "$result" | jq -r '.id')
    # Merge external record with CRM properties
    echo "$result" | jq -c --argjson ext "$line" '
      {crm_id: .id} +
      (
        .properties // {} |
        with_entries(.key = "crm_" + .key)
      ) +
      $ext
    ' >> "$MATCHED_FILE"
    matched=$(( matched + 1 ))
    echo "  [MATCH] $email → crm_id $crm_id"
  else
    echo "$line" >> "$UNMATCHED_FILE"
    unmatched=$(( unmatched + 1 ))
    echo "  [MISS]  $email"
  fi
done < "$INPUT_FILE"

echo ""
echo "Done."
echo "  Total:     $total"
echo "  Matched:   $matched → $MATCHED_FILE"
echo "  Unmatched: $unmatched → $UNMATCHED_FILE"
echo ""
echo "Next: review $UNMATCHED_FILE and either create new contacts or discard."
echo "      To write matched data back to CRM:"
echo "      cat $MATCHED_FILE | jq -c '{id: .crm_id, properties: {company: .company}}' \\"
echo "      | hubspot objects update --type contacts --dry-run"
