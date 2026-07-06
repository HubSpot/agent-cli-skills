# HubSpot CRM SQL Syntax Reference

This is the SQL dialect accepted by `hubspot reports create`. It queries HubSpot CRM data directly server-side.

## Basic query shape

```sql
SELECT property1, property2, ...
FROM OBJECT_TYPE
[WHERE condition]
[GROUP BY dimension]
[ORDER BY expression [ASC|DESC]]
[LIMIT n]
[OFFSET n]
```

`FROM` targets: `CONTACT`, `DEAL`, `COMPANY`, `TICKET`, `QUOTE`, custom object API names (e.g. `p1234567_my_object`), and event types (`e_*`, `pe<portalId>_*`).

`SELECT *` is supported but returns all properties — prefer explicit lists for large objects.

## WHERE operators

| Operator | Applies to | Example |
|---|---|---|
| `=`, `!=` | all types | `dealstage = 'closedwon'` |
| `<`, `<=`, `>`, `>=` | numbers, dates | `amount > 10000` |
| `IN (...)` | strings, enums | `dealstage IN ('closedwon', 'closedlost')` |
| `NOT IN (...)` | strings, enums | `lifecyclestage NOT IN ('subscriber')` |
| `BETWEEN x AND y` | numbers, dates | `createdate BETWEEN '2025-01-01' AND '2025-12-31'` |
| `IS NULL` / `IS NOT NULL` | all | `closedate IS NOT NULL` |
| `AND`, `OR` | logical | `amount > 1000 AND hs_is_closed != 'true'` |
| `KEYWORD_SEARCH_QUERY('term', 'prop')` | text | `KEYWORD_SEARCH_QUERY('enterprise', 'dealname')` |

Note: boolean property values are strings in HubSpot — use `= 'true'`, `!= 'true'`.

## Aggregation functions

`COUNT(*)`, `SUM(property)`, `AVG(property)`, `MIN(property)`, `MAX(property)`, `MEDIAN(property)`

Aggregations require a `GROUP BY` clause (or `SELECT COUNT(*)` with no `GROUP BY` for a total).

```sql
SELECT dealstage, COUNT(*), SUM(amount_in_home_currency)
FROM DEAL
GROUP BY dealstage
ORDER BY SUM(amount_in_home_currency) DESC
```

## GROUP BY

Group by one or more dimensions:

```sql
GROUP BY dealstage, hubspot_owner_id
```

Time bucketing with `DATE_TRUNC`:

```sql
GROUP BY DATE_TRUNC(createdate, 'MONTH')
```

Intervals: `DAY`, `WEEK`, `MONTH`, `QUARTER`, `YEAR`

## Date period functions

Use in WHERE to express relative time windows (only one per query):

| Function | Meaning |
|---|---|
| `CURRENT_PERIOD(prop, 'UNIT')` | Current calendar unit (e.g. this month) |
| `CURRENT_PERIOD_SO_FAR(prop, 'UNIT')` | Current unit up to now |
| `PREVIOUS_PERIOD(prop, 'UNIT', count, isFiscal)` | Last N units |
| `NEXT_PERIOD(prop, 'UNIT', count, isFiscal)` | Next N units |

Units: `DAY`, `WEEK`, `MONTH`, `QUARTER`, `YEAR`

```sql
-- This month
WHERE CURRENT_PERIOD(createdate, 'MONTH')

-- Last 3 months
WHERE PREVIOUS_PERIOD(closedate, 'MONTH', 3, false)
```

## Cross-object filters

Filter the primary object by a property on an associated object (max 2 associated types per query):

```sql
-- Deals at retail companies
WHERE COMPANY.industry = 'RETAIL'

-- Contacts with at least one associated deal
WHERE associations.DEAL IS NOT NULL
```

## Pagination

Use `LIMIT` and `OFFSET` for large result sets. The response includes a `hasMore` field when more pages exist.

## Unsupported syntax (will fail)

- `SELECT DISTINCT` or `COUNT(DISTINCT x)`
- `JOIN`, `UNION`, subqueries, CTEs (`WITH ...`)
- `AS` column aliases
- `LIKE` / `ILIKE` (use `KEYWORD_SEARCH_QUERY` instead)
- `HAVING`
- `CASE WHEN`, `IF()`, `IIF()`
- String functions: `CONCAT`, `UPPER`, `RIGHT`, etc.
- Date functions: `QUARTER()`, `YEAR()`, `MONTH()` — use `DATE_TRUNC` instead
- List filters cannot be combined with aggregations
