# Deal Properties Reference

## Standard Deal Properties

| Property | Type | Writable | Notes |
|---|---|---|---|
| `dealname` | string | yes | Required on creation |
| `pipeline` | string | yes | Pipeline ID — **portal-specific, see warning below** |
| `dealstage` | string | yes | Stage ID — **portal-specific, see warning below** |
| `amount` | number | yes | Deal value; use `0` if unknown at creation time |
| `closedate` | string | yes | Format: `YYYY-MM-DD` (e.g. `2025-09-30`) |
| `hubspot_owner_id` | string | yes | Numeric owner ID — resolve at runtime via `hubspot owners list` |
| `dealtype` | enumeration | yes | `newbusiness` or `existingbusiness` |
| `description` | string | yes | Free-text deal description |
| `hs_deal_stage_probability` | number | **read-only** | Set by HubSpot based on stage configuration; cannot be set directly |
| `hs_is_closed` | boolean | **read-only** | `true` when the deal is in a closed stage (won or lost) |
| `hs_is_closed_won` | boolean | **read-only** | `true` only when the deal is in a closed-won stage |
| `notes_last_contacted` | string | yes | Date of last contact note; ISO 8601 |
| `hs_last_sales_activity_date` | string | **read-only** | Updated automatically by HubSpot on sales activity |
| `createdate` | string | **read-only** | Set by HubSpot on creation; ISO 8601 |
| `num_associated_contacts` | number | **read-only** | Count of associated contacts |
| `num_associated_companies` | number | **read-only** | Count of associated companies |

## `dealtype` Enum Values

| Value | Meaning |
|---|---|
| `newbusiness` | New logo / first-time customer |
| `existingbusiness` | Expansion, renewal, or upsell to existing customer |

---

> **WARNING: `pipeline` and `dealstage` are portal-specific IDs — never hardcode them.**
>
> Every HubSpot portal has its own pipeline and stage IDs. An ID that works in one portal will silently fail or resolve to the wrong stage in another. Always discover IDs at runtime before creating or filtering deals:
>
> ```bash
> # List all pipelines for the current portal
> hubspot pipelines list --object deals --format table
>
> # Get all stages for a specific pipeline (use the pipeline ID from above)
> hubspot pipelines stages --object deals --pipeline <pipeline_id> --format table
>
> # JSONL format for use in scripts
> hubspot pipelines stages --object deals --pipeline <pipeline_id> --format jsonl
> ```
>
> Capture the `id` field from the stages output and use those values for `pipeline` and `dealstage` properties.

## Filtering on Read-Only Boolean Properties

The read-only booleans `hs_is_closed` and `hs_is_closed_won` are useful for search filters even though they cannot be written:

```bash
# All open deals (not in a closed stage)
hubspot objects search --type deals \
  --filter "hs_is_closed!=true" \
  --properties dealname,dealstage,amount,closedate

# All closed-won deals
hubspot objects search --type deals \
  --filter "hs_is_closed_won=true" \
  --properties dealname,amount,closedate,hubspot_owner_id
```
