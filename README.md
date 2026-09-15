# dotfiles

Declarative system configuration, organized by environment.

- `agent-box/` — NixOS config for an agent box (OpenCode, Tailscale/Headscale,
  SSH, agent workspaces).
  - `modules/agent.nix` — reusable, vendor-agnostic NixOS module.
  - `hosts/agent-box/` — machine-specific config for the current VPS.
  - `scripts/setup.sh` — interactive first-boot setup.
  - `templates/envs/` — workspace environment templates.

See `agent-box/hosts/agent-box/README.md` for the full bootstrap, migration,
and daily-use guide.
