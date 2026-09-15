# Agent Box

Declarative NixOS configuration for the VPS that runs OpenCode and the One
Arcade web demo.

## Architecture

This flake is split into **generic** and **machine-specific** parts:

- `modules/agent.nix` — vendor-agnostic module with the agent user, OpenCode
  service, Tailscale, firewall, and the One Arcade demo service.
- `hosts/agent-box/configuration.nix` — only machine-specific bits: hostname,
  disk device, and the SSH key used for initial access.
- `hosts/agent-box/hardware-configuration.nix` — generated on the target machine
  by `nixos-generate-config`.

To move to a different VPS, create a new directory under `hosts/`, import
`modules/agent.nix`, set a hostname, and generate a fresh
`hardware-configuration.nix`.

## What this gives you

- Declarative, reproducible NixOS system configuration.
- `modules/agent.nix` defines the shared agent environment.
- `hosts/agent-box/configuration.nix` adds only hostname, disk, and SSH key.
- `nixos-rebuild switch` applies the entire system state.
- systemd services run OpenCode and the One Arcade demo server.
- Only SSH (port 22) is public; OpenCode and the demo are tailnet-only.

## One-time bootstrap (after NixOS install)

1. **Install NixOS** on the VPS.
   - **Recommended:** use `nixos-infect` on the running Debian host.
     This wipes the entire disk and converts it to NixOS
     without uploading an ISO:
      ```bash
      curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect \
        | NIX_CHANNEL=nixos-24.11 bash -x 2>&1 | tee /tmp/nixos-infect.log
      ```
     Wait for the reboot, then SSH back in as `root`.
   - **Alternative:** boot the NixOS minimal ISO, then:
      ```bash
      sudo nixos-generate-config --root /mnt
      # copy this flake to /mnt/etc/nixos
      sudo nixos-install --flake /mnt/etc/nixos/gamedev#agent-box
      reboot
      ```

2. **Add your SSH key** to `hosts/agent-box/configuration.nix` if you want
   key-based auth:
   ```nix
   users.users.agent.openssh.authorizedKeys.keys = [
     "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your@email"
   ];
   ```

3. **Apply the config** from the live system:
   ```bash
   sudo nixos-rebuild switch --flake /etc/nixos/gamedev#agent-box
   ```

4. **Run the interactive setup script as root:**
   ```bash
   sudo /etc/nixos/gamedev/scripts/setup.sh
   ```
   It will prompt for:
   - Tailscale/Headscale auth key
   - GitHub personal access token
   - OpenCode API key
   - OpenCode web UI password
   - Password for the `agent` user

   Then it optionally copies the `game` environment template and installs Godot
   export templates.

5. **Verify agent SSH login**, then disable root SSH in
   `hosts/agent-box/configuration.nix` and rebuild.

## Daily usage

- Rebuild the system after editing the config:
  ```bash
  sudo nixos-rebuild switch --flake /etc/nixos/gamedev#agent-box
  ```

- Access OpenCode web UI from any device on the tailnet:
  ```
  http://agent-box:4096
  # or
  http://<tailscale-ip>:4096
  ```

- Access the One Arcade demo from the tailnet:
  ```
  https://agent-box:8765/
  ```

- Attach to the persistent tmux session:
  ```bash
  tmux attach -t agent
  ```

- Enter a development environment:
  ```bash
  enter-env.sh game
  ```

## Migrating to a new VPS

1. Copy `/etc/nixos` (this flake) to the new machine.
2. Create a new host directory, e.g. `hosts/new-vps/`:
   ```bash
   mkdir -p /etc/nixos/gamedev/hosts/new-vps
   ```
3. Copy `hosts/agent-box/configuration.nix` as a template and adjust hostname,
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

Create new environments under `/home/agent/envs/` using `new-env.sh`. Each
environment is a flake that can declare its own packages. Commit the env files
in `/etc/nixos/gamedev/agent/envs/` with the rest of the system config.
