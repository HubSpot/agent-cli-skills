# Default Property Sets

Recommended `--properties` values for each object type. These give a complete, useful snapshot without requesting every field (which is slower and harder to read).

---

## Contacts

```bash
--properties email,firstname,lastname,company,phone,jobtitle,lifecyclestage,hs_lead_status,hubspot_owner_id,notes_last_contacted,createdate
```

| Property | Why |
|---|---|
| `email` | Primary identifier |
| `firstname`, `lastname` | Display name |
| `company` | Account name (text field — not the associated company record) |
| `phone` | Direct line for pre-call prep |
| `jobtitle` | Seniority and relevance context |
| `lifecyclestage` | Where in the funnel |
| `hs_lead_status` | Sales rep activity status |
| `hubspot_owner_id` | Who owns this contact |
| `notes_last_contacted` | Last logged activity date |
| `createdate` | When the contact entered the CRM |

---

## Companies

```bash
--properties name,domain,industry,annualrevenue,numberofemployees,city,country,hubspot_owner_id,hs_last_sales_activity_date
```

| Property | Why |
|---|---|
| `name` | Company display name |
| `domain` | Website domain — used for dedup and lookup |
| `industry` | Vertical / segment |
| `annualrevenue` | Account size signal |
| `numberofemployees` | Headcount signal |
| `city`, `country` | Territory context |
| `hubspot_owner_id` | Account owner |
| `hs_last_sales_activity_date` | Engagement recency |

---

## Deals

```bash
--properties dealname,amount,dealstage,pipeline,closedate,hubspot_owner_id,hs_is_closed,hs_is_closed_won,hs_deal_stage_probability,createdate
```

| Property | Why |
|---|---|
| `dealname` | Deal display name |
| `amount` | Deal value |
| `dealstage` | Current stage ID (portal-specific — look up via `hubspot pipelines stages`) |
| `pipeline` | Which pipeline |
| `closedate` | Expected close date |
| `hubspot_owner_id` | Rep responsible |
| `hs_is_closed` | True if won or lost |
| `hs_is_closed_won` | True if won specifically |
| `hs_deal_stage_probability` | Win probability at current stage |
| `createdate` | When the deal was created |

---

## Tickets

```bash
--properties subject,content,hs_pipeline,hs_pipeline_stage,hs_ticket_priority,hubspot_owner_id,createdate,hs_lastmodifieddate
```

| Property | Why |
|---|---|
| `subject` | Ticket title |
| `content` | Issue description |
| `hs_pipeline` | Which ticket pipeline |
| `hs_pipeline_stage` | Current stage (portal-specific — look up via `hubspot pipelines stages --object tickets`) |
| `hs_ticket_priority` | LOW, MEDIUM, HIGH, URGENT |
| `hubspot_owner_id` | Assigned rep |
| `createdate` | When the ticket was opened |
| `hs_lastmodifieddate` | Last update |
