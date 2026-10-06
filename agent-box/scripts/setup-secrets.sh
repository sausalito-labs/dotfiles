#!/usr/bin/env bash
# One-time bootstrap script for secrets and auth on the agent box.
#
# Create /var/lib/agent-setup/secrets.env with:
#
#   TAILSCALE_AUTHKEY=tskey-auth-...
#
# Then run this script as root.
#
# GitHub authentication is done separately with `gh auth login`. Claude Code
# authentication is done separately with `claude auth login` (Remote Control
# requires a claude.ai subscription login, not an API key).

set -euo pipefail

SECRETS_FILE="/var/lib/agent-setup/secrets.env"
USER="agent"
HOME_DIR="/home/agent"

if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "ERROR: Secrets file not found at $SECRETS_FILE" >&2
    echo "Create it with TAILSCALE_AUTHKEY." >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$SECRETS_FILE"

# -----------------------------------------------------------------------------
# 1. Tailscale
# -----------------------------------------------------------------------------
if ! tailscale status &>/dev/null; then
    echo "==> Joining Tailscale..."
    tailscale up --authkey "${TAILSCALE_AUTHKEY}" --operator="${USER}"
else
    echo "==> Tailscale already connected."
fi

# Let the agent user run `tailscale serve` / `tailscale funnel` without sudo.
# Re-applied every run because `tailscale up` resets unspecified flags.
echo "==> Setting the Tailscale operator to '${USER}'..."
tailscale set --operator="${USER}"

# -----------------------------------------------------------------------------
# 2. GitHub CLI
# -----------------------------------------------------------------------------
if ! sudo -u "$USER" gh auth status &>/dev/null; then
    echo "==> GitHub CLI not authenticated."
    echo "Run the following command as the agent user and follow the browser flow:"
    echo "  gh auth login"
else
    echo "==> GitHub CLI already authenticated."
fi

# -----------------------------------------------------------------------------
# 3. Claude Code
# -----------------------------------------------------------------------------
# No secret to write: Claude Code authenticates with `claude auth login` and
# stores the credential in ~/.claude/.credentials.json (mode 0600). setup.sh
# runs that login step.

echo "==> Auth setup complete."
