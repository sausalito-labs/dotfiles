#!/usr/bin/env bash
# One-script installer for the agent box.
#
# This installer will:
#   - If not on NixOS: wipe the disk, install NixOS via nixos-infect, reboot,
#     then continue automatically.
#   - If already on NixOS: clone this repo, build the agent box config, run
#     interactive setup, and disable root SSH.
#
# WARNING: The nixos-infect phase wipes the entire disk. Only run this on a
# machine you are willing to erase (e.g., a fresh VPS or a throwaway VM).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/sausalito-labs/dotfiles/master/agent-box/scripts/install.sh | bash
#
# Options:
#   --yes        Skip the confirmation prompt.
#   --dry-run    Print what would happen and exit without changing anything.
#
# Environment variables:
#   NIX_CHANNEL  e.g. nixos-24.11 (defaults to latest stable from channels.nixos.org)
#   AUTO_YES=1   Same as --yes

set -euo pipefail

REPO_URL="https://github.com/sausalito-labs/dotfiles.git"
INSTALL_URL="https://raw.githubusercontent.com/sausalito-labs/dotfiles/master/agent-box/scripts/install.sh"
REPO_DIR="/etc/nixos/dotfiles"
FLAKE_DIR="/etc/nixos/dotfiles/agent-box"
HOST_DIR="/etc/nixos/dotfiles/agent-box/hosts/agent-box"
SCRIPT_PATH="/root/agent-box-install.sh"
PHASE2_NIX="/etc/nixos/agent-box-phase2.nix"

DRY_RUN=0
AUTO_YES="${AUTO_YES:-0}"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [phase2]

Options:
  --dry-run    Print the plan and exit without making changes.
  --yes        Skip the confirmation prompt before nixos-infect.
  -h, --help   Show this help message.

Environment:
  NIX_CHANNEL  NixOS channel for nixos-infect (default: latest stable).
  AUTO_YES=1   Same as --yes.
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
        phase2)
            phase2
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--dry-run] [--yes] [phase2]" >&2
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

get_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || echo "<your-server-ip>"
}

get_os_id() {
    if [[ -f /etc/os-release ]]; then
        grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"'
    fi
}

get_latest_stable_channel() {
    # Try to detect the latest stable NixOS channel from the public S3 bucket.
    # If this fails or returns nothing, leave NIX_CHANNEL blank so nixos-infect
    # uses its own default.
    curl -fsSL "https://nix-channels.s3.amazonaws.com/" 2>/dev/null \
        | grep -oE 'nixos-[0-9]+\.[0-9]+' \
        | sort -V -u \
        | tail -1 || true
}

persist_script() {
    if [[ -f "$0" && "$0" != "/dev/stdin" && "$0" != "bash" && "$0" != "-bash" ]]; then
        cp "$0" "$SCRIPT_PATH"
    else
        curl -fsSL "$INSTALL_URL" -o "$SCRIPT_PATH"
    fi
    chmod +x "$SCRIPT_PATH"
}

write_phase2_service() {
    cat > "$PHASE2_NIX" <<'EOF'
{ ... }:

{
  systemd.services.agent-box-phase2 = {
    description = "Agent Box phase 2 bootstrap";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/root/agent-box-install.sh phase2";
      StandardOutput = "journal";
      StandardError = "journal";
    };

    unitConfig = {
      ConditionPathExists = "/root/agent-box-install.sh";
    };
  };
}
EOF
    echo "==> Wrote phase 2 systemd trigger to $PHASE2_NIX"
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

# ---------------------------------------------------------------------------
# OS / safety checks
# ---------------------------------------------------------------------------
check_can_infect() {
    local os_kernel
    os_kernel="$(uname -s)"

    if [[ "$os_kernel" != "Linux" ]]; then
        echo "ERROR: nixos-infect requires Linux. Detected: $os_kernel" >&2
        echo "If you already have NixOS installed, run this script there and it will skip nixos-infect." >&2
        echo "Otherwise, run this on a fresh Debian/Ubuntu VPS or inside a Linux VM." >&2
        return 1
    fi

    local os_id
    os_id="$(get_os_id)"
    case "$os_id" in
        debian|ubuntu)
            return 0
            ;;
        *)
            echo "ERROR: This installer uses nixos-infect, which only supports Debian/Ubuntu for unattended installs." >&2
            echo "Detected OS: ${os_id:-unknown}" >&2
            echo "If you already have NixOS installed, run this script there and it will skip nixos-infect." >&2
            return 1
            ;;
    esac
}

confirm_infect() {
    if [[ "$AUTO_YES" == "1" ]]; then
        return 0
    fi

    cat <<EOF

WARNING: This will wipe the entire disk on $(hostname) and install NixOS.
This is intended for a fresh VPS or throwaway VM, NOT your laptop or main machine.
EOF
    local answer=""
    read -rp "Continue? [y/N] " answer </dev/tty || true
    [[ "$answer" =~ ^[Yy]$ ]]
}

print_plan() {
    echo "Detected kernel: $(uname -s)"
    echo "NixOS: $(is_nixos && echo yes || echo no)"
    echo

    if is_nixos; then
        echo "Plan:"
        echo "  - skip nixos-infect (already on NixOS)"
        echo "  - clone $REPO_URL to $REPO_DIR"
        echo "  - generate $HOST_DIR/hardware-configuration.nix"
        echo "  - lock flake inputs into $FLAKE_DIR/flake.lock"
        echo "  - run nixos-rebuild switch --flake $FLAKE_DIR#agent-box"
        echo "  - run interactive setup (Tailscale, OpenCode, password)"
        echo "  - disable root SSH and rebuild"
        echo "  - print: ssh agent@$(get_ip)"
        return
    fi

    if [[ "$(uname -s)" != "Linux" ]]; then
        echo "Plan:"
        echo "  - exit: nixos-infect requires Linux"
        echo "  - if you install NixOS first, re-run this script to bootstrap the agent box"
        return
    fi

    local os_id
    os_id="$(get_os_id)"
    if [[ "$os_id" != "debian" && "$os_id" != "ubuntu" ]]; then
        echo "Plan:"
        echo "  - exit: nixos-infect only supports Debian/Ubuntu (detected: ${os_id:-unknown})"
        echo "  - if you install NixOS first, re-run this script to bootstrap the agent box"
        return
    fi

    local detected_channel
    detected_channel="$(get_latest_stable_channel)"

    echo "Plan:"
    echo "  - run nixos-infect with NIX_CHANNEL=${detected_channel:-<nixos-infect default>}"
    echo "  - reboot"
    echo "  - on first boot, a systemd one-shot service will automatically:"
    echo "      - clone $REPO_URL to $REPO_DIR"
    echo "      - generate hardware configuration"
    echo "      - lock flake inputs into $FLAKE_DIR/flake.lock"
    echo "      - run nixos-rebuild switch --flake $FLAKE_DIR#agent-box"
    echo "      - run interactive setup (Tailscale, OpenCode, password)"
    echo "      - disable root SSH and rebuild"
    echo "      - print: ssh agent@$(get_ip)"
}

# ---------------------------------------------------------------------------
# Phases
# ---------------------------------------------------------------------------
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

    if [[ "$DRY_RUN" == "1" ]]; then
        echo "==> Dry run mode. Nothing will be changed."
        print_plan
        exit 0
    fi

    if ! check_can_infect; then
        exit 1
    fi

    if ! confirm_infect; then
        echo "Aborted."
        exit 0
    fi

    NIX_CHANNEL="${NIX_CHANNEL:-$(get_latest_stable_channel)}"
    echo "==> Using NixOS channel: ${NIX_CHANNEL:-<nixos-infect default>}"

    if mount | grep -q "on /tmp type tmpfs"; then
        echo "==> /tmp is tmpfs; telling nixos-infect to skip its swap step"
        export NO_SWAP=1
    fi

    echo "==> Persisting installer for phase 2..."
    persist_script
    write_phase2_service

    echo "==> Running nixos-infect..."
    curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect \
        | NIX_CHANNEL="$NIX_CHANNEL" NIXOS_IMPORT="$PHASE2_NIX" bash -x 2>&1 | tee /tmp/nixos-infect.log

    echo
    echo "============================================================"
    echo " Phase 1 complete. Rebooting into NixOS."
    echo " Phase 2 will run automatically on first boot via systemd."
    echo "============================================================"
    reboot
}

phase2() {
    echo "============================================================"
    echo " Agent Box Installer - Phase 2: Bootstrap"
    echo "============================================================"
    echo

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

    if [[ ! -f "$FLAKE_DIR/flake.lock" ]]; then
        echo "==> Locking flake inputs..."
        nix-shell -p git --run "nix --extra-experimental-features 'nix-command flakes' flake lock $FLAKE_DIR"
    else
        echo "==> flake.lock already exists."
    fi

    echo "==> Committing bootstrap changes..."
    nix-shell -p git --run "
        git -C \"$REPO_DIR\" config user.email >/dev/null 2>&1 || git -C \"$REPO_DIR\" config user.email \"agent-box@localhost\"
        git -C \"$REPO_DIR\" config user.name >/dev/null 2>&1 || git -C \"$REPO_DIR\" config user.name \"Agent Box\"
        if git -C \"$REPO_DIR\" status --short | grep -q .; then
            git -C \"$REPO_DIR\" add -A
            git -C \"$REPO_DIR\" commit -m \"agent-box: bootstrap\"
        fi
    "

    echo "==> Applying initial NixOS configuration..."
    nix-shell -p git --run "nixos-rebuild switch --flake $FLAKE_DIR#agent-box"

    if [[ -z "${INVOCATION_ID:-}" ]]; then
        echo "==> Running interactive setup..."
        "$FLAKE_DIR/scripts/setup.sh"

        echo "==> Disabling root SSH..."
        disable_root_ssh
        git -C "$REPO_DIR" add -A
        git -C "$REPO_DIR" commit -m "agent-box: disable root SSH after setup"

        echo "==> Rebuilding with root SSH disabled..."
        nix-shell -p git --run "nixos-rebuild switch --flake $FLAKE_DIR#agent-box"

        echo
        echo "============================================================"
        echo " Setup complete."
        echo "============================================================"
        echo "Root SSH is now disabled. Log in as agent:"
        echo "  ssh agent@$(get_ip)"
        echo
    else
        echo "==> Running under systemd without a TTY; skipping interactive setup."
        echo "    Root SSH remains enabled. After this bootstrap finishes, log in as root and run:"
        echo "      $FLAKE_DIR/scripts/setup.sh"

        echo
        echo "============================================================"
        echo " Bootstrap complete."
        echo "============================================================"
        echo "Root SSH is still enabled. Log in as root and run setup:"
        echo "  $FLAKE_DIR/scripts/setup.sh"
        echo
    fi

    echo "==> Cleaning up bootstrap triggers..."
    rm -f "$SCRIPT_PATH"
    rm -f "$PHASE2_NIX"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" == "1" ]]; then
    print_plan
    exit 0
fi

if is_nixos; then
    phase2
else
    phase1
fi
