# HubSpot Agent CLI Skills

Markdown skill files for AI agents (Claude Code, Cursor, Windsurf, and others) to use the `hubspot` CLI to accomplish CRM tasks. The `hubspot` agent CLI is distinct from `hs`, the `@hubspot/cli` developer CLI for building apps, themes, and modules.

---

## Installation

### Claude Code plugin (recommended)

Add the marketplace, then install the plugin:

```
/plugin marketplace add HubSpot/agent-cli-skills
/plugin install hubspot-agent-cli@agent-cli-skills
```

The plugin auto-installs the `hubspot` CLI on session start. If that fails
(e.g. in a cloud session without network access), run
`/hubspot-agent-cli:hubspot-setup` for manual instructions.

### Claude Cowork / cloud sessions

To use the plugin in a Claude Cowork or cloud session, add the following to
the target repo's `.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "hubspot-agent-cli@agent-cli-skills": true
  },
  "extraKnownMarketplaces": {
    "agent-cli-skills": {
      "source": {
        "source": "github",
        "repo": "HubSpot/agent-cli-skills"
      }
    }
  }
}
```

Then allowlist the HubSpot install hosts in your cloud environment's
network-access settings (Custom mode):

```
install.hubspot.com
api.hubapi.com
```

### Copy skills directly

To install skills into your project's `.claude/skills/` directory instead:

```bash
npx skills hubspot/agent-cli-skills
```

To install a single skill:

```bash
npx skills hubspot/agent-cli-skills/hubspot-agent-cli/skills/bulk-operations
```

---

## Skills

`bulk-operations` is the foundation — every other skill assumes its JSONL pipe, batch-read, pagination, and dry-run/digest patterns. Read it first.

| Skill | Description |
|---|---|
| `hubspot-setup` | Install and configure the HubSpot CLI (runs automatically on session start) |
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

---

## Support

Open an issue at [github.com/hubspot/agent-cli-skills/issues](https://github.com/hubspot/agent-cli-skills/issues) or reach out to the HubSpot developer community on the [HubSpot Developer Forum](https://community.hubspot.com/t5/HubSpot-Developers/ct-p/developers).

---

## License

[Apache License 2.0](./LICENSE)
