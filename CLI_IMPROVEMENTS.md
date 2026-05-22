# CLI Improvements

Feature requests and bug fixes for the `hubspot` agent CLI. Each entry: a one-line ask, a one-line "why," and the skill(s) that would simplify with this change. Items here are things skills currently work around in prose; the right fix is in the CLI, not in a markdown caveat.

Add new entries at the bottom. Keep each entry to ≤4 lines.

---

## 1. `hubspot activities create --type CALL --contact X --deal Y --title ... --body ...`

**Ask:** One command that creates a call/note/meeting/task and associates it to one or more records, atomically.
**Why:** Activities without associations are invisible in the HubSpot UI. Every `sales-execution` example today is a two-step ritual that's easy to half-complete. Fold it into the CLI.
**Used by:** `sales-execution`, `customer-retention`, `ticket-resolution`.

## 2. Auto-pagination flag

**Ask:** `hubspot objects list --all` and `hubspot objects search --all` that paginate transparently and stream JSONL.
**Why:** Every skill currently teaches a `while` loop on `--format json` and `meta.next`. That's CLI work, not agent work.
**Used by:** Everything that reads more than 100 records.

## 3. Lookup-by-property shortcut

**Ask:** `hubspot objects get --type contacts --by email=jane@example.com` (and `--by domain=...` for companies).
**Why:** The single most common lookup is "find the one record matching this property." Skills currently do `objects search ... | jq` for the single-row case.
**Used by:** `crm-lookup`, `data-enrichment`, `customer-retention`.

## 4. Consistent singular/plural type references in `associations`

**Ask:** `hubspot associations list --from contact:123` (singular) should either work or stop appearing in `--help` examples. Today the help shows `contact:12345` but only `contacts:12345` succeeds.
**Why:** `--help` is the authoritative source; mismatched examples mislead agents and cost a retry.
**Used by:** Every skill that walks associations.

## 5. Server-side bulk update by filter

**Ask:** `hubspot objects update --type deals --where "dealstage=stagnant AND hs_is_closed!=true" --property hubspot_owner_id=999`.
**Why:** The current pattern is `search → jq → update`, which round-trips every record's ID through the agent. A `--where` flag pushes the join into the CLI.
**Used by:** `crm-data-quality`, `deal-management`, `team-ownership`.

## 6. `--first` / `--one` modes on `search`

**Ask:** `hubspot objects search --type contacts --filter "email=..." --one` returns exactly one record or exits non-zero.
**Why:** "Find the one record" is the most common lookup. `--one` removes a `jq` step and gives agents a clear failure signal.
**Used by:** `crm-lookup`, `data-enrichment`.

## 7. Curated property sets

**Ask:** `hubspot properties suggest --type contacts --intent <lookup|segmentation|reporting>` returns a JSON list of properties relevant to that intent.
**Why:** Every skill currently hand-maintains a "default property set." That's metadata that belongs in the CLI.
**Used by:** `crm-lookup`, `audience-targeting`, `sales-reporting`.

## 8. Recovery primitive on `hubspot history`

**Ask:** `hubspot history --restore <id>` or `hubspot history --revert-since 1h` to undo recent destructive mutations.
**Why:** The audit log already records `RecordMutation`, `BulkData`, `MetadataDestroy`. Closing the loop with a revert turns it into an actual safety net instead of a forensic log.
**Used by:** Every skill that does destructive work.

## 9. Permission preflight on `whoami`

**Ask:** `hubspot whoami --can delete:contacts` (or a `capabilities` field on `whoami` output) so the agent can check before attempting.
**Why:** Skills currently guess about "User OAuth cannot delete." Either the CLI knows what the auth token can do, or skills shouldn't claim limitations they can't verify.
**Used by:** `bulk-operations`, `crm-data-quality`.

## 10. `objects upsert` examples in `--help`

**Ask:** Extend `hubspot objects upsert --help` with a real worked example (build JSONL from a CSV, dry-run, run). Current help is dense.
**Why:** `upsert` is the single most powerful command for enrichment workflows but agents need to see the full pipeline to use it correctly.
**Used by:** `data-enrichment`, `crm-data-quality`.

## 11. `--properties` flattening claim in `--help` is wrong

**Ask:** Either flatten output to `prop_<name>` when `--properties` is passed (as `hubspot objects get --help` claims) or fix the help text. Today output is always nested under `.properties` regardless of `--properties`.
**Why:** Multiple skills built jq pipelines against the documented flat shape and silently produced empty output. The mismatch between `--help` and runtime broke real workflows.
**Used by:** `bulk-operations`, `sales-reporting`, `crm-lookup`, every read-then-reshape skill.

## 12. `objects search` should allow listing without a filter

**Ask:** `hubspot objects search --type deals` (no `--filter`) should return everything, the way `objects list` does. Today it errors.
**Why:** Agents reach for `search` for the rich filter language and only later need "show me everything"; switching commands mid-pipeline is friction. Workarounds like `--filter "hs_object_id>0"` are hacky.
**Used by:** `deal-management`, `sales-reporting`, `team-ownership`.

## 13. `owners get --email <addr>` (or `--filter email=`)

**Ask:** Direct owner lookup by email. Currently every reassignment workflow does `hubspot owners list | jq 'select(.email==...)'`.
**Why:** Owner-email → owner-ID is the single most common owner operation. The two-step jq dance shows up in `team-ownership`, `deal-management`, `customer-retention`.
**Used by:** `team-ownership`, `deal-management`, `customer-retention`, `sales-execution`.

## 14. `properties get/list` should return enumeration option values

**Ask:** `hubspot properties get --type tickets hs_ticket_priority` should include the allowed enum values; add `--include-options` or always include them for `enumeration`-type properties.
**Why:** Today the only way to discover allowed enum values is to probe with an invalid value and parse the 400 error string, or sample live records. Skills end up shipping static reference tables that go stale.
**Used by:** `ticket-resolution`, `sales-execution`, `customer-retention`, `quote-to-cash`.

## 15. `objects search` zero-result message pollutes stdout

**Ask:** When a search returns zero rows in `--format json` / default JSONL, the CLI prints "No results." to stdout ahead of (or instead of) the JSON. That breaks downstream `jq`. Send to stderr or suppress under machine-readable formats.
**Why:** Every pipeline that might legitimately get zero results has to filter "No results." out of stdout to avoid jq parse errors.
**Used by:** `team-ownership`, `crm-data-quality`, everything that pipes search to jq.

## 16. `objects types` should surface scope requirements

**Ask:** `hubspot objects types` lists `invoices`, `subscriptions`, `orders`, `carts` but commands against them 403 in many portals. Add a `requires_scopes` or `commerce_only` column.
**Why:** Today the only way to learn that a token can't read a listed object type is to attempt the call and parse the 403. Predeclaring scope requirements lets agents fail fast and explain why.
**Used by:** `quote-to-cash`, `customer-retention`.

## 17. `associations create` stdin shape in `--help`

**Ask:** `associations create --help` mentions stdin JSONL only in passing; surface the per-line shape `{"from":"contacts:123","to":"companies:456"}` in the Examples section the same way other write commands do.
**Why:** Bulk association is in every CRUD-adjacent skill but agents repeatedly fall back to one-call-per-pair because the stdin shape isn't obvious from `--help`.
**Used by:** `deal-management`, `sales-execution`, `data-enrichment`.

## 18. Workflow ergonomics: name search, partial update, enable/disable shortcuts

**Ask:** Add `hubspot workflows search` (or a `--name` filter on `list`); accept partial bodies on `update` with merge semantics; add `workflows enable/disable <id>` shortcuts.
**Why:** "Find workflow by name" is universally `list | jq` with page loops. Full-PUT on update is correct but makes flipping `isEnabled` needlessly hazardous (a forgotten `enrollmentCriteria` silently wipes the trigger).
**Used by:** `workflow-automation`.

## 19. Pipeline stage probability missing from `pipelines stages`

**Ask:** `hubspot pipelines stages --type deals --pipeline default` should include each stage's `probability` so agents can distinguish won vs lost stages from metadata.
**Why:** Today the only programmatic signal for won/lost is `hs_is_closed_won` on the deal record. Stage probability belongs on the stage, not on every closed deal.
**Used by:** `sales-reporting`, `deal-management`.

## 20. Typed values on read

**Ask:** A `--typed` flag (or default behavior) that returns booleans, numbers, and timestamps in their native JSON types instead of string-encoded (`"true"`, `"5000"`, `"2026-01-01T..."`).
**Why:** Every aggregation skill writes `tonumber` and string comparisons against `"true"`/`"false"`. The CLI knows the property types — it should emit them faithfully.
**Used by:** `sales-reporting`, `audience-targeting`, every reporting/aggregation flow.
