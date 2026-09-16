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
PHASE2_NIX="/etc/nixos/agent-box-phase2.nix"
BOOTSTRAP_DONE="/etc/agent-box-bootstrap-done"

DRY_RUN=0
AUTO_YES="${AUTO_YES:-0}"
RESET_REPO=0

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [phase2]

Options:
  --dry-run    Print the plan and exit without making changes.
  --yes        Skip the confirmation prompt before nixos-infect.
  --reset      If the repo already exists, reset it to origin/master before
               bootstrapping. Useful for rerunning the installer.
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
        --reset)
            RESET_REPO=1
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

write_phase2_service() {
    mkdir -p /etc/nixos

    # Preserve root access across the disk wipe: bake the current root
    # password hash and SSH keys into the first NixOS system. nixos-infect
    # does not carry /etc/shadow, so without this root would have no password.
    local root_hash="" root_cfg="" root_keys=()
    if [[ -r /etc/shadow ]]; then
        root_hash="$(awk -F: '/^root:/{print $2}' /etc/shadow 2>/dev/null || true)"
        case "$root_hash" in
            ""|"!"|"*"|"!*")
                root_hash=""
                ;;
        esac
    fi
    if [[ -r /root/.ssh/authorized_keys ]]; then
        while IFS= read -r key; do
            [[ -n "$key" ]] || continue
            root_keys+=("$key")
        done < <(grep -v '^#' /root/.ssh/authorized_keys 2>/dev/null || true)
    fi

    if [[ -n "$root_hash" || ${#root_keys[@]} -gt 0 ]]; then
        root_cfg="  users.users.root = {"
        if [[ -n "$root_hash" ]]; then
            root_cfg+=$'\n    hashedPassword = "'"$root_hash"$'";'
        fi
        if [[ ${#root_keys[@]} -gt 0 ]]; then
            root_cfg+=$'\n    openssh.authorizedKeys.keys = ['
            for key in "${root_keys[@]}"; do
                [[ -n "$key" ]] || continue
                # Indented strings (''...'') let keys contain quotes/backslashes
                # literally, same as nixos-infect uses. Only '' needs escaping.
                key_esc=$(printf '%s' "$key" | tr -d '\r' | sed "s/''/'''/g")
                root_cfg+=$'\n      '"''${key_esc}''"
            done
            root_cfg+=$'\n    ];'
        fi
        root_cfg+=$'\n  };'
        echo "==> Preserving root password and SSH keys in phase 2 config"
    else
        echo "WARNING: No usable root password or SSH keys found; root may be inaccessible after the switch." >&2
    fi

    cat > "$PHASE2_NIX" <<EOF
{ pkgs, ... }:

{
  # The first-built NixOS system needs these for the phase 2 bootstrap:
  # curl fetches this installer at first boot, git clones the repo.
  environment.systemPackages = [ pkgs.curl pkgs.git ];

$root_cfg
  systemd.services.agent-box-phase2 = {
    description = "Agent Box phase 2 bootstrap";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = [ "/run/current-system/sw" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Self-healing trigger: re-fetch this installer at first boot instead of
      # relying on a copy surviving the reboot. Cache-Control busts stale CDN
      # copies. Runs once via /etc/agent-box-bootstrap-done.
      # Systemd services do not get /run/current-system/sw/bin on PATH, so use
      # absolute store paths for the fetch and export PATH for the script run.
      ExecStart = ''\${pkgs.bash}/bin/bash -c 'export PATH="/run/current-system/sw/bin:/run/current-system/sw/sbin:/usr/bin:/bin:/usr/sbin:/sbin"; if [ ! -e "$BOOTSTRAP_DONE" ]; then \${pkgs.curl}/bin/curl -fsSL -H "Cache-Control: no-cache" "$INSTALL_URL" -o /root/agent-box-install.sh && \${pkgs.bash}/bin/bash /root/agent-box-install.sh phase2; fi' '';
      Restart = "on-failure";
      RestartSec = "10s";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };
}
EOF
    echo "==> Wrote phase 2 systemd trigger to $PHASE2_NIX"

    # Validate the generated module parses as Nix before nixos-infect wipes the
    # disk. This catches quoting bugs in preserved keys/passwords early.
    local nix_parse=""
    if command -v nix-instantiate >/dev/null 2>&1; then
        nix_parse="$(command -v nix-instantiate)"
    elif [[ -x /nix/var/nix/profiles/default/bin/nix-instantiate ]]; then
        nix_parse="/nix/var/nix/profiles/default/bin/nix-instantiate"
    fi

    if [[ -n "$nix_parse" ]]; then
        if ! "$nix_parse" --parse "$PHASE2_NIX" >/dev/null 2>&1; then
            echo "ERROR: generated phase 2 module failed Nix syntax check:" >&2
            "$nix_parse" --parse "$PHASE2_NIX" >&2 || true
            exit 1
        fi
        echo "==> Phase 2 module passes Nix syntax check"
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
    if [[ "$RESET_REPO" == "1" ]]; then
        echo "  - reset $REPO_DIR to origin/master"
    fi
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

    echo "==> Writing phase 2 systemd trigger..."
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

    # Systemd services do not inherit the NixOS login PATH or NIX_PATH. Make
    # sure git/nix/nixos-rebuild/nixos-generate-config resolve regardless of
    # how phase 2 is invoked.
    export PATH="/run/current-system/sw/bin:/run/current-system/sw/sbin:$PATH"
    if [[ -d /nix/var/nix/profiles/per-user/root/channels/nixos ]]; then
        export NIX_PATH="nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos${NIX_PATH:+:$NIX_PATH}"
    fi

    if [[ -d "$REPO_DIR" ]]; then
        if [[ "$RESET_REPO" == "1" ]]; then
            echo "==> Resetting $REPO_DIR to origin/master..."
            git -C "$REPO_DIR" fetch origin
            git -C "$REPO_DIR" reset --hard origin/master
        else
            echo "==> $REPO_DIR already exists. Skipping clone."
        fi
    else
        echo "==> Backing up default /etc/nixos and cloning repo..."
        mv /etc/nixos /etc/nixos.bak
        git clone "$REPO_URL" "$REPO_DIR"
    fi

    echo "==> Regenerating hardware configuration..."
    nixos-generate-config --show-hardware-config > "$HOST_DIR/hardware-configuration.nix"

    echo "==> Detecting boot disk..."
    root_part="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
    if [[ -n "$root_part" ]]; then
        root_disk="$(lsblk -no pkname "$root_part" 2>/dev/null || true)"
        if [[ -n "$root_disk" && "/dev/$root_disk" != "$root_part" ]]; then
            if ! grep -q 'boot.loader.grub.device' "$HOST_DIR/configuration.nix"; then
                echo "==> Boot disk detected as /dev/$root_disk; adding to configuration.nix"
                sed -i '/enable = true;/a\    device = lib.mkDefault "/dev/'"$root_disk"'";' "$HOST_DIR/configuration.nix"
            fi
        else
            echo "==> Could not detect boot disk. Verify boot.loader.grub.device in $HOST_DIR/configuration.nix"
        fi
    else
        echo "==> Could not detect root mount. Verify boot.loader.grub.device in $HOST_DIR/configuration.nix"
    fi

    if [[ ! -f "$FLAKE_DIR/flake.lock" ]]; then
        echo "==> Locking flake inputs..."
        nix --extra-experimental-features "nix-command flakes" flake lock "$FLAKE_DIR"
    else
        echo "==> flake.lock already exists."
    fi

    echo "==> Committing bootstrap changes..."
    git -C "$REPO_DIR" config user.email >/dev/null 2>&1 || git -C "$REPO_DIR" config user.email "agent-box@localhost"
    git -C "$REPO_DIR" config user.name >/dev/null 2>&1 || git -C "$REPO_DIR" config user.name "Agent Box"
    if git -C "$REPO_DIR" status --short | grep -q .; then
        git -C "$REPO_DIR" add -A
        git -C "$REPO_DIR" commit -m "agent-box: bootstrap"
    fi

    echo "==> Applying initial NixOS configuration..."
    nixos-rebuild switch --flake "$FLAKE_DIR#agent-box"

    if [[ -z "${INVOCATION_ID:-}" ]]; then
        echo "==> Running interactive setup..."
        "$FLAKE_DIR/scripts/setup.sh"

        echo "==> Disabling root SSH..."
        disable_root_ssh
        git -C "$REPO_DIR" add -A
        git -C "$REPO_DIR" commit -m "agent-box: disable root SSH after setup"

        echo "==> Rebuilding with root SSH disabled..."
        nixos-rebuild switch --flake "$FLAKE_DIR#agent-box"

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

    echo "==> Cleaning up bootstrap trigger..."
    rm -f "$PHASE2_NIX"
    touch "$BOOTSTRAP_DONE"
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
