# Agent Box Instructions

You are running on the **agent box**, a Debian host with multi-user Nix layered
on top. The operating system (sshd, root access, host provisioning) is managed
by the provider (netcup); this repo manages only the per-user Nix environment,
the Claude Code Remote Control service, and per-project workflows.

## Base system tools

Installed into the `agent` user's Nix profile, so they are always on PATH:

- `git`, `gh` — version control and GitHub CLI
- `tmux` — persistent terminal sessions
- `curl`, `unzip` — network and archive tools
- `htop` — process viewer
- `python3`, `openssl` — scripting and crypto utilities

`claude` itself is **not** in the Nix profile. It is installed with the official
installer at `/home/agent/.local/bin` (always the latest release, self-updating
in the background). To update it:

```bash
sudo -u agent claude update
```

Add more tools with `nix profile install nixpkgs#<pkg>`, or by adding them to the
`toolchain` package in `./flake.nix` and reinstalling the profile.

The toolchain and Nix are on PATH everywhere, login shell or not:
- login shells get it from `/etc/profile.d/agent-box.sh`;
- the `claude-remote-control.service` unit sets the same PATH for non-login
  shells —
  systemd contexts and the agent's own shell (`bash -c` never reads
  `/etc/profile`).

`git`, `gh`, `nix`, `enter-workflow.sh` etc. therefore resolve from any
session the box provides. After a toolchain upgrade, restart the service
(`systemctl restart claude-remote-control`) so the unit's PATH reflects the new
profile.

## When asked to install a tool

1. If a relevant workflow already exists, edit that workflow's `flake.nix`.
2. Otherwise, create a new workflow with `new-workflow.sh <name> [template]`.
3. Never install a tool globally with `nix-env` or edit system files unless the
   user explicitly asks.

## Workflows

A **workflow** is a per-project Nix flake that lives under
`/opt/agent-box/agent-box/workflows/<name>/`. Workflows declare their own
packages so you can install arbitrary tools without touching the base system.

### Pre-made workflows

These also serve as templates:

- `template` — empty starter
- `game` — Godot 4, Python 3, unzip, curl
- `webpage` — Node.js, pnpm

Every workflow keeps a committed `flake.lock` pinned to the same nixpkgs
revision as the toolchain, so a box rebuilt from this repo reproduces the same
tool versions. If you add or change an `inputs` entry in a workflow, re-lock it
before committing (`nix flake lock` in the workflow's directory). New workflows
copied by `new-workflow.sh` inherit the template's lock automatically.

### Godot export templates

Exporting a game build needs the export templates for the pinned Godot version.
They are ~300 MB and only used at export time, so install them on demand (as
the agent user, whose PATH includes the toolchain):

    mkdir -p ~/.local/share/godot/export_templates
    cd ~/.local/share/godot/export_templates
    curl -fLo Godot_v4.3-stable_export_templates.tpz \
        https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_export_templates.tpz
    test -s Godot_v4.3-stable_export_templates.tpz
    unzip -o Godot_v4.3-stable_export_templates.tpz
    mv -f 4.3 4.3.stable

### Workflow commands

```bash
new-workflow.sh <name> [template]   # create a workflow from a template
enter-workflow.sh <name>            # enter a workflow's nix develop shell
purge-workflow.sh <name>            # delete a workflow
```

### Try → pin → commit

When you need a new tool:

1. Enter the workflow:
   ```bash
   enter-workflow.sh <name>
   ```

2. Test it temporarily:
   ```bash
   nix-shell -p <tool> --run "<tool> --version"
   ```

3. If it works, pin it permanently by editing the workflow's `flake.nix` and
   adding the package to `devShells.default.packages`.

4. Reload the workflow:
   ```bash
   exit
   enter-workflow.sh <name>
   ```

5. Commit the workflow to the dotfiles repo on GitHub to keep it backed up.
   The local copy is replaced on every reinstall, so anything not committed
   upstream disappears. Nix does not require a commit for `nix develop` to
   work.

### Cleanup

To remove a failed experiment:

```bash
exit
purge-workflow.sh <name>
nix-collect-garbage -d
```

## Committing changes

When you make changes to workflows, commit them to the dotfiles repo on GitHub
to keep them backed up; the local tree has no git metadata and gets replaced
on reinstall.

## Updating the agent environment

Tool upgrades come from the pinned `nixpkgs` input in `./flake.nix`:
- Change `flake.nix` (or bump the nixpkgs input), then:
  ```bash
  sudo -u agent nix profile upgrade toolchain
  ```

Claude Code is managed separately by its own installer and tracks the latest
release:
  ```bash
  sudo -u agent claude update
  ```

After upgrading either, restart the service:
  ```bash
  systemctl restart claude-remote-control
  ```

## Important paths

- `/opt/agent-box/` — this repo (clone of the dotfiles repo)
- `/opt/agent-box/agent-box/` — the agent box config, packages, scripts
- `/opt/agent-box/agent-box/workflows/` — workflows and templates
- `/home/agent/projects/` — default workspace for project repos (the Remote
  Control service starts sessions in this directory)
- `/home/agent/.claude/CLAUDE.md` — this file (symlink to the repo's AGENTS.md)
- `/var/lib/agent-setup/secrets.env` — Tailscale secrets

## Services

- `claude-remote-control.service` — Claude Code Remote Control. Runs Claude Code
  on the box, driven from claude.ai/code or the Claude app; opens no inbound
  ports. Restart with: `systemctl restart claude-remote-control`
- `tailscaled.service` — tailnet mesh (used for SSH/MagicDNS admin access).

## Exposing local services (Tailscale Serve/Funnel)

The `agent` user is the Tailscale operator, so it can run `tailscale serve` and
`tailscale funnel` without `sudo`:

```bash
tailscale serve --bg 3000      # reachable inside the tailnet only
tailscale funnel --bg 3000     # reachable on the public internet
tailscale serve status
tailscale funnel status
tailscale serve reset          # clear serve/funnel config
```

Funnel notes:

- Funnel must be enabled for the tailnet in the admin console (DNS -> HTTPS
  certificates, then Funnel). The first use prints a one-time approval link.
- Funnel only allows ports 443, 8443, and 10000; use `tailscale serve` for
  anything else (tailnet-only).
- Anything funnelled is on the public internet. Don't funnel services that
  should stay private.
- The operator setting is re-applied by setup because `tailscale up` resets
  unspecified flags. As operator you can also serve/funnel, but not restart
  `tailscaled` or change other root-only settings.

## Rules

- Do **not** install global packages with `nix-env` or edit system files unless
  the user explicitly asks. Prefer creating or editing a workflow.
- Root SSH and OS access are managed by netcup; do not reconfigure sshd or root
  access unless asked.
- SSH (port 22) is the only public port; everything else is firewalled.
- Claude Code Remote Control opens no inbound ports; it makes outbound HTTPS to
  api.anthropic.com and is reached through claude.ai/code or the Claude app.
- Remote Control requires a claude.ai subscription login (not an API key) and
  stores the session transcript on Anthropic's servers.