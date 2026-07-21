# Deal Pipeline Signals — Filter Cookbook

The deal-level signals HubSpot exposes for identifying deals that may need attention, and how to query them. **No definition of "stalled" is prescribed** — what counts as stalled depends on the team's sales cycle (enterprise deals legitimately sit longer than SMB), pipeline-stage SLAs, and forecasting cadence. Ask the user or derive from context before plugging in a cutoff.

## Picking a cutoff

Before any time-based filter, you need a cutoff date. Don't invent one — ask, or derive:

- **Activity gap** — what's a normal touch cadence for an open deal in this team? "Stalled" is some multiple of that.
- **Stage age** — does the pipeline have per-stage SLAs (e.g. "should not sit in proposal more than 2 weeks")? Use those.
- **Close-date drift** — what's the typical cycle length? A deal whose close date is past should usually be flagged immediately; one with a far-future close needs cycle-length context to interpret.

If the user hasn't told you and you can't infer it, ask.

```bash
# Substitute N for whatever cutoff the user/context justifies
CUTOFF=$(date -v-${N}d +%Y-%m-%d 2>/dev/null || date -d "${N} days ago" +%Y-%m-%d)
FUTURE=$(date -v+${N}d +%Y-%m-%d 2>/dev/null || date -d "${N} days" +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)
```

---

## Signals HubSpot exposes

### Past close date, still open

Hard signal — the rep already committed to a close date that has passed. Doesn't need a tunable cutoff; the cutoff is today.

```bash
hubspot objects search --type deals \
  --filter "closedate<$TODAY AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id,amount
```

### Activity gap — `hs_last_activity_date`

How long since *anything* (call, note, email, task, meeting) happened on the deal. Cutoff should map to the team's touch cadence.

```bash
hubspot objects search --type deals \
  --filter "hs_last_activity_date<$CUTOFF AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id,hs_last_activity_date
```

### No activity ever (open deals)

```bash
hubspot objects search --type deals \
  --filter "!hs_last_activity_date AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id
```

### Stuck in a specific stage

Discover stage IDs first: `hubspot pipelines stages --type deals --pipeline <pipeline_id>`. Combine with `closedate` or `hs_last_activity_date` based on how the team measures stuck.

```bash
hubspot objects search --type deals \
  --filter "dealstage=<stage_id> AND closedate<$CUTOFF AND hs_is_closed!=true" \
  --properties dealname,closedate,hubspot_owner_id,amount
```

### Data quality on open deals

Missing required fields on an open deal — usually a data-hygiene flag, not a churn signal. What's "required" is team-defined.

```bash
# Missing amount
hubspot objects search --type deals \
  --filter "!amount AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id

# No associated contacts
hubspot objects search --type deals \
  --filter "num_associated_contacts<1 AND hs_is_closed!=true" \
  --properties dealname,dealstage,closedate,hubspot_owner_id,amount
```

### Pipeline intent vs. close timing — `hs_deal_stage_probability` + `closedate`

`hs_deal_stage_probability` is HubSpot's per-stage win probability (0–1). High probability with a far-future close date can indicate either a long-cycle deal (normal) or pipeline slippage (problem). The `$FUTURE` cutoff is the caller's call — it should reflect the team's forecast horizon.

```bash
hubspot objects search --type deals \
  --filter "hs_deal_stage_probability>0 AND closedate>$FUTURE AND hs_is_closed!=true" \
  --properties dealname,dealstage,hs_deal_stage_probability,closedate,amount,hubspot_owner_id
```

---

## Combining signals

`--filter` is AND-only within a single flag. Use repeated `--filter` flags for OR, or merge multiple queries with `jq -s 'unique_by(.id)'`:

```bash
{
  hubspot objects search --type deals --filter "closedate<$TODAY AND hs_is_closed!=true"
  hubspot objects search --type deals --filter "!amount AND hs_is_closed!=true"
  hubspot objects search --type deals --filter "hs_last_activity_date<$CUTOFF AND hs_is_closed!=true"
} | jq -s 'unique_by(.id) | .[]'
```

## Filter syntax notes

- `closedate` is a date; activity-date props are datetime but accept `YYYY-MM-DD` strings for `<`/`>` comparisons.
- `!prop` = null/empty; bare `prop` = present and non-empty.
- AND only within one `--filter`. Use repeated `--filter` flags for OR.
- `hs_is_closed` and `hs_is_closed_won` are read-only but filterable.
