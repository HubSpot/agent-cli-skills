---
name: ad-campaign-analytics
description: Understand what ad and campaign attribution data is accessible from the CRM and what requires the HubSpot Marketing Hub UI or API.
triggers:
  - "ad campaign"
  - "marketing campaign"
  - "paid advertising"
  - "campaign performance"
  - "ad spend"
  - "marketing analytics"
  - "ad campaign analytics"
  - "campaign attribution"
---

## Context
Ad campaign data (impressions, clicks, spend, audience reach) lives in HubSpot's Marketing Hub and ad platform integrations — it is not accessible via the CRM objects API that this CLI uses. However, the CRM does store contact-level attribution properties that show which campaigns influenced a contact, and these are queryable from the CLI.

## What IS Accessible from the CRM

### Contact Attribution Properties

These properties are set automatically when a contact first converts via a tracked source.

| Property | Type | Notes |
|---|---|---|
| `hs_analytics_source` | enumeration | First-touch source: PAID_SEARCH, PAID_SOCIAL, ORGANIC_SEARCH, DIRECT_TRAFFIC, EMAIL_MARKETING, etc. |
| `hs_analytics_source_data_1` | string | Source detail (e.g. campaign name or keyword) |
| `hs_analytics_source_data_2` | string | Additional source detail |
| `hs_analytics_first_url` | string | First page visited |
| `hs_analytics_last_url` | string | Most recent page visited |
| `hs_analytics_first_touch_converting_campaign` | string | Campaign that drove the first conversion |
| `hs_analytics_last_touch_converting_campaign` | string | Campaign that drove the most recent conversion |
| `hs_analytics_num_page_views` | number | Total page views tracked |
| `hs_analytics_num_visits` | number | Total sessions |

### Find Contacts from a Specific Campaign Source

```bash
# Contacts from paid search
hubspot objects search --type contacts \
  --filter "hs_analytics_source=PAID_SEARCH" \
  --properties email,firstname,lastname,hs_analytics_source,hs_analytics_source_data_1,lifecyclestage

# Contacts from paid social
hubspot objects search --type contacts \
  --filter "hs_analytics_source=PAID_SOCIAL" \
  --properties email,firstname,lastname,hs_analytics_source_data_1,lifecyclestage

# Contacts attributed to a specific campaign (first touch)
hubspot objects search --type contacts \
  --filter "hs_analytics_first_touch_converting_campaign~summer_promo" \
  --properties email,firstname,hs_analytics_first_touch_converting_campaign,lifecyclestage
```

### Count Leads by Source

```bash
hubspot objects search --type contacts \
  --filter "lifecyclestage=lead" \
  --properties hs_analytics_source \
| jq -r '.properties.hs_analytics_source // "unknown"' \
| sort | uniq -c | sort -rn
```

### Email Engagement Properties (on Contacts)

| Property | Notes |
|---|---|
| `hs_email_last_open_date` | Last time a marketing email was opened |
| `hs_email_last_click_date` | Last marketing email click |
| `hs_email_bounced` | `true` if email has bounced |
| `hs_email_optout` | `true` if unsubscribed from all email |

```bash
# Contacts who opened a marketing email in the last 30 days (macOS)
hubspot objects search --type contacts \
  --filter "hs_email_last_open_date>$(date -v-30d +%Y-%m-%d)" \
  --properties email,firstname,hs_email_last_open_date,lifecyclestage
```

## What Is NOT Accessible from This CLI

The following requires the HubSpot Marketing Hub UI or Marketing API (not implemented in hub-cli):

- Ad platform impressions, clicks, spend, and ROAS by campaign
- Marketing Hub campaign-level analytics (sends, opens, clicks, unsubscribes per campaign)
- Ad audience membership and custom audience sync status
- Campaign ROI and attribution reports
- Marketing Hub email campaign creation and sending

For these, use the HubSpot Marketing Hub UI or query the HubSpot Marketing API directly via `curl` with a private app token.

## Known Limitations
- `hs_analytics_source` values are first-touch only. HubSpot's multi-touch attribution models are only available in the Marketing Hub UI.
- Campaign name properties use free-text strings — use `~` (CONTAINS_TOKEN) for partial matches, but it matches whole words only.
