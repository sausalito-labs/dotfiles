# Agent Box Instructions

You are running on the **agent box**, a NixOS system designed for experimenting
with tools and workflows without polluting the base system.

## Base system tools

The following are always available without entering a workflow:

- `git`, `gh` — version control and GitHub CLI
- `tmux` — persistent terminal sessions
- `curl`, `unzip` — network and archive tools
- `htop` — process viewer
- `python3`, `openssl` — scripting and crypto utilities
- `opencode` — this agent

## Workflows

A **workflow** is a per-project Nix flake that lives under
`/etc/nixos/dotfiles/agent-box/workflows/<name>/`. Workflows declare their own
packages so you can install arbitrary tools without touching the base system.

### Pre-made workflows

These also serve as templates:

- `template` — empty starter
- `game` — Godot 4, Python 3, unzip, curl
- `webpage` — Node.js, pnpm

### Workflow commands

```bash
new-workflow.sh <name> [template]   # create a workflow from a template
enter-workflow.sh <name>            # enter a workflow's nix develop shell
purge-workflow.sh <name>            # delete a workflow
```

You can also create a workflow manually by copying a template:

```bash
cp -r /etc/nixos/dotfiles/agent-box/workflows/template \
      /etc/nixos/dotfiles/agent-box/workflows/my-workflow
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

5. Commit the workflow locally so Nix can see it:
   ```bash
   git -C /etc/nixos/dotfiles add agent-box/workflows/<name>
   git -C /etc/nixos/dotfiles commit -m "add <tool> to <name> workflow"
   ```

   You do not need to push this commit to GitHub.

### Updating a template

If you find a workflow setup that should become the default for future projects,
edit the corresponding template directly:

```bash
vim /etc/nixos/dotfiles/agent-box/workflows/game/flake.nix
```

Then commit locally.

### Cleanup

To remove a failed experiment:

```bash
exit
purge-workflow.sh <name>
nix-collect-garbage -d
```

## Important paths

- `/etc/nixos/dotfiles/` — this repo (system config + workflows)
- `/etc/nixos/dotfiles/agent-box/workflows/` — workflows and templates
- `/home/agent/.config/opencode/AGENTS.md` — this file

## Rules

- Do **not** install global packages with `nix-env` or edit the base NixOS config
  unless the user explicitly asks. Prefer creating or editing a workflow.
- Rebuild the system only when asked:
  ```bash
  sudo nixos-rebuild switch --flake /etc/nixos/dotfiles/agent-box#agent-box
  ```
- Tailscale is running; SSH (port 22) is the only public port.
- OpenCode web UI runs on port 4096 inside the tailnet.
