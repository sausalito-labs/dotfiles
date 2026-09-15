# Agent Box

NixOS flake for an agent box with workflows.

> **Warning:** The installer below uses `nixos-infect`, which **wipes the entire
> disk**. Only run it on a machine you are willing to erase (a fresh VPS or a
> throwaway VM). It is **not** for macOS, Windows, or your main machine.

## What this is and what it isn't

**This is:**
- A NixOS flake for a remote Linux server (VPS or VM).
- A stable base system with OpenCode, SSH, Tailscale, and a firewall.
- A set of per-project development environments called **workflows**.
- A one-script installer for a fresh disk via `nixos-infect`.

**This is not:**
- A macOS, Windows, or WSL setup.
- A desktop environment or daily driver.
- A system where packages are installed globally by default.
- A Docker, Kubernetes, or container platform.
- A CI/CD runner, game engine, or game itself.
- A project that requires pushing VPS changes to GitHub.

## How it works

The agent box keeps a small, stable base system and puts all project-specific
tooling into **workflows**.

- **Base system**: OpenCode, git, gh, tmux, curl, unzip, htop, python3, openssl,
  plus SSH, Tailscale, and firewall.
- **Workflows**: per-project flakes under `/etc/nixos/dotfiles/agent-box/workflows/`.
  Each workflow declares its own packages.

The pre-made workflows are also templates:

- `template` — empty starter
- `game` — Godot 4, Python 3, unzip, curl
- `webpage` — Node.js, pnpm

### Try → pin → commit loop

When you want to try a new tool:

```bash
enter-workflow.sh game
nix-shell -p some-experimental-tool --run "some-experimental-tool --help"
```

If it works, pin it permanently:

```bash
vim /etc/nixos/dotfiles/agent-box/workflows/game/flake.nix
exit
enter-workflow.sh game
```

If it does not work, throw it away.

If you were testing inside an existing workflow, the temporary package is gone
as soon as you exit:

```bash
exit
nix-collect-garbage -d
```

If you created a brand-new workflow for the experiment, delete the workflow too:

```bash
exit
purge-workflow.sh assets
nix-collect-garbage -d
```

No leftover state in the base system.

### Creating a new workflow from a template

```bash
new-workflow.sh assets template
enter-workflow.sh assets
```

This copies `workflows/template/` to `workflows/assets/`.

### Cleanup

- Remove a workflow: `purge-workflow.sh <name>`
- Clean downloaded packages: `nix-collect-garbage -d`
- Reset everything: reinstall NixOS, run the installer again.

### Note on local commits

The installer creates a `hardware-configuration.nix` and commits it **locally**
so the NixOS flake can import it. Workflows created later can also be committed
locally, but that is only for backup — `nix develop` works on uncommitted
workflow files. You do **not** need to push anything to GitHub.

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
- Lock flake inputs into `flake.lock` for reproducible builds.
- Apply the agent box NixOS config.
- Prompt for Tailscale, OpenCode, and agent password.
- Link `agent-box/AGENTS.md` into OpenCode's system prompt.
- Disable root SSH and rebuild.

After setup, log in as `agent` and run `gh auth login` to authenticate GitHub
via the website.

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

Edit `/etc/nixos/dotfiles/agent-box/workflows/<name>/flake.nix` to add packages.
Changes are stored under `/etc/nixos/dotfiles/agent-box/workflows/`. Commit them
locally if you want them backed up; they do not need to be committed for
`nix develop` to work.

## Structure

- `modules/agent.nix` — vendor-agnostic NixOS module.
- `hosts/agent-box/` — machine-specific config for the current VPS.
- `scripts/install.sh` — one-shot installer.
- `scripts/setup.sh` — interactive first-boot setup (called by installer).
- `workflows/` — workflows (also serve as templates).
- `AGENTS.md` — instructions injected into OpenCode’s system prompt.

See `hosts/agent-box/README.md` for migration and adding new hosts.
