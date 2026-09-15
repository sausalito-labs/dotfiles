# Agent Box

Declarative NixOS configuration for the VPS that runs OpenCode.

For the normal bootstrap, use `../scripts/install.sh`. This README covers
architecture, migration, and adding new hosts.

## Architecture

This flake is split into **generic** and **machine-specific** parts:

- `modules/agent.nix` — vendor-agnostic module with the agent user, OpenCode
  service, Tailscale, and firewall.
- `hosts/agent-box/configuration.nix` — only machine-specific bits: hostname,
  disk device, and the SSH key used for initial access.
- `hosts/agent-box/hardware-configuration.nix` — generated on the target machine
  by `nixos-generate-config`.

To move to a different VPS, create a new directory under `hosts/`, import
`modules/agent.nix`, set a hostname, and generate a fresh
`hardware-configuration.nix`.

## What this gives you

- Declarative, reproducible NixOS system configuration.
- `modules/agent.nix` defines the shared agent workflow base.
- `hosts/agent-box/configuration.nix` adds only hostname, disk, and SSH key.
- `nixos-rebuild switch` applies the entire system state.
- systemd services run OpenCode.
- Only SSH (port 22) is public; OpenCode is tailnet-only.

## Daily usage

- Rebuild the system after editing the config:
  ```bash
  sudo nixos-rebuild switch --flake /etc/nixos/dotfiles/agent-box#agent-box
  ```

- Access OpenCode web UI from any device on the tailnet:
  ```
  http://agent-box:4096
  # or
  http://<tailscale-ip>:4096
  ```

- Attach to the persistent tmux session:
  ```bash
  tmux attach -t agent
  ```

- Enter a workflow:
  ```bash
  enter-workflow.sh game
  ```
  Workflows live in `/etc/nixos/dotfiles/agent-box/workflows/`.

## Migrating to a new VPS

1. Copy `/etc/nixos/dotfiles` (this repo) to the new machine.
2. Create a new host directory, e.g. `hosts/new-vps/`:
   ```bash
   mkdir -p /etc/nixos/dotfiles/agent-box/hosts/new-vps
   ```
3. Copy `hosts/agent-box/configuration.nix` as a template and adjust hostname,
   disk device, and SSH key.
4. Generate hardware config:
   ```bash
   sudo nixos-generate-config --show-hardware-config > /etc/nixos/dotfiles/agent-box/hosts/new-vps/hardware-configuration.nix
   ```
5. Add the new host to `flake.nix`:
   ```nix
   nixosConfigurations.new-vps = nixpkgs.lib.nixosSystem {
     system = "x86_64-linux";
     modules = [ ./hosts/new-vps/configuration.nix ];
   };
   ```
6. Run `sudo nixos-install --flake /etc/nixos/dotfiles/agent-box#new-vps` and reboot.
7. Re-run `/etc/nixos/dotfiles/agent-box/scripts/setup.sh` on the new machine.

## Workflows

Create new workflows under `/etc/nixos/dotfiles/agent-box/workflows/` using
`new-workflow.sh`. Each workflow is a flake that can declare its own packages.
Workflow files live in the flake directory and are committed locally so Nix can
see them; you do not need to push them to origin.
