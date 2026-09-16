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
fetches this repo to `/opt/agent-box`, builds the base toolchain via this flake,
and installs OpenCode with its official installer (latest release, self-updating).
Your OS and root access stay exactly as the provider configured them.

`scripts/setup.sh` then collects secrets interactively (Tailscale auth key,
OpenCode API key + web password, agent password), joins the tailnet, writes the
OpenCode service secrets, completes a GitHub device-flow login, links `AGENTS.md`
into OpenCode's system prompt, and exposes the web UI over Tailscale Funnel as
a public HTTPS URL (no client installs needed).

The toolchain is on PATH everywhere without symlink tricks: login shells get it
from `/etc/profile.d/agent-box.sh`, and the `opencode.service` unit sets the
same PATH for non-login shells (systemd contexts and the agent's own shell).

The pre-made workflows are also templates:

- `template` — empty starter
- `game` — Godot 4, Python 3, unzip, curl
- `webpage` — Node.js, pnpm

## Bootstrap a fresh VPS

1. Log in as root (netcup password/key — works from any device):
   ```bash
   ssh root@<your-server-ip>
   ```
2. Run the installer. It installs everything, then starts the interactive
   setup (Tailscale, OpenCode, passwords) in the same session:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/sausalito-labs/dotfiles/master/agent-box/scripts/install.sh | bash
   ```
   If you recently updated the installer, pass `-H 'Cache-Control: no-cache'`
   to avoid fetching a stale CDN-cached copy.

That's it — no reboot, no disk wipe, no root-ssh choreography. The interactive
setup runs automatically when the install finishes. To rerun setup later (for
example, to rotate secrets):

```bash
bash /opt/agent-box/agent-box/scripts/setup.sh
```

## After setup

The setup summary prints both addresses; the Funnel one needs no Tailscale on
your device:

- OpenCode web UI from any browser, anywhere (public HTTPS via Tailscale Funnel):
  ```text
  https://<node>.<tailnet>.ts.net     user: opencode / your OpenCode web UI password
  ```
- OpenCode web UI inside the tailnet (magicDNS):
  ```text
  http://<node>:4096
  ```
- Log in via the tailnet: `ssh agent@<node>`

Project repos live in `/home/agent/projects` (agent-owned; the web service
starts there). In the web UI, pick the folder for the repo you're working in —
OpenCode is per-project, so each session loads the directory you choose.

GitHub CLI is already authenticated by setup (device flow). Re-run it if needed:
```bash
sudo -u agent gh auth login --hostname github.com --git-protocol https --web
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
curl ... | AUTO_YES=1 bash
```

## Structure

- `flake.nix` — `packages.toolchain` (pinned nixpkgs).
- `flake.lock` — locked nixpkgs rev for the toolchain (committed).
- `services/opencode.service` — OpenCode web UI systemd unit (agent user,
  sets the toolchain PATH for non-login shells).
- `scripts/install.sh` — one-command Debian/Nix installer.
- `scripts/setup.sh` — interactive first-time setup (Tailscale, OpenCode, passwords).
- `scripts/setup-secrets.sh` — applies secrets (Tailscale up, OpenCode auth).
- `scripts/{new,enter,purge}-workflow.sh` — workflow helpers (on PATH via the unit
  and profile.d).
- `workflows/` — per-project flakes with committed `flake.lock`, each pinned to the
  same nixpkgs rev as the toolchain (also serve as templates).
- `AGENTS.md` — instructions injected into OpenCode's system prompt.