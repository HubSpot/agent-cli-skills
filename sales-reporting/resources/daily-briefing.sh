#!/bin/bash
# daily-briefing.sh
#
# Prints a formatted daily sales pipeline snapshot:
#   1. Deals closing in the next 7 days
#   2. Deals updated in the last 24 hours
#   3. New contacts created in the last 7 days
#   4. Open pipeline total by count and value
#   5. Top 5 open deals by value
#
# Usage:
#   ./daily-briefing.sh

set -euo pipefail

TODAY=$(date +%Y-%m-%d)

if [[ "$(uname)" == "Darwin" ]]; then
  NEXT_7=$(date -v+7d +%Y-%m-%d)
  YESTERDAY=$(date -v-1d +%Y-%m-%d)
  LAST_7=$(date -v-7d +%Y-%m-%d)
else
  NEXT_7=$(date -d '7 days' +%Y-%m-%d)
  YESTERDAY=$(date -d '1 day ago' +%Y-%m-%d)
  LAST_7=$(date -d '7 days ago' +%Y-%m-%d)
fi

sep() { printf '\n%s\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

echo "DAILY SALES BRIEFING — $TODAY"

# ── Open Pipeline Summary ─────────────────────────────────────────────────────
sep; echo "OPEN PIPELINE SUMMARY"

hubspot objects search --type deals \
  --filter "hs_is_closed!=true" \
  --properties amount,dealstage \
  --limit 100 \
| jq -rs '
  {
    count: length,
    value: ([.[].prop_amount | select(. != null and . != "") | tonumber] | add // 0 | round)
  }
  | "  Deals:  \(.count)",
    "  Value:  $\(.value)"
' -r

# ── Deals Closing Next 7 Days ─────────────────────────────────────────────────
sep; echo "CLOSING NEXT 7 DAYS ($TODAY → $NEXT_7)"

results=$(
  hubspot objects search --type deals \
    --filter "closedate>$TODAY AND closedate<$NEXT_7 AND hs_is_closed!=true" \
    --properties dealname,amount,closedate,hubspot_owner_id \
    --limit 20 2>/dev/null
)

if [[ -n "$results" ]]; then
  echo "$results" \
  | jq -r '"  \(.prop_closedate // "??")  $\(.prop_amount // "0" | tonumber | round)  \(.prop_dealname // "(no name)")"' \
  2>/dev/null | sort
else
  echo "  (none)"
fi

# ── Recently Updated Deals ────────────────────────────────────────────────────
sep; echo "DEALS UPDATED SINCE $YESTERDAY"

results=$(
  hubspot objects search --type deals \
    --filter "hs_lastmodifieddate>$YESTERDAY AND hs_is_closed!=true" \
    --properties dealname,amount,dealstage,hs_lastmodifieddate \
    --limit 10 2>/dev/null
)

if [[ -n "$results" ]]; then
  echo "$results" \
  | jq -r '"  \(.prop_hs_lastmodifieddate // "" | .[0:10])  \(.prop_dealname // "(no name)")  $\(.prop_amount // "0")"' \
  2>/dev/null
else
  echo "  (none)"
fi

# ── New Contacts This Week ────────────────────────────────────────────────────
sep; echo "NEW CONTACTS SINCE $LAST_7"

new_contacts=$(
  hubspot objects search --type contacts \
    --filter "createdate>$LAST_7" \
    --properties email,firstname,lastname,company,lifecyclestage \
    --limit 20 2>/dev/null
)

if [[ -n "$new_contacts" ]]; then
  count=$(echo "$new_contacts" | wc -l | tr -d ' ')
  echo "  $count new contacts"
  echo "$new_contacts" \
  | jq -r '"  \(.prop_firstname // "") \(.prop_lastname // "")  <\(.prop_email // "")>  \(.prop_company // "")"' \
  2>/dev/null
else
  echo "  (none)"
fi

# ── Top 5 Open Deals by Value ─────────────────────────────────────────────────
sep; echo "TOP 5 OPEN DEALS BY VALUE"

hubspot objects search --type deals \
  --filter "hs_is_closed!=true" \
  --properties dealname,amount,closedate,hubspot_owner_id \
  --limit 100 \
| jq -rs '
  sort_by(.prop_amount | select(. != null) | tonumber | . * -1)
  | .[0:5][]
  | "  $\(.prop_amount // "0" | tonumber | round)  \(.prop_dealname // "(no name)")  (close: \(.prop_closedate // "TBD"))"
' -r 2>/dev/null

sep
echo "End of briefing."
