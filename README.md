# HubSpot Agent Skills

[![Install Skills](https://img.shields.io/badge/Install%20Skills-hubspot%2Fagent--cli--skills-blue)](https://skills.sh/hubspot/agent-cli-skills)

Markdown skill files for AI agents (Claude Code, Cursor, Windsurf, and others) to use the [`hubspot` CLI](https://github.com/hubspot/hub-cli) to accomplish CRM tasks.

---

## Installation

```bash
npx skills hubspot/agent-cli-skills
```

This installs all skills into your project's `.claude/skills/` directory. To install a single skill:

```bash
npx skills hubspot/agent-cli-skills/bulk-operations
```

---

## Skills

`bulk-operations` is the foundation — every other skill assumes its JSONL pipe, batch-read, pagination, and dry-run/digest patterns. Read it first.

| Skill | Description |
|---|---|
| `bulk-operations` | Foundation: JSONL pipes, batch read, pagination, dry-run/digest/confirm for destructive ops, `hubspot history` recovery |
| `audience-targeting` | Build targeted contact segments by filtering on lifecycle stage, engagement, and firmographics |
| `communication-history` | Retrieve activity history for CRM records and assemble pre-call research briefs |
| `crm-data-quality` | Find incomplete records, normalize field values, and dedupe via `objects merge` |
| `crm-lookup` | Find records by ID/email/domain/partial name and traverse associations for a full picture |
| `custom-object-management` | Manage custom object schemas: list, create, update labels, delete |
| `customer-retention` | Identify inactive customers, flag at-risk subscriptions, and create follow-up tasks |
| `data-enrichment` | Match external data to CRM contacts and companies via `objects upsert` |
| `deal-management` | Full deal lifecycle: discover pipelines/stages, qualify, advance, find stalled, close |
| `quote-to-cash` | Create product catalog entries, build quotes with line items, and track invoices |
| `sales-execution` | Log calls, notes, meetings, and tasks against contacts and deals (with association) |
| `sales-reporting` | Daily sales briefings, pipeline snapshots, and win/loss analysis |
| `team-ownership` | Assign, reassign, and audit record ownership across contacts, deals, and companies |
| `ticket-resolution` | Create and triage support tickets, move them through pipelines, and log resolution |
| `workflow-automation` | List, create, update, and delete HubSpot workflows from the CLI |

CLI feature requests surfaced by these skills are tracked in [`CLI_IMPROVEMENTS.md`](./CLI_IMPROVEMENTS.md).

---

## Support

Open an issue at [github.com/hubspot/agent-cli-skills/issues](https://github.com/hubspot/agent-cli-skills/issues) or reach out to the HubSpot developer community on the [HubSpot Developer Forum](https://community.hubspot.com/t5/HubSpot-Developers/ct-p/developers).

---

## License

[Apache License 2.0](./LICENSE)
