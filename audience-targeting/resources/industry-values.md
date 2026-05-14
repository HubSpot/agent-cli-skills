# Industry Enumeration Values — Company Objects

The `industry` field lives on **Company** objects, not Contact objects. To segment contacts
by industry you must use a two-step query: find matching companies first, then fetch their
associated contacts.

---

## Two-Step Pattern: Contacts by Company Industry

```bash
# Step 1: find companies in the target industry
hubspot objects search --type companies \
  --filter "industry=INFORMATION_TECHNOLOGY" \
  > it_companies.jsonl

# Step 2: get associated contacts for each company
cat it_companies.jsonl \
| jq -r '.id' \
| xargs -I{} hubspot associations list --from companies:{} --to contacts --format jsonl \
> it_contacts.jsonl

# OR: inline without saving the intermediate file
hubspot objects search --type companies \
  --filter "industry=SOFTWARE" \
| jq -r '.id' \
| xargs -I{} hubspot associations list --from companies:{} --to contacts --format jsonl
```

For multiple industries, use `--filter` OR groups on the companies search:

```bash
hubspot objects search --type companies \
  --filter "industry=SOFTWARE" \
  --filter "industry=INFORMATION_TECHNOLOGY" \
  --filter "industry=TELECOMMUNICATIONS" \
| jq -r '.id' \
| xargs -I{} hubspot associations list --from companies:{} --to contacts --format jsonl
```

---

## Full Industry Enum Table

| API Value (use in --filter) | Human-Readable Label |
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

## Filter Syntax

```bash
# Single industry — exact match (case-sensitive, use API value)
hubspot objects search --type companies \
  --filter "industry=HEALTHCARE"

# Multiple industries using OR groups
hubspot objects search --type companies \
  --filter "industry=HEALTHCARE" \
  --filter "industry=PHARMACEUTICALS" \
  --filter "industry=BIOTECHNOLOGY"

# Combine with other firmographic filters (AND within a group)
hubspot objects search --type companies \
  --filter "industry=INFORMATION_TECHNOLOGY AND numberofemployees>=100" \
  --properties name,domain,numberofemployees

# Companies with no industry set
hubspot objects search --type companies --filter "!industry" \
  --properties name,domain
```

---

## Notes

- Industry values are **case-sensitive**. Use the API value exactly as shown in the table (e.g., `INFORMATION_TECHNOLOGY`, not `information_technology` or `Information Technology`).
- The `industry` field on Contact objects is a free-text string that contacts may fill in themselves — it is not the same enumeration. For reliable industry segmentation, always use the Company object's `industry` field.
- If a company was imported without an industry value, `--filter "!industry"` will find those records so you can enrich them.
