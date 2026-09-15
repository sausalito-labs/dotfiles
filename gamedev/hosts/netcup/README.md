# Netcup Gamedev Box

Declarative NixOS configuration for the netcup VPS that runs OpenCode, Godot, and the One Arcade web demo.

## Architecture

This flake is split into **generic** and **machine-specific** parts:

- `modules/gamedev-box.nix` — vendor-agnostic module with the gamedev user,
  OpenCode service, Godot, Tailscale, firewall, and the One Arcade demo service.
- `hosts/netcup/configuration.nix` — only netcup-specific bits: hostname,
  disk device, and the SSH key used for initial access.
- `hosts/netcup/hardware-configuration.nix` — generated on the target machine
  by `nixos-generate-config`.

To move to a different VPS, create a new directory under `hosts/`, import
`modules/gamedev-box.nix`, set a hostname, and generate a fresh
`hardware-configuration.nix`.

## What this gives you

- Declarative, reproducible NixOS system configuration.
- `modules/gamedev-box.nix` defines the shared gamedev environment.
- `hosts/netcup/configuration.nix` adds only hostname, disk, and SSH key.
- `nixos-rebuild switch` applies the entire system state.
- systemd services run OpenCode and the One Arcade demo server.
- Only SSH (port 22) is public; OpenCode and the demo are tailnet-only.

## One-time bootstrap (after NixOS install)

1. **Install NixOS** on the netcup VPS.
   - **Recommended for netcup:** use `nixos-infect` on the running Debian host.
     This wipes the entire disk and converts it to NixOS
     without uploading an ISO:
      ```bash
      curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect \
        | NIX_CHANNEL=nixos-unstable bash -x 2>&1 | tee /tmp/nixos-infect.log
      ```
     Wait for the reboot, then SSH back in as `root`.
   - **Alternative:** boot the NixOS minimal ISO via SCP's *Media → DVD Drive*,
     then:
     ```bash
     sudo nixos-generate-config --root /mnt
     # copy this flake to /mnt/etc/nixos
     sudo nixos-install --flake /mnt/etc/nixos/gamedev#netcup
     reboot
     ```

2. **Add your SSH key** to `hosts/netcup/configuration.nix`:
   ```nix
   users.users.gamedev.openssh.authorizedKeys.keys = [
     "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your@email"
   ];
   ```

3. **Apply the config** from the live system:
   ```bash
   sudo nixos-rebuild switch --flake /etc/nixos/gamedev#netcup
   ```

4. **Run the interactive setup script**:
   ```bash
   sudo /etc/nixos/gamedev/scripts/setup.sh
   ```
   It will prompt for:
   - Tailscale/Headscale auth key
   - GitHub personal access token
   - OpenCode API key
   - OpenCode web UI password

   Then it optionally installs Godot export templates.

## Daily usage

- Rebuild the system after editing the config:
  ```bash
  sudo nixos-rebuild switch --flake /etc/nixos/gamedev#netcup
  ```

- Access OpenCode web UI from any device on the tailnet:
  ```
  http://netcup-gamedev:4096
  # or
  http://<tailscale-ip>:4096
  ```

- Access the One Arcade demo from the tailnet:
  ```
  https://netcup-gamedev:8765/
  ```

- Attach to the persistent tmux session:
  ```bash
  tmux attach -t gamedev
  ```

## Migrating to a new VPS

1. Copy `/etc/nixos` (this flake) to the new machine.
2. Create a new host directory, e.g. `hosts/new-vps/`:
   ```bash
   mkdir -p /etc/nixos/gamedev/hosts/new-vps
   ```
3. Copy `hosts/netcup/configuration.nix` as a template and adjust hostname,
   disk device, and SSH key.
4. Generate hardware config:
   ```bash
   sudo nixos-generate-config --show-hardware-config > /etc/nixos/gamedev/hosts/new-vps/hardware-configuration.nix
   ```
5. Add the new host to `flake.nix`:
   ```nix
   nixosConfigurations.new-vps = nixpkgs.lib.nixosSystem {
     system = "x86_64-linux";
     modules = [ ./hosts/new-vps/configuration.nix ];
   };
   ```
6. Run `sudo nixos-install --flake /etc/nixos/gamedev#new-vps` and reboot.
7. Re-run `/etc/nixos/gamedev/scripts/setup.sh` on the new machine.

## Asset generation pipeline

For the future Python/ML asset pipeline, create a separate container or
`nix-shell` environment in another directory. Don't pollute this host config
with experimental tooling.
