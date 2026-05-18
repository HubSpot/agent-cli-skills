---
name: audience-targeting
description: Build a targeted contact segment by filtering on lifecycle, engagement, jobtitle, geography, or firmographics — then export it as JSONL for a campaign or downstream tool.
triggers:
  - "segment contacts"
  - "target audience"
  - "find prospects"
  - "build audience"
  - "contact segmentation"
  - "contacts in industry"
  - "decision makers"
  - "engaged contacts"
---

## Foundation

Read `bulk-operations/SKILL.md` first — pagination, JSONL piping, destructive-op safety. Reshape recipes in `bulk-operations/resources/json-patterns.md`. Resource: `resources/contact-segmentation-filters.md` is the filter-expression cookbook (lifecycle, lead status, email engagement, activity, deals, owner).

## Filter syntax cheat sheet

Source of truth: `hubspot objects search --help`.

- One `--filter` flag = one AND group: `--filter "lifecyclestage=lead AND !hubspot_owner_id"`.
- Multiple `--filter` flags are OR'd. Use for enum-OR-enum.
- Operators: `=`, `!=`, `>`, `>=`, `<`, `<=`, `~` (CONTAINS_TOKEN — whole-word, NOT substring).
- HAS_PROPERTY: bare `name` or `name?`. NOT_HAS_PROPERTY: `!name`. Dates: `YYYY-MM-DD`.

`~` gotcha: `jobtitle~director` matches the token "director", not arbitrary substrings. No regex operator — search broadly, post-filter with `jq`.

## Properties this skill turns on

Full live list: `hubspot properties list --object contacts`. Enum options aren't exposed by `properties get`; discover with `hubspot objects list --type contacts --properties <name> --limit 100 --format json | jq -r '.data[].properties.<name> // empty' | sort -u`.

Core fields used here: `lifecyclestage`, `hubspot_owner_id` (bare/`!` for owned/unowned; `hubspot owners list` for IDs), `hs_email_optout` (`!=true` excludes opted-out), `hs_email_last_open_date` / `notes_last_contacted` (recency), `jobtitle` / `country` / `city` (string `=` or `~`), `num_associated_deals` (0 net-new, `>=1` has-pipeline).

Firmographics (`industry`, `numberofemployees`, `annualrevenue`) live on **companies** — see cross-object section.

## Common segments

```bash
# Recent leads (this quarter, not yet owned)
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead AND createdate>2026-01-01 AND !hubspot_owner_id" \
  --properties email,firstname,lastname,createdate

# Decision-makers by jobtitle (OR across tokens)
hubspot objects search --type contacts \
  --filter "jobtitle~director" --filter "jobtitle~vp" --filter "jobtitle~chief" \
  --properties email,jobtitle,company

# Engaged but not yet MQL (opened recently, still lead, opted in)
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead AND hs_email_last_open_date>2026-04-01 AND hs_email_optout!=true" \
  --properties email,firstname,hs_email_last_open_date

# Geographic — US contacts opted in
hubspot objects search --type contacts \
  --filter "country=United States AND hs_email_optout!=true" \
  --properties email,state,city
```

More patterns (lead status, deals, owners, combined AND/OR) in `resources/contact-segmentation-filters.md`.

## Cross-object: companies-in-industry → their contacts

`industry`/`numberofemployees`/`annualrevenue` live on the company. Build the company set, then traverse — never `xargs -I{} hubspot objects get` per company. `associations list` emits `{"id":"...","type":"company_to_contact"}`, feeding directly into a single batched `objects get`.

```bash
# Step 1: target companies. Industry options are portal-specific — discover with:
#   hubspot objects list --type companies --properties industry --limit 100 --format json \
#   | jq -r '.data[].properties.industry // empty' | sort -u
hubspot objects search --type companies \
  --filter "industry=SOFTWARE AND numberofemployees>=100" \
  --properties name,industry,numberofemployees \
  > target_companies.jsonl

# Step 2: gather association IDs (associations list has no batch --from), then ONE batched
# objects get for all contacts.
while read -r cid; do hubspot associations list --from "companies:$cid" --to contacts; done \
  < <(jq -r '.id' target_companies.jsonl) \
| jq -c '{id}' | sort -u \
| hubspot objects get --type contacts --properties email,firstname,jobtitle,hs_email_optout \
> target_contacts.jsonl

# Optional: drop opted-out
jq -c 'select(.properties.hs_email_optout != "true")' target_contacts.jsonl > campaign_audience.jsonl
```

## Saving and reusing a segment

A segment is a JSONL file. Re-use for updates, exports, or re-fetches:

```bash
# Save
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead AND hs_email_optout!=true" \
  --properties email,firstname,lastname,jobtitle \
  > segments/opted_in_leads.jsonl

# Assign owner (dry-run first per bulk-operations/SKILL.md)
jq -c '{id, properties:{hubspot_owner_id:"12345"}}' segments/opted_in_leads.jsonl \
| hubspot objects update --type contacts --dry-run

# Re-fetch with different properties later
jq -c '{id}' segments/opted_in_leads.jsonl \
| hubspot objects get --type contacts --properties email,lifecyclestage,hs_lead_status
```

Destructive ops on a saved segment follow the dry-run → digest → confirm flow in `bulk-operations/SKILL.md`.

## Known limits

- No Lists API surface. Can't save as a HubSpot list or filter by list membership.
- `~` is token-match, not substring. No regex operator.
- `properties get` does not return enum options — discover via `objects list` + `jq`.
- `associations list` has no batch `--from`. Loop to gather IDs, batch the downstream `objects get`.
- For >100 results, use the pagination loop in `bulk-operations/SKILL.md`.
