---
description: Set up the HubSpot CLI. Use when the `hubspot` command is missing, the user asks how to install the CLI, or the SessionStart bootstrap failed.
disable-model-invocation: true
---

# HubSpot CLI Setup

## Quick install

```bash
curl -fsSL https://install.hubspot.com | sh
```

Then verify:

```bash
hubspot --version
```

## Cloud / remote sessions (Claude Cowork, routines)

Cloud sandboxes block egress by default. In your environment's network-access
settings, switch to **Custom** and add these hosts (one per line):

```
install.hubspot.com
api.hubapi.com
```

Tick **"Also include default list of common package managers"** so GitHub and
registries stay reachable, then re-run the install command above.

## After install

Authenticate with a HubSpot portal:

```bash
hubspot auth
```

Run `hubspot --help` to see available commands.
