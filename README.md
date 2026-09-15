# dotfiles

Declarative system configuration. Currently contains the NixOS flake for
`agent-box`, a remote Linux server (VPS/VM) that runs OpenCode and Tailscale.

- `agent-box/` — NixOS config for an agent box (OpenCode, Tailscale/Headscale,
  SSH, agent workflows).
  - `modules/agent.nix` — reusable, vendor-agnostic NixOS module.
  - `hosts/agent-box/` — machine-specific config for the current VPS.
  - `scripts/install.sh` — one-shot installer for a fresh VPS.
  - `scripts/setup.sh` — interactive first-boot setup.
  - `workflows/` — workflows (also serve as templates).

See `agent-box/README.md` for bootstrap and `agent-box/hosts/agent-box/README.md`
for migration and daily-use details.
