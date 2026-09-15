# Agent Box

NixOS flake for an agent box with workflows.

> **Warning:** The installer below uses `nixos-infect`, which **wipes the entire
> disk**. Only run it on a machine you are willing to erase (a fresh VPS or a
> throwaway VM). It is **not** for macOS, Windows, or your main machine.

## How it works

The agent box keeps a small, stable base system and puts all project-specific
tooling into **workflows**.

- **Base system**: OpenCode, git, gh, tmux, curl, htop, python3, openssl, plus
  SSH, Tailscale, and firewall.
- **Workflows**: per-project flakes under `/home/agent/workflow/`. Each workflow
  declares its own packages.

### Try → pin → commit loop

When you want to try a new tool:

```bash
new-workflow.sh assets template
enter-workflow.sh assets
nix-shell -p some-experimental-tool --run "some-experimental-tool --help"
```

If it works, pin it permanently:

```bash
vim /home/agent/workflow/assets/flake.nix   # add some-experimental-tool
enter-workflow.sh assets                     # reload with the pinned tool
```

If it does not work, throw it away:

```bash
exit
purge-workflow.sh assets
nix-collect-garbage -d
```

No leftover state in the base system.

### Cleanup

- Remove a workflow: `purge-workflow.sh <name>`
- Clean downloaded packages: `nix-collect-garbage -d`
- Reset everything: reinstall NixOS, run the installer again.

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

The installer will:
- Install the latest stable NixOS channel via `nixos-infect`.
- Reboot.
- Clone this repo to `/etc/nixos/dotfiles`.
- Generate a hardware configuration.
- Apply the agent box NixOS config.
- Prompt for Tailscale, GitHub, OpenCode, and agent password.
- Link `agent-box/AGENTS.md` into OpenCode’s system prompt.
- Disable root SSH and rebuild.

## Already on NixOS?

If you already have NixOS installed (e.g., in a VM, on a spare machine, or via
Asahi Linux on a Mac), the same installer skips `nixos-infect` and just runs
the bootstrap/setup phase:

```bash
curl -fsSL https://raw.githubusercontent.com/sausalito-labs/dotfiles/master/agent-box/scripts/install.sh | bash
```

It will generate a `hardware-configuration.nix` for that machine. If you are not
using the VPS host, you may want to create a new host directory under
`agent-box/hosts/` instead of reusing `hosts/agent-box/`.

## Testing safely

Do **not** test the full installer on hardware you care about. Good options:

- A cheap cloud VPS (e.g., netcup, Hetzner, Vultr).
- A local VM: QEMU, VirtualBox, UTM (macOS), or VMware.
- A dry-run to inspect what the installer would do:
  ```bash
  curl -fsSL https://raw.githubusercontent.com/sausalito-labs/dotfiles/master/agent-box/scripts/install.sh | bash -s -- --dry-run
  ```

## Installer options

- `--yes` or `AUTO_YES=1` — skip the confirmation prompt before `nixos-infect`.
  ```bash
  curl ... | bash -s -- --yes
  # or
  curl ... | AUTO_YES=1 bash
  ```
- `--dry-run` — print the plan and exit without making changes.
  ```bash
  curl ... | bash -s -- --dry-run
  ```
- `NIX_CHANNEL` — pin the NixOS channel used by `nixos-infect`.
  ```bash
  curl ... | NIX_CHANNEL=nixos-24.11 bash
  ```

## Workflows

Create, enter, and remove workflows:

```bash
new-workflow.sh my-webpage webpage
enter-workflow.sh my-webpage
purge-workflow.sh my-webpage
```

Edit `/home/agent/workflow/<name>/flake.nix` to add packages. Changes are stored
under `/etc/nixos/dotfiles/agent-box/workflow/`, so commit them with the repo
to back them up.

## Structure

- `modules/agent.nix` — vendor-agnostic NixOS module.
- `hosts/agent-box/` — machine-specific config for the current VPS.
- `scripts/install.sh` — one-shot installer.
- `scripts/setup.sh` — interactive first-boot setup (called by installer).
- `templates/workflow/` — workflow templates.
- `workflow/` — runtime workflows.
- `AGENTS.md` — instructions injected into OpenCode’s system prompt.

See `hosts/agent-box/README.md` for migration and adding new hosts.
