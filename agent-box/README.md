# Agent Box

OpenCode + per-project workflows on plain Nix, layered over Debian/Ubuntu.

## What this is and what it isn't

**This is:**
- A Debian/Ubuntu host with multi-user Nix and an `agent` user.
- OpenCode (web UI on port 4096 inside the tailnet), SSH, Tailscale, ufw.
- A set of per-project development environments called **workflows**.
- A one-command installer for a fresh VPS that does **not** touch the OS.

**This is not:**
- NixOS. The operating system (sshd, root access, provisioning) is managed by
  the provider, not by this repo.
- A macOS, Windows, or WSL setup.
- A desktop environment or daily driver.
- A Docker, Kubernetes, or container platform.
- A system where packages are installed globally by default.

## How it works

`scripts/install.sh` installs multi-user Nix (with Determinate Nix Installer),
creates the `agent` user, installs Tailscale + a firewall (SSH + tailnet only),
clones this repo to `/opt/agent-box`, and builds the agent profile
(`opencode` + the base toolchain) via this flake. Your OS and root access stay
exactly as the provider configured them.

`scripts/setup.sh` then collects secrets interactively (Tailscale auth key,
OpenCode API key + web password, agent password), joins the tailnet, writes the
OpenCode service secrets, and links `AGENTS.md` into OpenCode's system prompt.

The pre-made workflows are also templates:

- `template` — empty starter
- `game` — Godot 4, Python 3, unzip, curl
- `webpage` — Node.js, pnpm

## Bootstrap a fresh VPS

1. Log in as root (netcup password/key — works from any device):
   ```bash
   ssh root@<your-server-ip>
   ```
2. Run the installer:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/sausalito-labs/dotfiles/master/agent-box/scripts/install.sh | bash
   ```
   If you recently updated the installer, pass `-H 'Cache-Control: no-cache'`
   to avoid fetching a stale CDN-cached copy.
3. Run the interactive setup:
   ```bash
   bash /opt/agent-box/agent-box/scripts/setup.sh
   ```

That's it — no reboot, no disk wipe, no root-ssh choreography.

## After setup

- Log in as the agent user from the tailnet:
  ```bash
  ssh agent@agent-box
  ```
- OpenCode web UI:
  ```bash
  http://agent-box:4096
  ```
- Authenticate GitHub with the website flow:
  ```bash
  gh auth login
  ```

## Try → pin → commit

```bash
enter-workflow.sh game
nix-shell -p some-experimental-tool --run "some-experimental-tool --help"
```

If it works, pin it in the workflow's `flake.nix`, then:

```bash
exit
enter-workflow.sh game
```

Failed experiment? Throw it away:

```bash
exit
nix-collect-garbage -d
```

## Creating a new workflow from a template

```bash
new-workflow.sh assets template
enter-workflow.sh assets
```

This copies `workflows/template/` to `workflows/assets/`.

## Cleanup

- Remove a workflow: `purge-workflow.sh <name>`
- Clean downloaded packages: `nix-collect-garbage -d`
- Reset the box: reinstall Debian in the provider panel, run the installer again.

## Installer options

```bash
curl ... | bash -s -- --yes         # skip the confirmation prompt
curl ... | bash -s -- --dry-run     # print the plan, change nothing
curl ... | bash -s -- --reset       # reset /opt/agent-box to origin/master first
curl ... | AUTO_YES=1 bash
```

## Structure

- `flake.nix` — `packages.opencode` + `packages.toolchain` (pinned nixpkgs).
- `packages/opencode/` — OpenCode derivation (prebuilt x64 binary).
- `services/opencode.service` — OpenCode web UI systemd unit (agent user).
- `scripts/install.sh` — one-command Debian/Nix installer.
- `scripts/setup.sh` — interactive first-time setup (Tailscale, OpenCode, passwords).
- `scripts/setup-secrets.sh` — applies secrets (Tailscale up, OpenCode auth).
- `scripts/{new,enter,purge}-workflow.sh` — workflow helpers.
- `workflows/` — per-project flakes (also serve as templates).
- `AGENTS.md` — instructions injected into OpenCode's system prompt.