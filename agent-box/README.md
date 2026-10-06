# Agent Box

Claude Code + per-project workflows on plain Nix, layered over Debian/Ubuntu.

## What this is and what it isn't

**This is:**
- A Debian/Ubuntu host with multi-user Nix and an `agent` user.
- Claude Code (driven remotely from claude.ai/code or the Claude app via
  [Remote Control](https://code.claude.com/docs/en/remote-control)), Tailscale,
  SSH, ufw.
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
and installs Claude Code with its official installer (latest release,
self-updating). Your OS and root access stay exactly as the provider configured
them.

`scripts/setup.sh` then collects secrets interactively (Tailscale auth key,
agent password), joins the tailnet, completes a GitHub device-flow login, signs
Claude Code in with a claude.ai subscription, accepts Remote Control's one-time
confirmation, links `AGENTS.md` into Claude Code's memory as
`~/.claude/CLAUDE.md`, and starts the Remote Control service.

Remote Control runs Claude Code **on the box** and is driven from
claude.ai/code or the Claude app — it opens no inbound ports and is not exposed
through Tailscale Funnel. Tailscale is used only for SSH/MagicDNS admin access.
The session transcript is stored on Anthropic's servers.

The toolchain is on PATH everywhere without symlink tricks: login shells get it
from `/etc/profile.d/agent-box.sh`, and the
`claude-remote-control.service` unit sets the same PATH for non-login shells
(systemd contexts and the agent's own shell).

The pre-made workflows are also templates:

- `template` — empty starter
- `game` — Godot 4, Python 3, unzip, curl
- `webpage` — Node.js, pnpm

## Requirements

- A **claude.ai Pro, Max, Team, or Enterprise subscription** for the `agent`
  user. Remote Control does not work with API keys or `claude setup-token`.
- A Tailscale account (to join the tailnet).
- A GitHub account (for `gh`, optional but used by setup).

## Bootstrap a fresh VPS

1. Log in as root (netcup password/key — works from any device):
   ```bash
   ssh root@<your-server-ip>
   ```
2. Run the installer. It installs everything, then starts the interactive
   setup (Tailscale, GitHub, Claude Code login) in the same session:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/sausalito-labs/dotfiles/master/agent-box/scripts/install.sh | bash
   ```
   If you recently updated the installer, pass `-H 'Cache-Control: no-cache'`
   to avoid fetching a stale CDN-cached copy.

That's it — no reboot, no disk wipe, no root-ssh choreography. The interactive
setup runs automatically when the install finishes. To rerun setup later (for
example, to rotate secrets or re-login):

```bash
bash /opt/agent-box/agent-box/scripts/setup.sh
```

## After setup

Claude Code is reachable from any device — no client installs needed:

- Open **https://claude.ai/code** (or the **Claude app**, Code tab) and open the
  session named `agent-box`.
- Admin over the tailnet: `ssh agent@<node>`.
- The service runs on the box and keeps running; restart it with
  `sudo systemctl restart claude-remote-control`.

Project repos live in `/home/agent/projects` (agent-owned; the Remote Control
service starts sessions there). Clone the repo you want to work on into that
directory.

GitHub CLI is already authenticated by setup (device flow). Re-run it if needed:
```bash
sudo -u agent gh auth login --hostname github.com --git-protocol https --web
```

### Keeping the login alive

Remote Control uses your claude.ai subscription login, stored in
`~/.claude/.credentials.json`. If it expires, sessions stop making progress
until you sign in again. To renew, SSH in as the agent user, run `claude`, and
use `/login`:

```bash
ssh agent@<node>
claude
# then type: /login
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
- `services/claude-remote-control.service` — Claude Code Remote Control systemd
  unit (agent user, sets the toolchain PATH for non-login shells).
- `scripts/install.sh` — one-command Debian/Nix installer.
- `scripts/setup.sh` — interactive first-time setup (Tailscale, GitHub, Claude
  Code login).
- `scripts/setup-secrets.sh` — applies secrets (Tailscale up, GitHub).
- `scripts/{new,enter,purge}-workflow.sh` — workflow helpers (on PATH via the unit
  and profile.d).
- `workflows/` — per-project flakes with committed `flake.lock`, each pinned to the
  same nixpkgs rev as the toolchain (also serve as templates).
- `AGENTS.md` — instructions linked into Claude Code's memory as ~/.claude/CLAUDE.md.
