#!/usr/bin/env bash
# One-time bootstrap script for secrets and auth on the NixOS agent box.
#
# Create /var/lib/agent-setup/secrets.env with:
#
#   TAILSCALE_AUTHKEY=tskey-auth-...
#   GITHUB_TOKEN=ghp_...
#   OPENCODE_API_KEY=sk-...
#
# Then run this script as root.

set -euo pipefail

SECRETS_FILE="/var/lib/agent-setup/secrets.env"
USER="agent"
HOME_DIR="/home/agent"

if [[ ! -f "$SECRETS_FILE" ]]; then
    echo "ERROR: Secrets file not found at $SECRETS_FILE" >&2
    echo "Create it with TAILSCALE_AUTHKEY, GITHUB_TOKEN, and OPENCODE_API_KEY." >&2
    exit 1
fi

# shellcheck source=/dev/null
source "$SECRETS_FILE"

# -----------------------------------------------------------------------------
# 1. Tailscale
# -----------------------------------------------------------------------------
if ! tailscale status &>/dev/null; then
    echo "==> Joining Tailscale/Headscale..."
    tailscale up --authkey "${TAILSCALE_AUTHKEY}"
else
    echo "==> Tailscale already connected."
fi

# -----------------------------------------------------------------------------
# 2. GitHub CLI
# -----------------------------------------------------------------------------
if ! sudo -u "$USER" gh auth status &>/dev/null; then
    echo "==> Authenticating gh..."
    echo "${GITHUB_TOKEN}" | sudo -u "$USER" gh auth login --with-token
else
    echo "==> GitHub CLI already authenticated."
fi

# -----------------------------------------------------------------------------
# 3. OpenCode
# -----------------------------------------------------------------------------
OPENCODE_AUTH_DIR="$HOME_DIR/.local/share/opencode"
OPENCODE_AUTH_FILE="$OPENCODE_AUTH_DIR/auth.json"

if [[ ! -f "$OPENCODE_AUTH_FILE" ]]; then
    echo "==> Writing OpenCode auth file..."
    mkdir -p "$OPENCODE_AUTH_DIR"
    cat > "$OPENCODE_AUTH_FILE" <<EOF
{
  "opencode-go": {
    "type": "api",
    "key": "${OPENCODE_API_KEY}"
  }
}
EOF
    chown -R "$USER:$USER" "$OPENCODE_AUTH_DIR"
    chmod 600 "$OPENCODE_AUTH_FILE"
else
    echo "==> OpenCode auth file already exists."
fi

echo "==> Auth setup complete."
