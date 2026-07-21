#!/usr/bin/env bash
# Install the HubSpot CLI if it isn't already available.

if command -v hubspot &>/dev/null; then
  exit 0
fi

if curl -fsSL --connect-timeout 5 https://install.hubspot.com 2>/dev/null | sh 2>/dev/null; then
  exit 0
fi

cat <<'MSG'
HubSpot CLI auto-install failed.

To install manually:
  curl -fsSL https://install.hubspot.com | sh

If you are in a cloud/remote session, allowlist these hosts in your
environment's network-access settings (Custom mode):
  install.hubspot.com
  api.hubapi.com

Run /hubspot-agent-cli:hubspot-setup for step-by-step guidance.
MSG
exit 0
