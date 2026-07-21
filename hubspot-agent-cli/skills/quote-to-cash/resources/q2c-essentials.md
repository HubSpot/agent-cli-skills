# Quote-to-cash essentials

Minimal field reference — for the full property list run
`hubspot properties list --type products|line_items|quotes|invoices|subscriptions`.
For any enum, verify the API values with
`hubspot properties get --type <type> --name <property>` and read the `options[].value` field.

## The six fields that matter

| Object | Field | Notes |
|---|---|---|
| `products` | `name` | Required on create. |
| `products` | `price` | Unit price. `hs_sku`, `description`, `recurringbillingfrequency` are optional. |
| `line_items` | `name`, `quantity` | Both required. `quantity` is a number. |
| `line_items` | `price` | Overrides the product price for this quote. |
| `line_items` | `hs_product_id` | Links the line item back to a `products` record (omit for ad-hoc items). |
| `quotes` | `hs_title` | Required. CLI-created quotes are always `DRAFT` until status is moved. |

## Discount fields on line items

`discount` is the writable percentage (e.g. `10` for 10% off). `hs_total_discount` is
HubSpot-computed and should not be set by hand. Confirm in your portal before relying on
this — `hubspot properties get --type line_items --name discount` and
`... --name hs_total_discount` will show `modificationMetadata.readOnlyValue`.

## Associations

Plural names both sides. The three you actually need:

```bash
hubspot associations create --from quotes:<quote_id> --to line_items:<line_item_id>
hubspot associations create --from deals:<deal_id>   --to quotes:<quote_id>
hubspot associations create --from quotes:<quote_id> --to contacts:<contact_id>   # optional
```

Pipe JSONL `{"from":"quotes:1","to":"line_items:2"}` to `hubspot associations create`
for bulk.

## Portal caveats

- `invoices` and `subscriptions` show empty `objectTypeId` in `hubspot objects types`.
  They are queryable through `objects search`/`list` but require the matching scopes
  (`invoices-read`, `subscriptions-read`) on the active token. Expect a 403 otherwise.
- `orders` and `carts` are listed but rarely populated unless HubSpot Commerce is on.
- Quote PDF/share-link generation, approval routing, and invoice creation usually need
  the HubSpot UI — the CLI handles records and status updates only.
