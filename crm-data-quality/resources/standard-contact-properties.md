# Standard Contact Properties Reference

Use `hubspot properties list --object contacts` to enumerate all properties in a portal.
Properties marked **read-only** cannot be set via `hubspot objects update` or `create`.

---

## Identity Fields

| Internal Name | Label | Type | Notes |
|---|---|---|---|
| `email` | Email | string | Primary deduplication key. HubSpot enforces uniqueness per portal. |
| `firstname` | First Name | string | |
| `lastname` | Last Name | string | |
| `phone` | Phone Number | string | Stored as entered — no normalization enforced. |
| `mobilephone` | Mobile Phone Number | string | |
| `company` | Company Name | string | Free-text company name, **not** the associated Company object. |
| `website` | Website URL | string | |
| `jobtitle` | Job Title | string | |

---

## Address Fields

| Internal Name | Label | Type | Notes |
|---|---|---|---|
| `address` | Street Address | string | |
| `city` | City | string | |
| `state` | State/Region | string | Free text; use full name or abbreviation consistently. |
| `zip` | Postal Code | string | Stored as string to preserve leading zeros. |
| `country` | Country/Region | string | Free text; use consistent values (e.g. always "United States", not "US"). |

---

## Lifecycle and Status Fields

| Internal Name | Label | Type | Enum Values |
|---|---|---|---|
| `lifecyclestage` | Lifecycle Stage | enumeration | `subscriber`, `lead`, `marketingqualifiedlead`, `salesqualifiedlead`, `opportunity`, `customer`, `evangelist`, `other` |
| `hs_lead_status` | Lead Status | enumeration | `NEW`, `OPEN`, `IN_PROGRESS`, `OPEN_DEAL`, `UNQUALIFIED`, `ATTEMPTED_TO_CONTACT`, `CONNECTED`, `BAD_TIMING` |
| `hs_email_optout` | Unsubscribed from all email | boolean | `true` = opted out. Filter with `hs_email_optout!=true` to find opt-in contacts. |
| `hs_email_bounce` | Bounced | boolean | `true` = hard bounced email. HubSpot sets this automatically. |

---

## Activity and Date Fields

All datetime fields use ISO 8601 format. In filter expressions, use `YYYY-MM-DD`.

| Internal Name | Label | Type | Notes |
|---|---|---|---|
| `createdate` | Create Date | datetime | Read-only. When the contact record was created. |
| `lastmodifieddate` | Last Modified Date | datetime | Read-only. Updated on any property change. |
| `notes_last_contacted` | Last Contacted | datetime | Read-only. Last time a call, meeting, or email was logged. |
| `hs_last_sales_activity_date` | Last Sales Activity Date | datetime | Read-only. Includes calls, emails, meetings. |
| `hs_email_last_open_date` | Last Marketing Email Open Date | datetime | Read-only. Set by HubSpot email sends. |
| `hs_email_last_send_date` | Last Marketing Email Send Date | datetime | Read-only. Set by HubSpot email sends. |

---

## Ownership

| Internal Name | Label | Type | Notes |
|---|---|---|---|
| `hubspot_owner_id` | Contact owner | string | Numeric owner ID. Resolve names with `hubspot owners list`. Empty = unowned. |

---

## Analytics and Attribution

| Internal Name | Label | Type | Notes |
|---|---|---|---|
| `hs_analytics_source` | Original Source | enumeration | `DIRECT_TRAFFIC`, `ORGANIC_SEARCH`, `PAID_SEARCH`, `REFERRALS`, `SOCIAL_MEDIA`, `EMAIL_MARKETING`, `OTHER_CAMPAIGNS`, `OFFLINE` |
| `hs_analytics_source_data_1` | Original Source Drill-Down 1 | string | e.g. search engine name or campaign name |
| `num_associated_deals` | Number of Associated Deals | number | Read-only. Count of all deals associated with the contact. |

---

## Filter Syntax Quick Reference

```bash
# Exact match
--filter "lifecyclestage=lead"

# Not equal
--filter "hs_lead_status!=UNQUALIFIED"

# Property exists (has any value)
--filter "email"

# Property missing / empty
--filter "!phone"

# Date comparison (before date)
--filter "hs_email_last_open_date<2024-01-01"

# Date comparison (after date)
--filter "hs_email_last_open_date>2024-01-01"

# Contains token (whole-word match)
--filter "company~acme"

# AND within one --filter flag
--filter "lifecyclestage=lead AND hs_lead_status=NEW"

# OR: use separate --filter flags (one group per flag)
--filter "lifecyclestage=lead" --filter "lifecyclestage=marketingqualifiedlead"
```
