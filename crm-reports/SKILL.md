---
name: crm-reports
description: Run server-side SQL reports against HubSpot CRM data from the terminal. Use when the user needs aggregations, cross-object queries, time series, or GROUP BY analysis. Prefer this over crm-query when the request involves counting/summing across a dimension, time bucketing, or cross-object filters in a single call.
triggers:
  - "reports create"
  - "create report"
  - "sql report"
  - "run a report"
  - "group by stage"
  - "group by owner"
  - "count by"
  - "sum by"
  - "revenue by month"
  - "deals by stage"
  - "contacts by lifecycle"
  - "time series"
  - "cross-object filter"
  - "deals at retail companies"
---

## Overview

`hubspot reports create` executes a SQL query server-side against HubSpot CRM data and streams back the result set. It supports aggregations, GROUP BY, DATE_TRUNC time bucketing, and cross-object filters — capabilities that require multi-step workarounds with `hubspot objects search`.

For full SQL syntax, see [`resources/sql-syntax.md`](resources/sql-syntax.md). `hubspot reports create --help` is authoritative on flags.

## Command

```bash
hubspot reports create "<sql>" --intent "<short description>"
```

- `sql` (required, positional): A valid HubSpot CRM SQL query.
- `--intent` (required): A short human-readable label for what the query does (e.g. "Deals by stage"). Used for display and logging — does not affect execution.
- `--format` (optional): `jsonl` (default), `json`, or `table`.

## When to use this vs `crm-query`

| Scenario | Use |
|---|---|
| Aggregate / GROUP BY (count, sum, avg by a dimension) | `crm-reports` |
| Time series (revenue by month, contacts by week) | `crm-reports` |
| Cross-object filter in a single call | `crm-reports` |
| Simple filter + list of records | `crm-query` |
| Basic lookup by ID, email, name | `crm-lookup` |
| Pipeline snapshots, win/loss | `sales-reporting` |

## Examples

**Deals by stage (count + value):**
```bash
hubspot reports create \
  "SELECT dealstage, COUNT(*), SUM(amount_in_home_currency) FROM DEAL GROUP BY dealstage" \
  --intent "Deals by stage"
```

**Contacts created this month:**
```bash
hubspot reports create \
  "SELECT COUNT(*) FROM CONTACT WHERE CURRENT_PERIOD(createdate, 'MONTH')" \
  --intent "Contacts created this month"
```

**Revenue by close month (won deals, last 6 months):**
```bash
hubspot reports create \
  "SELECT DATE_TRUNC(closedate, 'MONTH'), SUM(amount_in_home_currency) FROM DEAL WHERE hs_is_closed_won = 'true' AND PREVIOUS_PERIOD(closedate, 'MONTH', 6, false) GROUP BY DATE_TRUNC(closedate, 'MONTH')" \
  --intent "Revenue by close month"
```

**Deals at retail companies (cross-object filter):**
```bash
hubspot reports create \
  "SELECT dealname, amount_in_home_currency, dealstage FROM DEAL WHERE COMPANY.industry = 'RETAIL'" \
  --intent "Deals at retail companies"
```

**Open deals by owner:**
```bash
hubspot reports create \
  "SELECT hubspot_owner_id, COUNT(*), SUM(amount_in_home_currency) FROM DEAL WHERE hs_is_closed != 'true' GROUP BY hubspot_owner_id" \
  --intent "Open deals by owner"
```

## Key rules

- Always discover portal-specific values (stage IDs, owner IDs, enum values) with `crm-query` before writing WHERE conditions that reference them.
- `amount_in_home_currency` is the normalised deal value field; prefer it over `amount` for aggregations.
- Stage IDs are portal-specific strings — get them with `hubspot pipelines stages --type deals` before using in WHERE.
- Owner IDs are numeric strings — resolve names with `hubspot owners list` after the query returns.
- `hs_is_closed_won` and `hs_is_closed` filter values must be quoted strings: `= 'true'`, `!= 'true'`.
- Max 2 different associated object types per query when using cross-object filters.

## Known limitations

- `SELECT DISTINCT`, `COUNT(DISTINCT x)`, `JOIN`, `UNION`, subqueries, CTEs, and `HAVING` are not supported.
- `AS` aliases are not supported — column names in the result match the property name.
- `LIKE`/`ILIKE` is not supported — use `KEYWORD_SEARCH_QUERY('term', 'property')` for text search.
- `CASE WHEN`, `IF()`, string functions (`CONCAT`, `UPPER`) are not supported.
- Website traffic analytics (`web_analytics.*`) and marketing email metrics (`EXT_EMAIL_*`) are not available via this command.
