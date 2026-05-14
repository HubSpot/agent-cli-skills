---
name: customer-retention
description: Retain customers and reduce churn by identifying inactive customer contacts, flagging at-risk subscriptions, creating follow-up tasks, and logging check-in notes.
triggers:
  - "customer retention"
  - "churn risk"
  - "inactive customers"
  - "customer follow-up"
  - "account health"
  - "customer success"
  - "at-risk accounts"
  - "customers not contacted"
  - "renewal"
---

## Resources

| File | When to use |
|---|---|
| `resources/customer-health-signals.md` | Three-tier reference of churn signals and engagement indicators with exact CLI filter expressions for each |
| `resources/retention-playbook.sh` | Daily health-check script: finds inactive customers, past-due subscriptions, and stale high-priority tickets, then creates follow-up tasks |

## Context
Customer retention requires proactive outreach to accounts showing signs of disengagement. This skill covers finding inactive customer contacts based on last contact date, flagging at-risk subscriptions, creating follow-up tasks at scale, getting company health overviews, and logging check-in notes — all using the CLI.

## Property Reference — Contacts (Customers)

| Property | Type | Notes |
|---|---|---|
| lifecyclestage | enumeration | Filter on `customer` to scope to current customers |
| notes_last_contacted | datetime | Last time a contact activity was logged |
| notes_last_updated | datetime | Last CRM update |
| hs_email_last_open_date | datetime | Last marketing email open |
| hs_last_sales_activity_date | datetime | Read-only |
| num_associated_deals | number | Read-only |
| hs_email_optout | boolean | |

## Property Reference — Companies

| Property | Type | Notes |
|---|---|---|
| hs_num_open_deals | number | Read-only |
| hs_num_associated_contacts | number | Read-only |
| annualrevenue | number | |
| hs_last_sales_activity_date | datetime | Read-only |

## Property Reference — Subscriptions

| Property | Type | Notes |
|---|---|---|
| hs_subscription_status | enumeration | ACTIVE, CANCELLED, PAST_DUE, TRIALING |
| hs_mrr | number | Monthly recurring revenue |
| hs_arr | number | Annual recurring revenue |

## Key Workflows

### Find Inactive Customer Contacts

```bash
# Customers not contacted in the last 90 days
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND notes_last_contacted<2025-01-01" \
  --properties email,firstname,lastname,notes_last_contacted,hubspot_owner_id

# Customers who have never been contacted
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND !notes_last_contacted" \
  --properties email,firstname,lastname,hubspot_owner_id
```

### Bulk Create Follow-Up Tasks for Inactive Customers

```bash
# Save inactive customers first
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND notes_last_contacted<2025-01-01" \
  --properties email,firstname,hubspot_owner_id \
  > inactive_customers.jsonl

# Create a follow-up task for each
cat inactive_customers.jsonl | while read line; do
  contact_id=$(echo "$line" | jq -r '.id')
  name=$(echo "$line" | jq -r '.properties.firstname')

  task_id=$(hubspot objects create --type tasks \
    --property hs_task_subject="Check in with $name" \
    --property hs_task_priority=MEDIUM \
    --property hs_task_status=NOT_STARTED \
    --property hs_task_type=CALL \
    --property hs_timestamp=$(date +%s)000 \
    --format json | jq -r '.data.id')

  hubspot associations create --from tasks:$task_id --to contacts:$contact_id
done
```

### Find At-Risk Subscriptions

```bash
# Past due subscriptions
hubspot objects search --type subscriptions \
  --filter "hs_subscription_status=PAST_DUE" \
  --properties hs_mrr,hs_arr,hs_subscription_status

# Cancelled subscriptions (for win-back outreach)
hubspot objects search --type subscriptions \
  --filter "hs_subscription_status=CANCELLED" \
  --properties hs_mrr,hs_subscription_status
```

### Get Company Health Overview

```bash
hubspot objects get --type companies <company_id> \
  --properties name,hs_num_open_deals,hs_num_associated_contacts,annualrevenue,hs_last_sales_activity_date
```

### Flag At-Risk Customers with a Custom Property

```bash
# Create the property (run once per portal)
hubspot properties create \
  --object contacts \
  --name churn_risk_flag \
  --label "Churn Risk Flag" \
  --type enumeration \
  --field-type select

# Flag inactive customers
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND notes_last_contacted<2025-01-01" \
| jq -c '{id, properties: {churn_risk_flag: "AT_RISK"}}' \
| hubspot objects update --type contacts
```

### Log a Customer Check-In Note

```bash
# Create the note
hubspot objects create --type notes \
  --property hs_note_body="Q1 check-in completed. Customer is happy with the product and exploring expansion into the analytics module." \
  --property hs_timestamp=$(date +%s)000

# Associate note to contact (mandatory)
hubspot associations create --from notes:<note_id> --to contacts:<contact_id>

# Also associate to company if applicable
hubspot associations create --from notes:<note_id> --to companies:<company_id>
```

### Find All Active Subscriptions and Their MRR

```bash
hubspot objects search --type subscriptions \
  --filter "hs_subscription_status=ACTIVE" \
  --properties hs_mrr,hs_arr,hs_subscription_status

# Sum total MRR — fetch with --format json, then sum .data[].properties.hs_mrr
hubspot objects search --type subscriptions \
  --filter "hs_subscription_status=ACTIVE" \
  --format json \
  | jq '[.data[].properties.hs_mrr | tonumber] | add'
```

### Find Customers Who Have Not Opened a Recent Email

```bash
hubspot objects search --type contacts \
  --filter "lifecyclestage=customer AND hs_email_last_open_date<2025-01-01 AND hs_email_optout!=true" \
  --properties email,firstname,hs_email_last_open_date
```

### Get All Contacts at a Company

```bash
hubspot associations list --from companies:<company_id> --to contacts --format jsonl
```

## Known Limitations
- No churn prediction or health score natively in HubSpot. Create custom properties (e.g., `churn_risk_flag`, `health_score`) to track these using data from your product analytics system.
- Subscription management (creating or modifying subscriptions) requires a private app token (`export HUBSPOT_ACCESS_TOKEN=<token>`). User OAuth login has read access only for some subscription data.
- No Conversations/Inbox API — live chat and email threads are not accessible from the CLI.
- For > 100 inactive customers, use the pagination loop from the `bulk-operations` skill before running the task-creation loop.
- `notes_last_contacted` is updated when activities (calls, notes, meetings) are logged and associated to the contact — not just when properties are edited.
