# gamedev

NixOS flake for a headless gamedev box.

## Quick start

1. **SSH into the target machine as root.**
   ```bash
   ssh root@<your-server-ip>
   ```

2. **Run `nixos-infect` to convert the machine to NixOS.**
   This wipes the disk and installs NixOS:
   ```bash
   curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect \
     | NIX_CHANNEL=nixos-unstable bash -x 2>&1 | tee /tmp/nixos-infect.log
   ```
   Wait for the reboot.

3. **SSH back into the fresh NixOS machine as root.**

4. **Clone this flake to `/etc/nixos`:**
   ```bash
   git clone https://github.com/sausalito-labs/dotfiles.git /etc/nixos
   ```

5. **Generate the hardware configuration:**
   ```bash
   nixos-generate-config --show-hardware-config \
     > /etc/nixos/gamedev/hosts/netcup/hardware-configuration.nix
   ```

6. **Add your SSH key** to `/etc/nixos/gamedev/hosts/netcup/configuration.nix`.

7. **Apply the configuration:**
   ```bash
   nixos-rebuild switch --flake /etc/nixos/gamedev#netcup
   ```

8. **Run the interactive setup script:**
   ```bash
   /etc/nixos/gamedev/scripts/setup.sh
   ```
   It will prompt for Tailscale/Headscale auth key, GitHub token, OpenCode API
   key, and OpenCode web UI password. It can also install Godot export
   templates.

9. **Clone your game repo** (e.g., `one-arcade`) into `/home/gamedev/`, build
   the demo, and the `one-arcade-demo` systemd service will serve it.

## Structure

- `modules/gamedev-box.nix` — vendor-agnostic NixOS module.
- `hosts/netcup/` — machine-specific config for the current netcup VPS.
- `scripts/setup.sh` — interactive first-boot setup.

See `hosts/netcup/README.md` for migration, daily usage, and adding new hosts.
