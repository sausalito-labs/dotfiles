# Agent Box

NixOS flake for an agent box.

## Quick start

1. **SSH into the target machine as root.**
   ```bash
   ssh root@<your-server-ip>
   ```

2. **Run `nixos-infect` to convert the machine to NixOS.**
   This wipes the disk and installs NixOS:
   ```bash
   curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect \
     | NIX_CHANNEL=nixos-24.11 bash -x 2>&1 | tee /tmp/nixos-infect.log
   ```
   Wait for the reboot.

3. **SSH back into the fresh NixOS machine as root.**

4. **Replace `/etc/nixos` with this flake.**
   A fresh `nixos-infect` install has no `git` and `/etc/nixos` already
   contains default configs, so back it up and clone with a transient git:
   ```bash
   mv /etc/nixos /etc/nixos.bak
   nix-shell -p git --run "git clone https://github.com/sausalito-labs/dotfiles.git /etc/nixos"
   ```

5. **Generate the hardware configuration and track it:**
   ```bash
   nixos-generate-config --show-hardware-config \
     > /etc/nixos/agent-box/hosts/agent-box/hardware-configuration.nix
   git -C /etc/nixos add -A
   git -C /etc/nixos commit -m "agent-box initial config"
   ```

6. **Apply the configuration.** `nixos-rebuild` also needs git available:
   ```bash
   nix-shell -p git --run "nixos-rebuild switch --flake /etc/nixos/agent-box#agent-box"
   ```
   This first rebuild leaves root SSH enabled so you can run setup.

7. **Run the interactive setup script as root:**
   ```bash
   /etc/nixos/agent-box/scripts/setup.sh
   ```
   It will prompt for:
   - Tailscale/Headscale auth key
   - GitHub personal access token
   - OpenCode API key
   - OpenCode web UI password
   - Password for the `agent` user

   It can also copy the `game` environment template and install Godot export
   templates.

8. **In a new terminal, verify you can SSH as `agent`:**
   ```bash
   ssh agent@<your-server-ip>
   ```

9. **Disable root SSH and rebuild.** Edit
   `/etc/nixos/agent-box/hosts/agent-box/configuration.nix` and change:
   ```nix
   services.openssh.settings.PermitRootLogin = "no";
   ```
   Then:
   ```bash
   nix-shell -p git --run "nixos-rebuild switch --flake /etc/nixos/agent-box#agent-box"
   ```

## Structure

- `modules/agent.nix` — vendor-agnostic NixOS module.
- `hosts/agent-box/` — machine-specific config for the current VPS.
- `scripts/setup.sh` — interactive first-boot setup.
- `templates/envs/` — environment templates.
- `agent/envs/` — runtime agent environments.

See `hosts/agent-box/README.md` for migration, daily usage, and adding new hosts.

## Environments

Create a new environment from a template:

```bash
new-env.sh my-webpage webpage
```

Enter an environment:

```bash
enter-env.sh my-webpage
```

Remove an environment:

```bash
purge-env.sh my-webpage
```

Edit `/home/agent/envs/<name>/flake.nix` to add or remove packages. Changes are
stored under `/etc/nixos/agent-box/agent/envs/`, so commit them with the system
config to back them up.
