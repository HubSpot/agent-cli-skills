#!/bin/bash
# quote-creation-workflow.sh
#
# Creates a complete quote with line items and associates it to a deal.
#
# Usage:
#   DEAL_ID=<id> PRODUCT_IDS="<id1>:<qty1> <id2>:<qty2>" ./quote-creation-workflow.sh
#
# Examples:
#   DEAL_ID=12345 PRODUCT_IDS="67890:1" ./quote-creation-workflow.sh
#   DEAL_ID=12345 PRODUCT_IDS="67890:1 11111:5" QUOTE_TITLE="Acme Corp - Enterprise 2025" ./quote-creation-workflow.sh
#   DEAL_ID=12345 PRODUCT_IDS="67890:2" DISCOUNT=10 CURRENCY=EUR ./quote-creation-workflow.sh
#
# Required env vars:
#   DEAL_ID      — HubSpot deal ID to associate the quote to
#   PRODUCT_IDS  — space-separated list of "product_id:quantity" pairs
#                  at least one is required; or use STANDALONE_ITEMS instead
#
# Optional env vars:
#   QUOTE_TITLE       — quote title (default: "Quote - YYYY-MM-DD")
#   EXPIRATION_DATE   — YYYY-MM-DD (default: 30 days from today)
#   CURRENCY          — ISO 4217 code (default: USD)
#   DISCOUNT          — discount percentage to apply to all line items (default: 0)
#   QUOTE_STATUS      — initial quote status (default: DRAFT)
#   DRY_RUN           — set to "true" to print what would be done without creating records

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
DEAL_ID="${DEAL_ID:?Set DEAL_ID to the HubSpot deal ID}"
PRODUCT_IDS="${PRODUCT_IDS:-}"
QUOTE_TITLE="${QUOTE_TITLE:-Quote - $(date +%Y-%m-%d)}"
CURRENCY="${CURRENCY:-USD}"
DISCOUNT="${DISCOUNT:-0}"
QUOTE_STATUS="${QUOTE_STATUS:-DRAFT}"
DRY_RUN="${DRY_RUN:-false}"

# Compute expiration date (30 days from today)
if [[ -z "${EXPIRATION_DATE:-}" ]]; then
  if [[ "$(uname)" == "Darwin" ]]; then
    EXPIRATION_DATE=$(date -v+30d +%Y-%m-%d)
  else
    EXPIRATION_DATE=$(date -d "30 days" +%Y-%m-%d)
  fi
fi

echo "========================================"
echo "  Quote Creation Workflow"
echo "========================================"
echo "  Deal ID:         $DEAL_ID"
echo "  Quote title:     $QUOTE_TITLE"
echo "  Currency:        $CURRENCY"
echo "  Expiration:      $EXPIRATION_DATE"
echo "  Status:          $QUOTE_STATUS"
echo "  Discount:        $DISCOUNT%"
echo "  Dry run:         $DRY_RUN"
echo ""

LINE_ITEM_IDS=()

# ── Step 1: Look up products and create line items ────────────────────────────
echo "----------------------------------------"
echo "Step 1: Create line items"
echo "----------------------------------------"

if [[ -z "$PRODUCT_IDS" ]]; then
  echo "ERROR: Set PRODUCT_IDS as 'product_id:quantity' pairs separated by spaces." >&2
  echo "  Example: PRODUCT_IDS=\"67890:1 11111:5\"" >&2
  exit 1
fi

POSITION=1

for pair in $PRODUCT_IDS; do
  product_id="${pair%%:*}"
  quantity="${pair##*:}"

  echo "  Fetching product $product_id ..."

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN] Would create line item: product_id=$product_id quantity=$quantity"
    LINE_ITEM_IDS+=("dry-run-line-item-$product_id")
    POSITION=$(( POSITION + 1 ))
    continue
  fi

  # Fetch the product to get its name and price
  product_json=$(
    hubspot objects get --type products "$product_id" \
      --properties name,price,hs_sku,recurringbillingfrequency \
      2>/dev/null
  )

  product_name=$(echo "$product_json" | jq -r '.properties.name // "Product"')
  product_price=$(echo "$product_json" | jq -r '.properties.price // "0"')

  echo "  Product: $product_name (price: $product_price $CURRENCY)"

  # Build line item create arguments
  line_item_args=(
    --property "name=$product_name"
    --property "quantity=$quantity"
    --property "price=$product_price"
    --property "hs_product_id=$product_id"
    --property "hs_line_item_currency_code=$CURRENCY"
    --property "hs_position_on_quote=$POSITION"
  )

  if [[ "$DISCOUNT" != "0" ]]; then
    line_item_args+=(--property "discount=$DISCOUNT")
  fi

  line_item_id=$(
    hubspot objects create --type line_items \
      "${line_item_args[@]}" \
      --format json \
    | jq -r '.data.id // .id'
  )

  if [[ -z "$line_item_id" || "$line_item_id" == "null" ]]; then
    echo "  ERROR: Failed to create line item for product $product_id" >&2
    exit 1
  fi

  echo "  Created line item ID: $line_item_id"
  LINE_ITEM_IDS+=("$line_item_id")
  POSITION=$(( POSITION + 1 ))
done

echo ""

# ── Step 2: Create the quote ──────────────────────────────────────────────────
echo "----------------------------------------"
echo "Step 2: Create the quote"
echo "----------------------------------------"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY RUN] Would create quote:"
  echo "  Title:      $QUOTE_TITLE"
  echo "  Currency:   $CURRENCY"
  echo "  Expiration: $EXPIRATION_DATE"
  echo "  Status:     $QUOTE_STATUS"
  QUOTE_ID="dry-run-quote-id"
else
  QUOTE_ID=$(
    hubspot objects create --type quotes \
      --property "hs_title=$QUOTE_TITLE" \
      --property "hs_expiration_date=$EXPIRATION_DATE" \
      --property "hs_status=$QUOTE_STATUS" \
      --property "hs_currency=$CURRENCY" \
      --format json \
    | jq -r '.data.id // .id'
  )

  if [[ -z "$QUOTE_ID" || "$QUOTE_ID" == "null" ]]; then
    echo "ERROR: Failed to create quote" >&2
    exit 1
  fi
fi

echo "Created quote ID: $QUOTE_ID"
echo ""

# ── Step 3: Associate line items to the quote ─────────────────────────────────
echo "----------------------------------------"
echo "Step 3: Associate line items to quote $QUOTE_ID"
echo "----------------------------------------"

for line_item_id in "${LINE_ITEM_IDS[@]}"; do
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would associate line_items:$line_item_id -> quotes:$QUOTE_ID"
  else
    echo "  Associating line item $line_item_id ..."
    hubspot associations create \
      --from "quotes:$QUOTE_ID" \
      --to "line_items:$line_item_id"
    echo "  Associated."
  fi
done

echo ""

# ── Step 4: Associate the quote to the deal ───────────────────────────────────
echo "----------------------------------------"
echo "Step 4: Associate quote to deal $DEAL_ID"
echo "----------------------------------------"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[DRY RUN] Would associate deals:$DEAL_ID -> quotes:$QUOTE_ID"
else
  hubspot associations create \
    --from "deals:$DEAL_ID" \
    --to "quotes:$QUOTE_ID"
  echo "Associated quote $QUOTE_ID to deal $DEAL_ID."
fi

echo ""

# ── Output summary ────────────────────────────────────────────────────────────
echo "========================================"
echo "  Done"
echo "========================================"
echo "  Quote ID:        $QUOTE_ID"
echo "  Deal ID:         $DEAL_ID"
echo "  Line items:      ${#LINE_ITEM_IDS[@]}"
echo "  Status:          $QUOTE_STATUS"
echo ""

if [[ "$DRY_RUN" != "true" ]]; then
  echo "Next steps:"
  echo "  1. Verify the quote in HubSpot:"
  echo "     hubspot objects get --type quotes $QUOTE_ID --properties hs_title,hs_status,hs_expiration_date,hs_currency"
  echo ""
  echo "  2. Review all line items on the quote:"
  echo "     hubspot associations list --from quotes:$QUOTE_ID --to line_items --format jsonl"
  echo ""
  echo "  3. When ready to send, update the quote status:"
  echo "     hubspot objects update --type quotes $QUOTE_ID --property hs_status=APPROVAL_NOT_NEEDED"
  echo ""
  echo "  4. Sharing the quote link and PDF download require the HubSpot UI."
fi
