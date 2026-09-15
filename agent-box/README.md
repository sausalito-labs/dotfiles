# Agent Box

NixOS flake for an agent box with workspace environments.

## Bootstrap a fresh VPS

1. SSH as root.
2. Download and run the installer:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/sausalito-labs/dotfiles/master/agent-box/scripts/install.sh | bash
   ```
3. Wait for the reboot, then SSH as root again. Phase 2 finishes automatically.
4. When it prints `Setup complete`, log in as `agent`:
   ```bash
   ssh agent@<your-server-ip>
   ```

If already on NixOS, the same installer skips `nixos-infect` and just builds the
environment.

## Workspaces

Create, enter, and remove environments:

```bash
new-env.sh my-webpage webpage
enter-env.sh my-webpage
purge-env.sh my-webpage
```

Edit `/home/agent/envs/<name>/flake.nix` to add packages. Changes are stored
under `/etc/nixos/dotfiles/agent-box/agent/envs/`, so commit them with the repo
to back them up.

## Structure

- `modules/agent.nix` — vendor-agnostic NixOS module.
- `hosts/agent-box/` — machine-specific config.
- `scripts/install.sh` — one-shot installer.
- `scripts/setup.sh` — interactive first-boot setup (called by installer).
- `templates/envs/` — environment templates.
- `agent/envs/` — runtime environments.

See `hosts/agent-box/README.md` for migration and adding new hosts.
