# Standard Company Properties Reference

Use `hubspot properties list --object companies` to enumerate all properties in a portal.
Properties marked **read-only** cannot be set via `hubspot objects update` or `create`.

---

## Identity and Contact Fields

| Internal Name | Label | Type | Notes |
|---|---|---|---|
| `name` | Company name | string | Primary display name. |
| `domain` | Company Domain Name | string | Used for automatic contact association. One per record. |
| `website` | Website URL | string | Full URL including protocol. |
| `phone` | Phone Number | string | Main company phone. |

---

## Firmographic Fields

| Internal Name | Label | Type | Enum Values / Notes |
|---|---|---|---|
| `industry` | Industry | enumeration | See full enum table below |
| `type` | Type | enumeration | `PROSPECT`, `PARTNER`, `RESELLER`, `VENDOR`, `OTHER` |
| `numberofemployees` | Number of Employees | number | Integer. Used for size-based segmentation. |
| `annualrevenue` | Annual Revenue | number | Integer (USD). No currency conversion. |

### Industry Enumeration Values

| API Value | Human-Readable Label |
|---|---|
| `ACCOUNTING` | Accounting |
| `ADVERTISING_AND_MARKETING` | Advertising & Marketing |
| `AEROSPACE` | Aerospace |
| `AGRICULTURE` | Agriculture |
| `ARTS_ENTERTAINMENT` | Arts & Entertainment |
| `AUTOMOTIVE` | Automotive |
| `BANKING` | Banking |
| `BIOTECHNOLOGY` | Biotechnology |
| `BROADCASTING` | Broadcasting |
| `CONSTRUCTION` | Construction |
| `CONSUMER_GOODS` | Consumer Goods |
| `DEFENSE` | Defense & Space |
| `EDUCATION` | Education |
| `ENERGY` | Energy |
| `ENGINEERING` | Engineering |
| `ENVIRONMENTAL` | Environmental |
| `FINANCE` | Finance |
| `FOOD_BEVERAGE` | Food & Beverage |
| `GOVERNMENT` | Government |
| `HEALTHCARE` | Healthcare |
| `HOSPITALITY` | Hospitality |
| `HUMAN_RESOURCES` | Human Resources |
| `INFORMATION_TECHNOLOGY` | Information Technology |
| `INSURANCE` | Insurance |
| `LEGAL` | Legal |
| `MANUFACTURING` | Manufacturing |
| `MEDIA` | Media |
| `NONPROFIT` | Nonprofit |
| `OTHER` | Other |
| `PHARMACEUTICALS` | Pharmaceuticals |
| `REAL_ESTATE` | Real Estate |
| `RETAIL` | Retail |
| `SOFTWARE` | Software |
| `TELECOMMUNICATIONS` | Telecommunications |
| `TRANSPORTATION` | Transportation |
| `UTILITIES` | Utilities |

---

## Address Fields

| Internal Name | Label | Type | Notes |
|---|---|---|---|
| `address` | Street Address | string | |
| `city` | City | string | |
| `state` | State/Region | string | Free text; maintain consistent format. |
| `zip` | Postal Code | string | Stored as string. |
| `country` | Country/Region | string | Free text; use consistent values. |

---

## Ownership

| Internal Name | Label | Type | Notes |
|---|---|---|---|
| `hubspot_owner_id` | Company owner | string | Numeric owner ID. Resolve with `hubspot owners list`. |

---

## Relationship Counters (Read-Only)

| Internal Name | Label | Type | Notes |
|---|---|---|---|
| `hs_num_open_deals` | Number of Open Deals | number | Read-only. Count of associated deals not in a closed stage. |
| `hs_num_associated_contacts` | Number of Associated Contacts | number | Read-only. Count of contacts linked to this company. |

---

## Activity and Date Fields

| Internal Name | Label | Type | Notes |
|---|---|---|---|
| `hs_last_sales_activity_date` | Last Sales Activity Date | datetime | Read-only. Updated on logged calls, emails, meetings. |
| `createdate` | Create Date | datetime | Read-only. |
| `lastmodifieddate` | Last Modified Date | datetime | Read-only. |

---

## Filter Syntax Quick Reference

```bash
# Find companies in a specific industry
hubspot objects search --type companies \
  --filter "industry=INFORMATION_TECHNOLOGY"

# OR across industries (one --filter per group)
hubspot objects search --type companies \
  --filter "industry=SOFTWARE" \
  --filter "industry=INFORMATION_TECHNOLOGY"

# Size-based filter
hubspot objects search --type companies \
  --filter "numberofemployees>=500"

# Company type
hubspot objects search --type companies \
  --filter "type=PROSPECT"

# Unowned companies
hubspot objects search --type companies --filter "!hubspot_owner_id"

# Companies with open deals
hubspot objects search --type companies \
  --filter "hs_num_open_deals>=1"

# Companies with no associated contacts
hubspot objects search --type companies \
  --filter "hs_num_associated_contacts=0"
```

---

## Data Quality Patterns

```bash
# Companies missing domain
hubspot objects search --type companies --filter "!domain" \
  --properties name,website

# Companies with no owner and open deals (likely territory gap)
hubspot objects search --type companies \
  --filter "!hubspot_owner_id AND hs_num_open_deals>=1" \
  --properties name,domain,hs_num_open_deals

# Normalize industry value for records with inconsistent casing
hubspot objects search --type companies --filter "industry~software" \
| jq -c '{id, properties: {industry: "SOFTWARE"}}' \
| hubspot objects update --type companies --dry-run
```
