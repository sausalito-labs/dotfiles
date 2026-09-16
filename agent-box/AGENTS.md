# Agent Box Instructions

You are running on the **agent box**, a Debian host with multi-user Nix layered
on top. The operating system (sshd, root access, host provisioning) is managed
by the provider (netcup); this repo manages only the per-user Nix environment,
the OpenCode web service, and per-project workflows.

## Base system tools

Installed into the `agent` user's Nix profile, so they are always on PATH:

- `git`, `gh` — version control and GitHub CLI
- `tmux` — persistent terminal sessions
- `curl`, `unzip` — network and archive tools
- `htop` — process viewer
- `python3`, `openssl` — scripting and crypto utilities

`opencode` itself is **not** in the Nix profile. It is installed with the
official installer at `/home/agent/.opencode/bin` (always the latest release,
self-updating via `opencode upgrade`). To update it:

```bash
sudo -u agent opencode upgrade
```

Add more tools with `nix profile install nixpkgs#<pkg>`, or by adding them to the
`toolchain` package in `./flake.nix` and reinstalling the profile.

The toolchain and Nix are on PATH everywhere, login shell or not:
- login shells get it from `/etc/profile.d/agent-box.sh`;
- the `opencode.service` unit sets the same PATH for non-login shells —
  systemd contexts and the agent's own shell (`bash -c` never reads
  `/etc/profile`).

`git`, `gh`, `nix`, `enter-workflow.sh` etc. therefore resolve from any
session the box provides. After a toolchain upgrade, restart `opencode`
(`systemctl restart opencode`) so the unit's PATH reflects the new profile.

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

OpenCode is managed separately by its own installer and tracks the latest
release:
  ```bash
  sudo -u agent opencode upgrade
  ```

After upgrading either, restart the web service:
  ```bash
  systemctl restart opencode
  ```

## Important paths

- `/opt/agent-box/` — this repo (clone of the dotfiles repo)
- `/opt/agent-box/agent-box/` — the agent box config, packages, scripts
- `/opt/agent-box/agent-box/workflows/` — workflows and templates
- `/home/agent/projects/` — default workspace for project repos (the web
  UI starts here; pick the folder for the repo you're working in)
- `/home/agent/.config/opencode/AGENTS.md` — this file
- `/var/lib/opencode/opencode.env` — OpenCode web UI secrets
- `/var/lib/agent-setup/secrets.env` — Tailscale/OpenCode API secrets

## Services

- `opencode.service` — OpenCode web UI on port 4096, exposed two ways:
  - tailnet (magicDNS): `http://<node>:4096`
  - public HTTPS via Tailscale Funnel: `https://<node>.<tailnet>.ts.net`
    (basic auth: user `opencode`, password from the setup run)
  Restart with: `systemctl restart opencode`
- `tailscaled.service` — tailnet mesh (Funnel traffic arrives through it).

Manage the public Funnel exposure with:
```bash
tailscale funnel --bg 4096   # enable/persist the public HTTPS URL
tailscale funnel off         # remove it
tailscale funnel status      # show the current URL
```

## Rules

- Do **not** install global packages with `nix-env` or edit system files unless
  the user explicitly asks. Prefer creating or editing a workflow.
- Root SSH and OS access are managed by netcup; do not reconfigure sshd or root
  access unless asked.
- SSH (port 22) is the only public port; everything else is firewalled.
- OpenCode web UI runs on port 4096, reachable via the tailnet and exposed
  publicly through Tailscale Funnel as an HTTPS URL.