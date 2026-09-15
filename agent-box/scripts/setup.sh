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
read -rsp "Tailscale/Headscale auth key: " TAILSCALE_AUTHKEY
echo
read -rsp "GitHub personal access token: " GITHUB_TOKEN
echo
read -rsp "OpenCode API key: " OPENCODE_API_KEY
echo
read -rsp "OpenCode web UI password: " OPENCODE_PASSWORD
echo
read -rsp "Set password for user '$USER': " AGENT_PASSWORD
echo

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

cat > "$SECRETS_FILE" <<EOF
TAILSCALE_AUTHKEY=${TAILSCALE_AUTHKEY}
GITHUB_TOKEN=${GITHUB_TOKEN}
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
    ln -sf /etc/nixos/dotfiles/agent-box/AGENTS.md /home/agent/.config/opencode/AGENTS.md
    chown -R agent:agent /home/agent/.config/opencode
    echo "==> Linked agent instructions to ~/.config/opencode/AGENTS.md"
fi

# -----------------------------------------------------------------------------
# Optional: Copy game workflow template
# -----------------------------------------------------------------------------
echo
read -rp "Copy the game workflow template now? [Y/n] " COPY_GAME_WORKFLOW
COPY_GAME_WORKFLOW=${COPY_GAME_WORKFLOW:-Y}

if [[ "$COPY_GAME_WORKFLOW" =~ ^[Yy]$ ]]; then
    echo "==> Copying game workflow template..."
    mkdir -p /etc/nixos/dotfiles/agent-box/workflow
    cp -r /etc/nixos/dotfiles/agent-box/templates/workflow/game /etc/nixos/dotfiles/agent-box/workflow/
    chown -R agent:agent /etc/nixos/dotfiles/agent-box/workflow/game
    echo "Copied. Enter it with: enter-workflow.sh game"
fi

# -----------------------------------------------------------------------------
# Optional: Godot export templates
# -----------------------------------------------------------------------------
echo
read -rp "Install Godot 4 export templates now? [Y/n] " INSTALL_TEMPLATES
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
echo "Access from the tailnet:"
echo "  OpenCode: http://agent-box:4096"
