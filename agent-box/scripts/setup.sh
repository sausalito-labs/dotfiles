#!/usr/bin/env bash
# Interactive one-time setup for the NixOS agent box.
# Run this as root after the first NixOS boot.

set -euo pipefail

USER="agent"
HOME_DIR="/home/agent"
SECRETS_DIR="/var/lib/agent-setup"
SECRETS_FILE="$SECRETS_DIR/secrets.env"

if [[ "$EUID" -ne 0 ]]; then
    echo "ERROR: Run this script as root (e.g., sudo /etc/nixos/dotfiles/agent-box/scripts/setup.sh)" >&2
    exit 1
fi

echo "============================================================"
echo " NixOS Agent Box - First-Time Setup"
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
/etc/nixos/dotfiles/agent-box/scripts/setup-secrets.sh

# Make sure the OpenCode service sees the new secrets.
systemctl restart opencode

# -----------------------------------------------------------------------------
# Inject agent instructions into OpenCode
# -----------------------------------------------------------------------------
mkdir -p /home/agent/.config/opencode
if [[ -f /etc/nixos/dotfiles/agent-box/AGENTS.md ]]; then
    # AGENT_BOX contains the agent-box specific rules. It is loaded via
    # opencode.json so the clean AGENTS.md stays free for custom prompts.
    ln -sf /etc/nixos/dotfiles/agent-box/AGENTS.md /home/agent/.config/opencode/AGENT_BOX
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
# Optional: Godot export templates
# -----------------------------------------------------------------------------
echo
echo "The game workflow is available at /etc/nixos/dotfiles/agent-box/workflows/game"
echo "Enter it with: enter-workflow.sh game"
echo

read -rp "Install Godot 4 export templates now? [Y/n] " INSTALL_TEMPLATES </dev/tty
INSTALL_TEMPLATES=${INSTALL_TEMPLATES:-Y}

if [[ "$INSTALL_TEMPLATES" =~ ^[Yy]$ ]]; then
    echo "==> Installing Godot export templates..."
    sudo -u "$USER" mkdir -p "$HOME_DIR/.local/share/godot/export_templates"
    sudo -u "$USER" bash -c '
        cd ~/.local/share/godot/export_templates
        curl -LO https://downloads.tuxfamily.org/godotengine/4.3/Godot_v4.3-stable_export_templates.tpz
        unzip -o Godot_v4.3-stable_export_templates.tpz
        mv -f 4.3 4.3.stable
    '
fi

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
echo "GitHub CLI is installed but not yet authenticated."
echo "Log in via the website with:"
echo "  sudo -u agent gh auth login"
echo
echo "Access from the tailnet:"
echo "  OpenCode: http://agent-box:4096"
