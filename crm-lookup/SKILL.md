---
name: crm-lookup
description: Find a specific CRM record by ID, email, domain, or name fragment, and traverse associations for the full account picture.
triggers:
  - "find contact"
  - "find contact by email"
  - "find company by domain"
  - "look up deal"
  - "contacts at this company"
  - "deals for this contact"
  - "find record"
---

## Source of truth

`hubspot <command> --help` is authoritative. Read [`bulk-operations/SKILL.md`](../bulk-operations/SKILL.md) first — it owns JSONL piping, pagination, batch-get-via-stdin, and the safety flow for any write that comes after a lookup. This skill is read-only.

## Pick properties from the live schema

Schemas drift. Run `hubspot properties list --type <type>` for the live set. First-pass `--properties` for a brief:

| Object | `--properties` |
|---|---|
| contacts | `email,firstname,lastname,company,phone,lifecyclestage,hubspot_owner_id` |
| companies | `name,domain,industry,annualrevenue,numberofemployees,hubspot_owner_id` |
| deals | `dealname,amount,dealstage,closedate,hubspot_owner_id,hs_is_closed_won` |
| tickets | `subject,hs_pipeline_stage,hs_ticket_priority,hubspot_owner_id` |

Contact ad/campaign attribution lives on `hs_analytics_*` (e.g. `hs_analytics_source`, `hs_analytics_source_data_1`/`_2`, `hs_analytics_first_touch_converting_campaign`, `hs_analytics_last_touch_converting_campaign`). Full list: `hubspot properties list --type contacts | grep hs_analytics_`.

## 1. Lookup by ID

Up to ~100 IDs in a single batch call:

```bash
hubspot objects get --type contacts 12345 67890 23456 --properties email,firstname,lastname,company,phone,lifecyclestage
```

## 2. Find one by email / domain (exact match)

`email`/`domain` are exact-match — normalize to lowercase. Multiple `--filter` flags are OR'd.

```bash
hubspot objects search --type contacts --filter "email=jane@acme.com" \
  --properties email,firstname,lastname,company,lifecyclestage,hubspot_owner_id

hubspot objects search --type companies --filter "domain=acme.com" \
  --properties name,domain,industry,annualrevenue,hubspot_owner_id

# OR — multiple emails in one call
hubspot objects search --type contacts \
  --filter "email=alice@acme.com" --filter "email=bob@acme.com" --properties email,firstname
```

## 3. Find by partial name (token + client-side narrowing)

`~` is CONTAINS_TOKEN — matches whole space-separated words. `dealname~acme` finds "Acme Renewal" but **not** "AcmeCorp". For substring, pipe to `jq`. There's no full-text search across all fields — pick the property.

```bash
hubspot objects search --type deals --filter "dealname~acme" --properties dealname,amount,dealstage \
| jq -c 'select(.properties.dealname | ascii_downcase | contains("acme corp"))'
```

## 4. Find all associated records (two CLI calls, not xargs)

Pattern: `associations list` → `jq -c '{id}'` → `objects get` batch. **Never** `xargs -I{} hubspot objects get …` — that spawns one process per record. Use **plural** in `--from` (`contacts:`, `companies:`, `deals:`); `--help` shows singular but only plural avoids a warning.

```bash
# All contacts at a company
hubspot associations list --from companies:67890 --to contacts \
| jq -c '{id}' \
| hubspot objects get --type contacts --properties email,firstname,lastname,jobtitle

# Open deals for a contact (filter client-side; "open" varies by pipeline)
hubspot associations list --from contacts:12345 --to deals | jq -c '{id}' \
| hubspot objects get --type deals --properties dealname,amount,dealstage,hs_is_closed \
| jq -c 'select(.properties.hs_is_closed != "true")'
```

## 5. Get a record plus its associations

```bash
contact_id=12345
hubspot objects get --type contacts $contact_id --properties email,firstname,lastname,company,lifecyclestage

# Associated company (usually one)
hubspot associations list --from contacts:$contact_id --to companies | jq -c '{id}' | head -1 \
| hubspot objects get --type companies --properties name,domain,industry,annualrevenue

# Associated deals
hubspot associations list --from contacts:$contact_id --to deals | jq -c '{id}' \
| hubspot objects get --type deals --properties dealname,amount,dealstage,closedate
```

## Constraints

- Search returns ≤100 per page. For more, use the pagination loop in `bulk-operations/SKILL.md`.
- `~` is token-based; substring filtering happens in `jq` after the search.
- If the lookup feeds a write (update, delete, merge), follow the `--dry-run` → digest → `--confirm` flow in `bulk-operations/SKILL.md`.
