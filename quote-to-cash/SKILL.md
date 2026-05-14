---
name: quote-to-cash
description: Get paid faster by creating product catalog entries, building quotes with line items, associating them to deals, and tracking outstanding and overdue invoices.
triggers:
  - "create quote"
  - "invoice"
  - "get paid"
  - "quote to cash"
  - "line items"
  - "product catalog"
  - "outstanding invoices"
  - "create product"
  - "build a quote"
  - "overdue invoices"
---

## Resources

| File | When to use |
|---|---|
| `resources/product-and-quote-properties.md` | Property reference for products, line items, quotes, and invoices — including all status enum values and the association requirements between them |
| `resources/quote-creation-workflow.sh` | End-to-end script that creates line items, builds a quote, associates everything, and links to a deal — accepts product IDs and quantities as inputs |

## Context
The quote-to-cash process covers creating products in the catalog, building quotes with line items, associating quotes to deals for approval, and tracking invoices through to payment. Quotes are created as Drafts from the CLI — approval workflows and quote sharing must be completed in the HubSpot UI.

## Property Reference — Products

| Property | Type | Notes |
|---|---|---|
| name | string | Required |
| description | string | |
| price | number | |
| hs_sku | string | SKU identifier |
| hs_cost_of_goods_sold | number | |
| recurringbillingfrequency | enumeration | monthly, quarterly, per_six_months, annually, per_two_years, per_three_years |

## Property Reference — Line Items

| Property | Type | Notes |
|---|---|---|
| name | string | Required |
| quantity | number | Required |
| price | number | Unit price |
| hs_product_id | string | Links to a Product record |
| discount | number | Discount percentage |
| hs_line_item_currency_code | string | e.g., USD, EUR |
| hs_total_discount | number | Read-only |

## Property Reference — Quotes

| Property | Type | Notes |
|---|---|---|
| hs_title | string | Required |
| hs_expiration_date | string | YYYY-MM-DD |
| hs_status | enumeration | DRAFT, APPROVAL_NOT_NEEDED, PENDING_APPROVAL, APPROVED, REJECTED, ARCHIVED |
| hs_currency | string | e.g., USD |

## Property Reference — Invoices

| Property | Type | Notes |
|---|---|---|
| hs_invoice_status | enumeration | DRAFT, OUTSTANDING, PAID, VOIDED, OVERDUE |
| hs_due_date | string | YYYY-MM-DD |
| hs_number | string | Invoice number |
| hs_amount_billed | number | |
| hs_balance | number | Remaining balance |

## Key Workflows

### Create a Product in the Catalog

```bash
hubspot objects create --type products \
  --property name="Enterprise License" \
  --property description="Annual enterprise software license — unlimited seats" \
  --property price=12000 \
  --property hs_sku="ENT-001" \
  --property recurringbillingfrequency=annually
```

### Find Products in the Catalog

```bash
# List all products
hubspot objects list --type products --properties name,price,hs_sku

# Search for a specific product
hubspot objects search --type products \
  --filter "name~Enterprise" \
  --properties name,price,hs_sku,recurringbillingfrequency
```

### Full Quote Creation Workflow

```bash
# Step 1: create the line item (can reference a product or be standalone)
hubspot objects create --type line_items \
  --property name="Enterprise License" \
  --property quantity=1 \
  --property price=12000 \
  --property hs_product_id=<product_id> \
  --property hs_line_item_currency_code=USD
# Note the returned line_item ID

# Step 2: create the quote
hubspot objects create --type quotes \
  --property hs_title="Acme Corp Enterprise - 2025" \
  --property hs_expiration_date=2025-06-30 \
  --property hs_status=DRAFT \
  --property hs_currency=USD
# Note the returned quote ID

# Step 3: associate line item to quote
hubspot associations create --from quotes:<quote_id> --to line_items:<line_item_id>

# Step 4: associate quote to deal
hubspot associations create --from deals:<deal_id> --to quotes:<quote_id>
```

### Create a Quote with Multiple Line Items

```bash
# Create line item 1
hubspot objects create --type line_items \
  --property name="Enterprise License" \
  --property quantity=1 \
  --property price=12000 \
  --property hs_product_id=<product_id_1>

# Create line item 2
hubspot objects create --type line_items \
  --property name="Professional Services" \
  --property quantity=10 \
  --property price=250 \
  --property hs_line_item_currency_code=USD

# Create the quote
hubspot objects create --type quotes \
  --property hs_title="Acme Corp - Enterprise + Services" \
  --property hs_expiration_date=2025-06-30 \
  --property hs_status=DRAFT \
  --property hs_currency=USD

# Associate both line items to the quote
hubspot associations create --from quotes:<quote_id> --to line_items:<line_item_1_id>
hubspot associations create --from quotes:<quote_id> --to line_items:<line_item_2_id>

# Associate quote to deal
hubspot associations create --from deals:<deal_id> --to quotes:<quote_id>
```

### Find All Outstanding Invoices

```bash
hubspot objects search --type invoices \
  --filter "hs_invoice_status=OUTSTANDING" \
  --properties hs_number,hs_amount_billed,hs_balance,hs_due_date
```

### Find Overdue Invoices

```bash
hubspot objects search --type invoices \
  --filter "hs_invoice_status=OVERDUE" \
  --properties hs_number,hs_due_date,hs_balance,hs_amount_billed
```

### Check Active Subscription MRR

```bash
# Find all active subscriptions
hubspot objects search --type subscriptions \
  --filter "hs_subscription_status=ACTIVE" \
  --properties hs_mrr,hs_arr,hs_subscription_status

# Total MRR across all active subscriptions
hubspot objects search --type subscriptions \
  --filter "hs_subscription_status=ACTIVE" \
  --format json \
  | jq '[.data[].properties.hs_mrr | tonumber] | add'
```

### Get All Quotes for a Deal

```bash
hubspot associations list --from deals:<deal_id> --to quotes --format jsonl
```

### Update a Quote's Expiration Date

```bash
hubspot objects update --type quotes <quote_id> \
  --property hs_expiration_date=2025-09-30
```

### Mark a Quote as Ready for Approval

```bash
hubspot objects update --type quotes <quote_id> \
  --property hs_status=APPROVAL_NOT_NEEDED
```

## Known Limitations
- Quote creation via CLI always creates a Draft. Approval workflows (routing the quote for sign-off) and quote sharing (sending the quote to the customer via a shareable link) must be completed in the HubSpot UI.
- Full invoice creation typically requires HubSpot Commerce to be configured on your portal. The CLI can read invoice data and update the status, but creating invoices from scratch may require portal-level setup.
- Deleting records (products, quotes, line items) requires a private app token: `export HUBSPOT_ACCESS_TOKEN=<token>`. User OAuth login cannot perform deletes.
- Line item `hs_total_discount` is read-only and calculated by HubSpot. Set the `discount` field (percentage) to apply a discount.
