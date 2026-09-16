#!/usr/bin/env bash
# One-command installer for the agent box on Debian/Ubuntu with plain Nix.
#
# Unlike the old nixos-infect flow, this does not replace the operating system.
# It installs multi-user Nix on the distro the provider already gives you and
# layers the agent box on top, so root access stays under the provider's control
# and works from any device.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/sausalito-labs/dotfiles/master/agent-box/scripts/install.sh | bash
#
# Options:
#   --yes        Skip the confirmation prompt.
#   --dry-run    Print what would happen and exit without changing anything.

set -euo pipefail

REPO_TARBALL_URL="https://github.com/sausalito-labs/dotfiles/archive/refs/heads/master.tar.gz"
REPO_DIR="/opt/agent-box"
AGENT_DIR="/opt/agent-box/agent-box"
NIX_BIN="/nix/var/nix/profiles/default/bin/nix"
AGENT_USER="agent"
AGENT_HOME="/home/agent"

DRY_RUN=0
AUTO_YES="${AUTO_YES:-0}"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --dry-run    Print the plan and exit without making changes.
  --yes        Skip the confirmation prompt.
  -h, --help   Show this help message.
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --yes)
            AUTO_YES=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--dry-run] [--yes]" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
is_nixos() {
    [[ -f /etc/NIXOS ]]
}

get_os_id() {
    if [[ -f /etc/os-release ]]; then
        grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"'
    fi
}

get_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || echo "<your-server-ip>"
}

step() {
    echo
    echo "==> $*"
}

run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "    [dry-run] $*"
    else
        "$@"
    fi
}

# ---------------------------------------------------------------------------
# OS / safety checks
# ---------------------------------------------------------------------------
check_prereqs() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        echo "ERROR: The agent box installer requires Linux (Debian/Ubuntu)." >&2
        echo "Detected: $(uname -s)" >&2
        exit 1
    fi

    if [[ "$(uname -m)" != "x86_64" ]]; then
        echo "ERROR: x86_64-linux is required (opencode ships a linux-x64 binary)." >&2
        echo "Detected: $(uname -m)" >&2
        exit 1
    fi

    if [[ "$EUID" -ne 0 ]]; then
        echo "ERROR: Run this as root." >&2
        exit 1
    fi

    local os_id
    os_id="$(get_os_id)"
    case "$os_id" in
        debian|ubuntu)
            ;;
        *)
            echo "ERROR: This installer targets Debian/Ubuntu. Detected: ${os_id:-unknown}" >&2
            exit 1
            ;;
    esac

    if is_nixos; then
        echo "ERROR: This box is running NixOS, which is no longer used." >&2
        echo "Reimage it to Debian/Ubuntu (netcup panel), then rerun this installer." >&2
        exit 1
    fi
}

confirm_install() {
    if [[ "$AUTO_YES" == "1" ]]; then
        return 0
    fi

    cat <<EOF

This installs Nix and the agent box on $(hostname) ($(get_ip)).
It will add the '$AGENT_USER' user, install Nix, Tailscale, a firewall,
and run the OpenCode web service. Your OS and root access are untouched.

EOF
    local answer=""
    read -rp "Continue? [y/N] " answer </dev/tty || true
    [[ "$answer" =~ ^[Yy]$ ]]
}

# ---------------------------------------------------------------------------
# Install steps
# ---------------------------------------------------------------------------
ensure_base_pkgs() {
    step "Installing base packages (curl, ufw)..."
    run apt-get update -y
    run apt-get install -y curl ufw

    if [[ "$(hostname)" != "agent-box" ]]; then
        step "Setting hostname to agent-box..."
        run hostnamectl set-hostname agent-box
        if ! grep -q 'agent-box' /etc/hosts; then
            echo "127.0.0.1 agent-box" >> /etc/hosts
        fi
    fi
}

ensure_nix() {
    if [[ -x "$NIX_BIN" ]] || [[ -n "$(command -v nix)" ]]; then
        step "Nix already installed"
        return
    fi

    step "Installing multi-user Nix (Determinate Nix Installer)..."
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "    [dry-run] curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm"
        return
    fi
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
        | sh -s -- install --no-confirm --extra-conf "experimental-features = nix-command flakes"
}

ensure_agent_user() {
    step "Creating '$AGENT_USER' user..."
    if ! id "$AGENT_USER" &>/dev/null; then
        run useradd -m -s /bin/bash -U "$AGENT_USER"
    fi

    run usermod -aG sudo "$AGENT_USER"
    if getent group nix-users >/dev/null 2>&1; then
        run usermod -aG nix-users "$AGENT_USER"
    fi

    echo "$AGENT_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/agent-box
    chmod 440 /etc/sudoers.d/agent-box

    cat > /etc/profile.d/agent-box.sh <<'EOF'
export PATH="$HOME/.opencode/bin:$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
EOF

    step "Creating state directories..."
    run mkdir -p "$AGENT_HOME/.config/opencode" \
        "$AGENT_HOME/.local/share/opencode" \
        "$AGENT_HOME/.local/share/godot/export_templates" \
        /var/lib/opencode
    run chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.config" "$AGENT_HOME/.local"
    run chown "$AGENT_USER:$AGENT_USER" /var/lib/opencode
}

ensure_repo() {
    step "Fetching dotfiles to $REPO_DIR..."
    local new_dir="${REPO_DIR}.new"
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "    [dry-run] curl -fsSL $REPO_TARBALL_URL | tar -xzf - --strip-components=1 -C $new_dir"
        return
    fi
    rm -rf "$new_dir" "$REPO_DIR"
    mkdir -p "$new_dir"
    curl -fsSL "$REPO_TARBALL_URL" \
        | tar -xzf - --strip-components=1 -C "$new_dir"
    mv "$new_dir" "$REPO_DIR"
    chown -R "$AGENT_USER:$AGENT_USER" "$REPO_DIR"
}

ensure_tailscale() {
    if command -v tailscale >/dev/null 2>&1; then
        step "Tailscale already installed"
        return
    fi
    step "Installing Tailscale..."
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "    [dry-run] curl -fsSL https://tailscale.com/install.sh | sh"
        return
    fi
    curl -fsSL https://tailscale.com/install.sh | sh
}

ensure_firewall() {
    step "Configuring firewall (ufw: allow SSH + tailnet)..."
    run ufw allow 22/tcp
    run ufw allow in on tailscale0
    run ufw --force enable
}

install_profile() {
    step "Building and installing toolchain into '$AGENT_USER' Nix profile..."
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "    [dry-run] sudo -u agent nix profile install $AGENT_DIR#toolchain"
        return
    fi
    sudo -u "$AGENT_USER" env \
        NIX_CONFIG="experimental-features = nix-command flakes" \
        "$NIX_BIN" profile install \
        "$AGENT_DIR#toolchain"
}

install_opencode() {
    step "Installing OpenCode via the official installer (tracking latest)..."
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "    [dry-run] sudo -u agent env HOME=/home/agent bash -c 'curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path'"
        return
    fi
    sudo -u "$AGENT_USER" env HOME="$AGENT_HOME" bash -c \
        'curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path'
}

install_service() {
    step "Installing OpenCode systemd service..."
    if [[ "$DRY_RUN" != "1" ]]; then
        install -m 644 "$AGENT_DIR/services/opencode.service" /etc/systemd/system/opencode.service
        systemctl daemon-reload
        systemctl enable opencode
    fi
}

run_setup() {
    if [[ "$DRY_RUN" == "1" ]]; then
        return
    fi

    if [[ -r /dev/tty ]]; then
        cat <<EOF

============================================================
 Agent box install complete. Starting interactive setup.
============================================================
EOF
        bash "$AGENT_DIR/scripts/setup.sh"
    else
        cat <<EOF

============================================================
 Agent box install complete.
============================================================

No interactive terminal detected, so setup was skipped.
Log in as root and run it manually when ready:

  bash $AGENT_DIR/scripts/setup.sh

It will complete the GitHub login and print the OpenCode web UI
URL (public HTTPS via Tailscale Funnel, plus the tailnet address).
EOF
    fi
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" == "1" ]]; then
    echo "Plan: install multi-user Nix + agent box on this Debian/Ubuntu host."
    echo "  - base packages: curl, ufw"
    echo "  - Determinate Nix (multi-user, flakes enabled)"
    echo "  - user '$AGENT_USER' (sudo, NOPASSWD, nix-users)"
    echo "  - fetch dotfiles (master tarball) to $REPO_DIR"
    echo "  - Tailscale + ufw (allow ssh, trust tailscale0)"
    echo "  - nix profile for '$AGENT_USER': toolchain"
    echo "  - opencode (official installer, latest) to /home/agent/.opencode/bin"
    echo "  - enable opencode.service (started by setup.sh)"
    echo "  - run interactive setup (setup.sh) when the install finishes"
    echo "  - hostname: agent-box"
    exit 0
fi

check_prereqs
confirm_install || {
    echo "Aborted."
    exit 0
}

ensure_base_pkgs
ensure_nix
ensure_agent_user
ensure_repo
ensure_tailscale
ensure_firewall
install_profile
install_opencode
install_service
run_setup
