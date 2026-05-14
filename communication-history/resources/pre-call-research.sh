#!/bin/bash
# pre-call-research.sh
#
# Assembles a complete pre-call brief for a contact: properties, company,
# open deals, and recent activity history.
#
# Usage:
#   CONTACT_ID=<id> ./pre-call-research.sh
#
# Example:
#   CONTACT_ID=12345 ./pre-call-research.sh

set -euo pipefail

CONTACT_ID="${CONTACT_ID:?Set CONTACT_ID to the HubSpot contact ID}"
ACTIVITY_LIMIT="${ACTIVITY_LIMIT:-10}"

sep() { printf '\n%s\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

echo "PRE-CALL BRIEF — Contact $CONTACT_ID"
echo "Generated: $(date '+%Y-%m-%d %H:%M')"

# ── Contact ───────────────────────────────────────────────────────────────────
sep; echo "CONTACT"

hubspot objects get --type contacts "$CONTACT_ID" \
  --properties email,firstname,lastname,company,phone,jobtitle,lifecyclestage,hs_lead_status,hubspot_owner_id \
| jq -r '
  "  Name:       \(.prop_firstname // "") \(.prop_lastname // "")",
  "  Email:      \(.prop_email // "(none)")",
  "  Phone:      \(.prop_phone // "(none)")",
  "  Title:      \(.prop_jobtitle // "(none)")",
  "  Company:    \(.prop_company // "(none)")",
  "  Stage:      \(.prop_lifecyclestage // "(none)")",
  "  Lead status:\(.prop_hs_lead_status // "(none)")"
'

# ── Associated Company ────────────────────────────────────────────────────────
sep; echo "COMPANY"

company_id=$(
  hubspot associations list --from contacts:"$CONTACT_ID" --to companies --format jsonl 2>/dev/null \
  | jq -r '.id' | head -1
)

if [[ -n "$company_id" ]]; then
  hubspot objects get --type companies "$company_id" \
    --properties name,domain,industry,annualrevenue,numberofemployees,city,country \
  | jq -r '
    "  Name:       \(.prop_name // "(none)")",
    "  Domain:     \(.prop_domain // "(none)")",
    "  Industry:   \(.prop_industry // "(none)")",
    "  Revenue:    \(.prop_annualrevenue // "(none)")",
    "  Employees:  \(.prop_numberofemployees // "(none)")",
    "  Location:   \((.prop_city // "") + (if .prop_country then ", " + .prop_country else "" end))"
  '
else
  echo "  (no associated company)"
fi

# ── Open Deals ────────────────────────────────────────────────────────────────
sep; echo "OPEN DEALS"

deal_ids=$(
  hubspot associations list --from contacts:"$CONTACT_ID" --to deals --format jsonl 2>/dev/null \
  | jq -r '.id'
)

if [[ -n "$deal_ids" ]]; then
  echo "$deal_ids" \
  | xargs -I{} hubspot objects get --type deals {} \
      --properties dealname,amount,dealstage,closedate,hs_is_closed \
  | jq -rc 'select(.prop_hs_is_closed != "true")
    | "  \(.prop_dealname // "(no name)")  |  $\(.prop_amount // "0")  |  close: \(.prop_closedate // "TBD")"'
else
  echo "  (no associated deals)"
fi

# ── Recent Activity ───────────────────────────────────────────────────────────
sep; echo "RECENT ACTIVITY (last $ACTIVITY_LIMIT)"

hubspot activities list --contact "$CONTACT_ID" --limit "$ACTIVITY_LIMIT" \
| jq -r '"  \(.timestamp[0:10])  \(.type | .[0:8] | ascii_downcase | ltrimstr("ing"))  \(.title)"' \
2>/dev/null || echo "  (no activities found)"

sep
echo "End of brief."
