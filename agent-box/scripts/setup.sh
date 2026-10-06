#!/usr/bin/env bash
# Interactive one-time setup for the agent box (Debian + Nix).
# Run this as root after scripts/install.sh.

set -euo pipefail

USER="agent"
HOME_DIR="/home/agent"
SECRETS_DIR="/var/lib/agent-setup"
SECRETS_FILE="$SECRETS_DIR/secrets.env"
CLAUDE_BIN="$HOME_DIR/.local/bin/claude"
AGENT_PATH="$HOME_DIR/.local/bin:$HOME_DIR/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/opt/agent-box/agent-box/scripts:/usr/local/bin:/usr/bin:/bin"

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
read -rsp "Set password for user '$USER': " AGENT_PASSWORD </dev/tty
echo

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

cat > "$SECRETS_FILE" <<EOF
TAILSCALE_AUTHKEY=${TAILSCALE_AUTHKEY}
EOF
chmod 600 "$SECRETS_DIR/secrets.env"

# -----------------------------------------------------------------------------
# Set agent user password
# -----------------------------------------------------------------------------
echo "$USER:$AGENT_PASSWORD" | chpasswd

# -----------------------------------------------------------------------------
# Run the automated auth setup (Tailscale, GitHub)
# -----------------------------------------------------------------------------
/opt/agent-box/agent-box/scripts/setup-secrets.sh

# -----------------------------------------------------------------------------
# GitHub CLI (device flow: complete in any browser, from anywhere)
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Claude Code login (Remote Control requires a claude.ai subscription login;
# API keys and setup-token do NOT work for Remote Control)
# -----------------------------------------------------------------------------
echo
echo "==> Claude Code login (claude.ai subscription)"
if sudo -u "$USER" env HOME="$HOME_DIR" PATH="$AGENT_PATH" \
    "$CLAUDE_BIN" auth status &>/dev/null; then
    echo "==> Claude Code already authenticated."
else
    echo "    A browser URL and code will appear. Open the URL on any device and"
    echo "    paste the code back here (this SSH session has no local browser)."
    if ! script -qefc \
        "sudo -u $USER env HOME=$HOME_DIR PATH=$AGENT_PATH $CLAUDE_BIN auth login" \
        /dev/null </dev/tty; then
        echo "    Warning: Claude login skipped or failed. Run it later as agent:"
        echo "      sudo -u agent env HOME=/home/agent $CLAUDE_BIN auth login"
    fi
fi

# -----------------------------------------------------------------------------
# Accept Remote Control's one-time confirmation and workspace trust so the
# headless service can start. Start it once interactively, then Ctrl+C.
# -----------------------------------------------------------------------------
if [[ -r /dev/tty ]]; then
    echo
    echo "==> Enabling Remote Control"
    echo "    Answer 'y' if asked, then press Ctrl+C to stop. setup will then start"
    echo "    the service in the background."
    script -qefc \
        "sudo -u $USER env HOME=$HOME_DIR PATH=$AGENT_PATH $CLAUDE_BIN remote-control --name agent-box --spawn same-dir" \
        /dev/null </dev/tty || true
fi

# -----------------------------------------------------------------------------
# Inject agent instructions into Claude Code
# -----------------------------------------------------------------------------
mkdir -p /home/agent/.claude
if [[ -f /opt/agent-box/agent-box/AGENTS.md ]]; then
    # Claude Code reads ~/.claude/CLAUDE.md as user-level memory. Symlink the
    # repo's AGENTS.md so the box instructions follow the repo.
    ln -sf /opt/agent-box/agent-box/AGENTS.md /home/agent/.claude/CLAUDE.md
    chown -R agent:agent /home/agent/.claude
    echo "==> Linked agent-box instructions to ~/.claude/CLAUDE.md"
fi

# -----------------------------------------------------------------------------
# Workspace
# -----------------------------------------------------------------------------
echo "==> Creating the workspace at $HOME_DIR/projects..."
mkdir -p "$HOME_DIR/projects"
chown "$USER:$USER" "$HOME_DIR/projects"

# -----------------------------------------------------------------------------
# Start the Remote Control service
# -----------------------------------------------------------------------------
echo "==> Starting Claude Code Remote Control service..."
systemctl enable --now claude-remote-control

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
echo "Service:"
systemctl status claude-remote-control --no-pager 2>/dev/null | head -5
echo
NODE_NAME="$(tailscale status 2>/dev/null | awk 'NR==1{print $2}')"
echo "Workspace (~/projects):"
echo "  /home/agent/projects  (clone repos here; the session starts in this dir)"
echo
echo "Reach Claude Code from any device:"
echo "  1. Open https://claude.ai/code (or the Claude app, Code tab)"
echo "  2. Open the session named 'agent-box'"
echo
if [[ -n "$NODE_NAME" ]]; then
    echo "Admin over the tailnet:  ssh agent@$NODE_NAME"
    echo
fi
echo "Note: Remote Control uses your claude.ai subscription login, and it stores"
echo "      the session transcript on Anthropic's servers. If the login expires,"
echo "      sessions stop until you SSH in, run 'claude', and use /login."
