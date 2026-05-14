# HubSpot Association Graph — CLI Reference

Associations link two CRM records together. Once created, an association is bidirectional:
querying from either side will return the other. However, the CLI `list` command requires
you to specify the "from" record — you cannot query "all associations for a record" from
both directions in a single call.

Association type IDs are resolved automatically by the CLI — you do not need to specify them.

---

## Core Object Associations

### contacts ↔ companies

The primary employer relationship. HubSpot tracks a "primary company" per contact.

```bash
# Create
hubspot associations create --from contacts:123 --to companies:456

# List companies associated with a contact
hubspot associations list --from contacts:123 --to companies

# List contacts associated with a company
hubspot associations list --from companies:456 --to contacts
```

### contacts ↔ deals

Links the people involved in a deal. Multiple contacts can be associated with one deal.

```bash
# Create
hubspot associations create --from contacts:123 --to deals:789

# List deals associated with a contact
hubspot associations list --from contacts:123 --to deals

# List contacts on a deal
hubspot associations list --from deals:789 --to contacts
```

### contacts ↔ tickets

Links contacts to their support tickets.

```bash
# Create
hubspot associations create --from contacts:123 --to tickets:555

# List tickets for a contact
hubspot associations list --from contacts:123 --to tickets

# List contacts on a ticket
hubspot associations list --from tickets:555 --to contacts
```

### contacts ↔ activity objects (calls, notes, meetings, tasks, emails)

Logged activities are associated with the contact they involve.

```bash
# Create
hubspot associations create --from contacts:123 --to calls:111
hubspot associations create --from contacts:123 --to notes:222
hubspot associations create --from contacts:123 --to meetings:333
hubspot associations create --from contacts:123 --to tasks:444
hubspot associations create --from contacts:123 --to emails:555

# List (by type)
hubspot associations list --from contacts:123 --to calls
hubspot associations list --from contacts:123 --to notes
hubspot associations list --from contacts:123 --to meetings
hubspot associations list --from contacts:123 --to tasks
hubspot associations list --from contacts:123 --to emails
```

---

## deals ↔ companies

Links a deal to the company it belongs to. Standard deal-to-account relationship.

```bash
# Create
hubspot associations create --from deals:789 --to companies:456

# List companies on a deal
hubspot associations list --from deals:789 --to companies

# List deals for a company
hubspot associations list --from companies:456 --to deals
```

## deals ↔ line_items

Line items are child objects that belong to a deal. One deal can have many line items.

```bash
# Create
hubspot associations create --from deals:789 --to line_items:901

# List line items on a deal
hubspot associations list --from deals:789 --to line_items

# List deals for a line item
hubspot associations list --from line_items:901 --to deals
```

## deals ↔ quotes

Quotes are associated with the deal they were generated from.

```bash
# Create
hubspot associations create --from deals:789 --to quotes:202

# List quotes on a deal
hubspot associations list --from deals:789 --to quotes

# List deals for a quote
hubspot associations list --from quotes:202 --to deals
```

---

## tickets ↔ companies

Links a support ticket to the company filing it.

```bash
# Create
hubspot associations create --from tickets:555 --to companies:456

# List companies on a ticket
hubspot associations list --from tickets:555 --to companies

# List tickets for a company
hubspot associations list --from companies:456 --to tickets
```

## tickets ↔ activity objects (calls, notes, communications)

```bash
# Create
hubspot associations create --from tickets:555 --to calls:111
hubspot associations create --from tickets:555 --to notes:222
hubspot associations create --from tickets:555 --to communications:333

# List
hubspot associations list --from tickets:555 --to calls
hubspot associations list --from tickets:555 --to notes
hubspot associations list --from tickets:555 --to communications
```

---

## quotes ↔ line_items

Quotes embed line items just like deals do.

```bash
# Create
hubspot associations create --from quotes:202 --to line_items:901

# List
hubspot associations list --from quotes:202 --to line_items
hubspot associations list --from line_items:901 --to quotes
```

---

## Bulk Association Patterns

### Bulk-create from a JSONL file

```bash
# File format: one JSON object per line
# {"from":"contacts:123","to":"companies:456"}
# {"from":"contacts:124","to":"companies:456"}

cat associations.jsonl | hubspot associations create
```

### Build association payloads from a search

```bash
# Associate every deal owned by a rep to a specific company
hubspot objects search --type deals --filter "hubspot_owner_id=12345" \
| jq -c '{from: ("deals:" + .id), to: "companies:456"}' \
| hubspot associations create

# Associate all contacts from a search to a company
hubspot objects search --type contacts --filter "company~acme" \
| jq -c '{from: ("contacts:" + .id), to: "companies:789"}' \
| hubspot associations create
```

### List associations and follow up with object details

```bash
# Get contacts associated with a company, then fetch their details
hubspot associations list --from companies:456 --to contacts \
| jq -r '.id' \
| xargs -I{} hubspot objects get --type contacts {} \
    --properties email,firstname,lastname,lifecyclestage
```

---

## Association Direction Note

HubSpot associations are **bidirectional once created**: creating `contacts:123 → companies:456`
means you can query from either direction. The distinction in the CLI `list` command is
purely about which record is the "anchor" for the query — it does not affect the stored relationship.

Some object pairs support multiple association types (e.g., primary vs. unlabeled company
association for contacts). The CLI resolves the **default** type automatically. To set
a specific type, check `hubspot associations list` output for the `type` field on existing
associations.
