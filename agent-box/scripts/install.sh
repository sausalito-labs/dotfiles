#!/usr/bin/env bash
# One-script installer for the agent box.
#
# Run this as root on a fresh Debian/Ubuntu VPS. It will:
#   1. Install NixOS via nixos-infect (if not already on NixOS).
#   2. After reboot, clone this repo and build the agent box config.
#   3. Run interactive setup (password, secrets).
#   4. Disable root SSH and rebuild.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/sausalito-labs/dotfiles/master/agent-box/scripts/install.sh | bash
# Or, after downloading:
#   ./install.sh

set -euo pipefail

REPO_URL="https://github.com/sausalito-labs/dotfiles.git"
INSTALL_URL="https://raw.githubusercontent.com/sausalito-labs/dotfiles/master/agent-box/scripts/install.sh"
REPO_DIR="/etc/nixos/dotfiles"
FLAKE_DIR="/etc/nixos/dotfiles/agent-box"
HOST_DIR="/etc/nixos/dotfiles/agent-box/hosts/agent-box"
SCRIPT_PATH="/root/agent-box-install.sh"
BASH_PROFILE="/root/.bash_profile"

is_nixos() {
    [[ -f /etc/NIXOS ]]
}

get_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || echo "<your-server-ip>"
}

persist_script() {
    if [[ -f "$0" && "$0" != "/dev/stdin" && "$0" != "bash" && "$0" != "-bash" ]]; then
        cp "$0" "$SCRIPT_PATH"
    else
        curl -fsSL "$INSTALL_URL" -o "$SCRIPT_PATH"
    fi
    chmod +x "$SCRIPT_PATH"
}

schedule_phase2() {
    cat >> "$BASH_PROFILE" <<EOF

# agent-box install phase 2 (auto-removed after run)
if [[ -x "$SCRIPT_PATH" ]]; then
    "$SCRIPT_PATH" phase2
fi
EOF
}

remove_phase2_hook() {
    if [[ -f "$BASH_PROFILE" ]]; then
        sed -i "\|# agent-box install phase 2|,/fi/d" "$BASH_PROFILE" || true
    fi
}

disable_root_ssh() {
    local config="$HOST_DIR/configuration.nix"
    if grep -q 'services.openssh.settings.PermitRootLogin = "yes";' "$config"; then
        sed -i 's/services.openssh.settings.PermitRootLogin = "yes";/services.openssh.settings.PermitRootLogin = "no";/' "$config"
        echo "==> Disabled root SSH in $config"
    else
        echo "WARNING: Could not find root SSH override to disable." >&2
    fi
}

phase1() {
    echo "============================================================"
    echo " Agent Box Installer - Phase 1: Install NixOS"
    echo "============================================================"
    echo

    if is_nixos; then
        echo "Already on NixOS. Skipping phase 1."
        phase2
        return
    fi

    echo "==> Running nixos-infect..."
    curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect \
        | NIX_CHANNEL=nixos-24.11 bash -x 2>&1 | tee /tmp/nixos-infect.log

    echo "==> Persisting installer for phase 2..."
    persist_script
    schedule_phase2

    echo
    echo "============================================================"
    echo " Phase 1 complete. Rebooting into NixOS."
    echo " After reboot, SSH back in as root to continue."
    echo "============================================================"
    reboot
}

phase2() {
    echo "============================================================"
    echo " Agent Box Installer - Phase 2: Bootstrap"
    echo "============================================================"
    echo

    remove_phase2_hook

    if [[ -d "$REPO_DIR" ]]; then
        echo "==> $REPO_DIR already exists. Skipping clone."
    else
        echo "==> Backing up default /etc/nixos and cloning repo..."
        mv /etc/nixos /etc/nixos.bak
        nix-shell -p git --run "git clone $REPO_URL $REPO_DIR"
    fi

    if [[ ! -f "$HOST_DIR/hardware-configuration.nix" ]]; then
        echo "==> Generating hardware configuration..."
        nixos-generate-config --show-hardware-config > "$HOST_DIR/hardware-configuration.nix"
    else
        echo "==> Hardware configuration already exists."
    fi

    if git -C "$REPO_DIR" status --short | grep -q .; then
        echo "==> Committing bootstrap changes..."
        git -C "$REPO_DIR" add -A
        git -C "$REPO_DIR" commit -m "agent-box: bootstrap"
    fi

    echo "==> Applying initial NixOS configuration..."
    nix-shell -p git --run "nixos-rebuild switch --flake $FLAKE_DIR#agent-box"

    echo "==> Running interactive setup..."
    "$FLAKE_DIR/scripts/setup.sh"

    echo "==> Disabling root SSH..."
    disable_root_ssh
    git -C "$REPO_DIR" add -A
    git -C "$REPO_DIR" commit -m "agent-box: disable root SSH after setup"

    echo "==> Rebuilding with root SSH disabled..."
    nix-shell -p git --run "nixos-rebuild switch --flake $FLAKE_DIR#agent-box"

    rm -f "$SCRIPT_PATH"

    echo
    echo "============================================================"
    echo " Setup complete."
    echo "============================================================"
    echo "Root SSH is now disabled. Log in as agent:"
    echo "  ssh agent@$(get_ip)"
    echo
}

case "${1:-}" in
    phase2)
        phase2
        ;;
    *)
        phase1
        ;;
esac
