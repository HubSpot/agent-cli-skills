---
name: quote-to-cash
description: Build the product catalog, assemble quotes (line items + associations to deals), and track invoices and subscriptions through to revenue.
triggers:
  - "create product"
  - "product catalog"
  - "build a quote"
  - "create quote"
  - "line items"
  - "associate line items"
  - "outstanding invoices"
  - "overdue invoices"
  - "active subscriptions"
  - "quote to cash"
---

## Resources

| File | When to use |
|---|---|
| `resources/q2c-essentials.md` | Six-field cheat sheet, association directions, portal caveats for invoices/subscriptions/orders/carts. |

## Foundations

Read `bulk-operations/SKILL.md` first — JSONL piping, batch read, pagination, and the dry-run/digest/confirm flow for destructive ops live there. Reshape recipes (read → write payload) are in `bulk-operations/resources/json-patterns.md`.

`hubspot <command> --help` is the source of truth. Object types are plural (`products`, `line_items`, `quotes`, `invoices`, `subscriptions`). Never hardcode property tables — `hubspot properties list --type <type>` is one call away. Verify any enum value the agent is about to write with `hubspot properties get --type <type> --name <property>` and read `options[].value`.

Portal note: `invoices`, `subscriptions`, `orders`, `carts` show an empty `objectTypeId` in `hubspot objects types`. They work through `objects search`/`list` when the token has the matching scope (`invoices-read`, `subscriptions-read`, etc.) and 403 otherwise. CLI-created quotes are always `DRAFT`; approval routing, share links, PDF generation, and invoice creation usually require the HubSpot UI.

## 1. Create a product

```bash
hubspot objects create --type products \
  --property name="Enterprise License" \
  --property price=12000 \
  --property hs_sku=ENT-001
```

For a recurring product set `recurringbillingfrequency`; check the API enum values first with `hubspot properties get --type products --name recurringbillingfrequency --format json | jq -r '.options[].value'`. Bulk-import a catalog by piping JSONL of `{"properties":{...}}` to `hubspot objects create --type products --dry-run`.

## 2. Build a quote: line items → quote → associations

`objects create` emits one result line per stdin line, in input order. That lets you build line items, capture their IDs, and associate them to the new quote in three pipes — no per-record shell loop.

```bash
DEAL_ID=12345

# 1. Create the line items. items.jsonl holds {"name":..,"qty":..,"price":..,"product_id":..} per line.
jq -c '{properties:{
    name:.name, quantity:(.qty|tostring), price:(.price|tostring),
    hs_product_id:.product_id, hs_line_item_currency_code:"USD"
  }}' items.jsonl \
| hubspot objects create --type line_items > /tmp/lineitems.jsonl

# 2. Create the quote.
QUOTE_ID=$(hubspot objects create --type quotes \
  --property hs_title="Acme Corp - 2026" \
  --property hs_expiration_date=2026-06-30 \
  --property hs_currency=USD \
  --format json | jq -r '.data.id // .id')

# 3. Associate every new line item to the quote in one pipe.
jq -r '.id' /tmp/lineitems.jsonl \
| jq -cR --arg q "$QUOTE_ID" '{from:("quotes:" + $q), to:("line_items:" + .)}' \
| hubspot associations create

# 4. Link the quote to the deal.
hubspot associations create --from "deals:$DEAL_ID" --to "quotes:$QUOTE_ID"
```

Discount handling — `discount` is the writable percentage (`10` = 10% off). `hs_total_discount` is HubSpot-computed; do not set it. Verify with `hubspot properties get --type line_items --name hs_total_discount` (look for `modificationMetadata.readOnlyValue:true`) before relying on this in a portal you don't own.

Promote a quote out of `DRAFT` when ready to share:

```bash
hubspot objects update --type quotes <quote_id> --property hs_status=APPROVAL_NOT_NEEDED
```

Verify `hs_status` enum values for your portal: `hubspot properties get --type quotes --name hs_status --format json | jq -r '.options[].value'`.

## 3. Track invoices

The CLI reads invoice data and updates status; creation usually needs HubSpot Commerce + UI. Filter by `hs_invoice_status` and date.

```bash
# All outstanding invoices
hubspot objects search --type invoices \
  --filter "hs_invoice_status=OUTSTANDING" \
  --properties hs_number,hs_amount_billed,hs_balance,hs_due_date

# Past-due (overdue) invoices, dynamic date
hubspot objects search --type invoices \
  --filter "hs_due_date<$(date +%Y-%m-%d) AND hs_invoice_status!=PAID" \
  --properties hs_number,hs_due_date,hs_balance

# Invoices billed in the last 30 days
hubspot objects search --type invoices \
  --filter "hs_invoice_date>=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d)" \
  --properties hs_number,hs_amount_billed,hs_invoice_date
```

Verify the status enum the same way: `hubspot properties get --type invoices --name hs_invoice_status --format json | jq -r '.options[].value'`.

## 4. Track subscriptions

Same shape, filter on `hs_subscription_status`. Verify the enum values before writing the filter — do not hardcode `ACTIVE`/`CANCELLED`/`PAST_DUE`:

```bash
hubspot properties get --type subscriptions --name hs_subscription_status --format json \
  | jq -r '.options[].value'

# Then filter (case matters)
hubspot objects search --type subscriptions \
  --filter "hs_subscription_status=<value-from-above>" \
  --properties hs_mrr,hs_arr,hs_subscription_status

# Sum MRR across active subs
hubspot objects search --type subscriptions \
  --filter "hs_subscription_status=<active-value>" --format json \
  | jq '[.data[].properties.hs_mrr | select(. != null) | tonumber] | add'
```

## Known constraints

- `invoices`, `subscriptions`, `orders`, `carts` need the matching read scope on the active token; 403 means the user OAuth login or private-app token is missing the scope.
- Destructive ops (`objects delete` on products/quotes/line_items) often need a private-app token: `export HUBSPOT_ACCESS_TOKEN=<token>`. See `bulk-operations/SKILL.md` for the dry-run → digest → confirm flow before bulk-deleting catalog records.
- Quote share links, PDF generation, approval routing, and from-scratch invoice creation are UI-only — the CLI updates records but cannot send a quote to a customer.
- `hs_total_discount` on line items is read-only — set `discount` (percentage) instead.
