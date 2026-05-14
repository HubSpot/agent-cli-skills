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
npx skills hubspot/agent-cli-skills/crm-data-quality
```

---

## Skills

| Skill | Description |
|---|---|
| `ad-campaign-analytics` | Understand what ad and campaign attribution data is accessible from the CRM |
| `audience-targeting` | Build targeted contact segments by filtering on lifecycle stage, engagement, and firmographics |
| `bulk-operations` | Foundational JSONL pipe pattern for bulk create, update, and delete operations |
| `communication-history` | Retrieve activity history for CRM records and assemble pre-call research briefs |
| `crm-data-quality` | Find incomplete records, normalize field values, and audit custom properties |
| `crm-lookup` | Find specific records by email or domain and traverse associations for a full account picture |
| `customer-retention` | Identify inactive customers, flag at-risk subscriptions, and create follow-up tasks |
| `data-enrichment` | Match external records to CRM contacts and companies and write enriched data back |
| `deal-acceleration` | Identify stalled deals and take bulk action to update stages or reassign ownership |
| `lead-qualification` | Find MQL contacts, create deals with correct pipeline stage, and promote lifecycle stages |
| `pipeline-revenue` | Create deals from qualified contacts and monitor pipeline health by stage |
| `quote-to-cash` | Create product catalog entries, build quotes with line items, and track invoices |
| `sales-execution` | Log calls, notes, meetings, and tasks against contacts and deals |
| `sales-reporting` | Generate daily sales briefings, pipeline snapshots, and activity summaries |
| `team-ownership` | Assign, reassign, and audit record ownership across contacts, deals, and companies |
| `ticket-resolution` | Create and triage support tickets, move them through pipelines, and log resolution notes |
| `win-loss-analysis` | Analyze closed deals, measure win rates by rep or time period, and identify revenue trends |
| `workflow-automation` | List, create, update, and delete HubSpot workflows from the CLI |
---

## Support

Open an issue at [github.com/hubspot/agent-cli-skills/issues](https://github.com/hubspot/agent-cli-skills/issues) or reach out to the HubSpot developer community on the [HubSpot Developer Forum](https://community.hubspot.com/t5/HubSpot-Developers/ct-p/developers).

---

## License

[Apache License 2.0](./LICENSE)
