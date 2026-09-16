#!/usr/bin/env bash
# Interactive one-time setup for the agent box (Debian + Nix).
# Run this as root after scripts/install.sh.

set -euo pipefail

USER="agent"
HOME_DIR="/home/agent"
SECRETS_DIR="/var/lib/agent-setup"
SECRETS_FILE="$SECRETS_DIR/secrets.env"

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run this script as root (e.g., sudo /opt/agent-box/agent-box/scripts/setup.sh)" >&2
    exit 1
fi

echo "============================================================"
echo " Agent Box - First-Time Setup"
echo "============================================================"
echo

# -----------------------------------------------------------------------------
# Collect secrets interactively
# -----------------------------------------------------------------------------
read -rsp "Tailscale auth key: " TAILSCALE_AUTHKEY </dev/tty
echo
read -rsp "OpenCode API key: " OPENCODE_API_KEY </dev/tty
echo
read -rsp "OpenCode web UI password: " OPENCODE_PASSWORD </dev/tty
echo
read -rsp "Set password for user '$USER': " AGENT_PASSWORD </dev/tty
echo

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

cat > "$SECRETS_FILE" <<EOF
TAILSCALE_AUTHKEY=${TAILSCALE_AUTHKEY}
OPENCODE_API_KEY=${OPENCODE_API_KEY}
EOF
chmod 600 "$SECRETS_DIR/secrets.env"

# -----------------------------------------------------------------------------
# Set agent user password
# -----------------------------------------------------------------------------
echo "$USER:$AGENT_PASSWORD" | chpasswd

# -----------------------------------------------------------------------------
# Set OpenCode web password
# -----------------------------------------------------------------------------
mkdir -p /var/lib/opencode
chown agent:agent /var/lib/opencode
cat > /var/lib/opencode/opencode.env <<EOF
OPENCODE_SERVER_PASSWORD=${OPENCODE_PASSWORD}
EOF
chmod 600 /var/lib/opencode/opencode.env

# -----------------------------------------------------------------------------
# Run the automated auth setup
# -----------------------------------------------------------------------------
/opt/agent-box/agent-box/scripts/setup-secrets.sh

# -----------------------------------------------------------------------------
# GitHub CLI (device flow: complete in any browser, from anywhere)
# -----------------------------------------------------------------------------
AGENT_PATH="$HOME_DIR/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"
if ! sudo -u "$USER" env PATH="$AGENT_PATH" gh auth status &>/dev/null; then
    echo
    echo "==> GitHub login: a one-time code will be shown."
    echo "    Open https://github.com/login/device on any device and enter it."
    if ! sudo -u "$USER" env PATH="$AGENT_PATH" \
        gh auth login --hostname github.com --git-protocol https --web; then
        echo "    Warning: GitHub login skipped or failed. Run it later with:"
        echo "    sudo -u agent gh auth login --hostname github.com --git-protocol https --web"
    fi
else
    echo "==> GitHub CLI already authenticated."
fi

# Make sure the OpenCode service sees the new secrets.
systemctl restart opencode

# -----------------------------------------------------------------------------
# Inject agent instructions into OpenCode
# -----------------------------------------------------------------------------
mkdir -p /home/agent/.config/opencode
if [[ -f /opt/agent-box/agent-box/AGENTS.md ]]; then
    # AGENT_BOX contains the agent-box specific rules. It is loaded via
    # opencode.json so the clean AGENTS.md stays free for custom prompts.
    ln -sf /opt/agent-box/agent-box/AGENTS.md /home/agent/.config/opencode/AGENT_BOX
    chown -R agent:agent /home/agent/.config/opencode
    echo "==> Linked agent-box instructions to ~/.config/opencode/AGENT_BOX"
fi

# Create a clean AGENTS.md for custom system prompts if one does not exist.
if [[ ! -f /home/agent/.config/opencode/AGENTS.md ]]; then
    cat > /home/agent/.config/opencode/AGENTS.md <<'EOF'
# System Prompts

Add custom system prompts here.
EOF
    chown agent:agent /home/agent/.config/opencode/AGENTS.md
    echo "==> Created clean ~/.config/opencode/AGENTS.md"
fi

# Load AGENT_BOX as an instruction file. Combined with AGENTS.md by OpenCode.
cat > /home/agent/.config/opencode/opencode.json <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["/home/agent/.config/opencode/AGENT_BOX"]
}
EOF
chown agent:agent /home/agent/.config/opencode/opencode.json
echo "==> Wrote ~/.config/opencode/opencode.json"

# -----------------------------------------------------------------------------
# Workspace
# -----------------------------------------------------------------------------
echo "==> Creating the workspace at $HOME_DIR/projects..."
mkdir -p "$HOME_DIR/projects"
chown "$USER:$USER" "$HOME_DIR/projects"

# -----------------------------------------------------------------------------
# Tailscale Funnel: public HTTPS URL for the web UI (no client installs)
# -----------------------------------------------------------------------------
echo "==> Exposing the OpenCode web UI via Tailscale Funnel (public HTTPS)..."
FUNNEL_URL=""
FUNNEL_ENABLE_URL=""
if FUNNEL_OUTPUT="$(tailscale funnel --bg 4096 2>&1)"; then
    echo "$FUNNEL_OUTPUT"
    FUNNEL_ENABLE_URL="$(printf '%s\n' "$FUNNEL_OUTPUT" \
        | grep -oE 'https://login\.tailscale\.com/f/funnel\?\S+' | head -1 || true)"
    FUNNEL_URL="$(tailscale funnel status 2>/dev/null \
        | grep -oE 'https://[^ ]+\.ts\.net' | head -1 || true)"
else
    echo "$FUNNEL_OUTPUT"
    echo "    Warning: could not enable Funnel. Run it later with:"
    echo "    sudo tailscale funnel --bg 4096"
    echo "    (HTTPS must be enabled for the tailnet: https://login.tailscale.com/admin/dns)"
fi

# -----------------------------------------------------------------------------
# Optional: Godot export templates
# -----------------------------------------------------------------------------
echo
echo "The game workflow is available at /opt/agent-box/agent-box/workflows/game"
echo "Enter it with: enter-workflow.sh game"
echo
echo "Godot export templates are installed on demand by the agent (see AGENTS.md)."

echo
echo "============================================================"
echo " Setup complete."
echo "============================================================"
echo "Tailscale status:"
tailscale status 2>/dev/null || true
echo
echo "Services:"
systemctl status opencode --no-pager 2>/dev/null | head -5
echo
NODE_NAME="$(tailscale status 2>/dev/null | awk 'NR==1{print $2}')"
echo
echo "Workspace (~/projects):"
echo "  /home/agent/projects  (create repos here, pick the folder in the web UI)"
echo
if [[ -n "$FUNNEL_ENABLE_URL" ]]; then
    echo "IMPORTANT: Funnel needs a one-time tailnet approval. Open this link:"
    echo "  $FUNNEL_ENABLE_URL"
    echo "  Then reload the web UI below (cert takes ~30-60s to issue)."
    echo
fi
if [[ -n "$FUNNEL_URL" ]]; then
    echo "OpenCode web UI (public, no install needed):"
    echo "  $FUNNEL_URL"
    echo "  user: opencode / your OpenCode web UI password"
fi
if [[ -n "$NODE_NAME" ]]; then
    echo "OpenCode web UI (inside the tailnet):"
    echo "  http://$NODE_NAME:4096"
fi
