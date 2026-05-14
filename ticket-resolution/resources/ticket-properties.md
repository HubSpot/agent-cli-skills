# Ticket Properties Reference

## Standard Ticket Properties

| Property | Type | Required | Read-only | Notes |
|---|---|---|---|---|
| subject | string | Yes | No | Ticket title — displayed everywhere in the UI |
| content | string | No | No | Full description of the issue |
| hs_pipeline | string | No* | No | Pipeline ID — **always portal-specific** |
| hs_pipeline_stage | string | No* | No | Stage ID — **always portal-specific** |
| hubspot_owner_id | string | No | No | Assigned support agent user ID |
| hs_ticket_priority | enumeration | No | No | `LOW` `MEDIUM` `HIGH` `URGENT` |
| hs_ticket_category | enumeration | No | No | See enum values below |
| hs_resolution | string | No | No | Resolution summary — fill when closing a ticket |
| createdate | datetime | No | Yes | Set automatically on creation |
| hs_lastmodifieddate | datetime | No | Yes | Set automatically on any update |
| time_to_first_response_in_seconds | number | No | Yes | Computed by HubSpot — seconds from create to first reply |
| time_to_close_in_seconds | number | No | Yes | Computed by HubSpot — seconds from create to close |

*`hs_pipeline` and `hs_pipeline_stage` are not strictly required by the API but tickets created without them will land in the default pipeline's first stage. Always set them explicitly.

---

## hs_ticket_priority Enum Values

| Value | Use when |
|---|---|
| `LOW` | Minor inconvenience, workaround exists |
| `MEDIUM` | Meaningful impact, no immediate workaround |
| `HIGH` | Significant business impact, limited workaround |
| `URGENT` | System down, critical data loss, revenue impact |

---

## hs_ticket_category Enum Values

| Value | Description |
|---|---|
| `PRODUCT_ISSUE` | Bug, error, unexpected behavior |
| `BILLING_ISSUE` | Charge dispute, invoice question |
| `FEATURE_REQUEST` | Request for new functionality |
| `GENERAL_INQUIRY` | Question, how-to, information request |
| `OTHER` | Does not fit the above categories |

---

## Getting Pipeline and Stage IDs

> Pipeline and stage IDs are **always portal-specific** — they are never transferable between portals. Run these two commands before creating or updating any ticket.

```bash
# Step 1: list all ticket pipelines and get pipeline IDs
hubspot pipelines list --object tickets --format table

# Step 2: list stages for a specific pipeline
hubspot pipelines stages --object tickets --pipeline <pipeline_id> --format table
```

The stage table output includes the stage label (e.g., "New", "In Progress", "Resolved") and the corresponding ID you need for `hs_pipeline_stage`.

**Typical stage names to look for:**
- Intake / New — use as `hs_pipeline_stage` when creating tickets
- In Progress / Working — use when moving a ticket into active work
- Waiting on Customer — use when ticket is blocked pending customer response
- Resolved / Closed — use when setting `hs_resolution` and closing

---

## Quick Reference: Create a Ticket

```bash
hubspot objects create --type tickets \
  --property subject="<required>" \
  --property content="<description>" \
  --property hs_pipeline=<pipeline_id> \
  --property hs_pipeline_stage=<stage_id> \
  --property hs_ticket_priority=HIGH \
  --property hs_ticket_category=PRODUCT_ISSUE \
  --property hubspot_owner_id=<owner_id>
```

After creation, always associate to a contact and company:

```bash
hubspot associations create --from tickets:<ticket_id> --to contacts:<contact_id>
hubspot associations create --from tickets:<ticket_id> --to companies:<company_id>
```
