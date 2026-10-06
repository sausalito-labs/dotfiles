# dotfiles

Declarative tooling layered over plain Nix. Currently contains `agent-box`, a
remote Linux server (VPS/VM) that runs Claude Code and Tailscale over Debian/Nix.

- `agent-box/` — agent box configuration (Claude Code, Tailscale, SSH, workflows).
  - `flake.nix` — agent toolchain buildEnv, pinned nixpkgs (Claude Code installs
    via its official installer and tracks the latest release).
  - `services/claude-remote-control.service` — Claude Code Remote Control systemd
    unit (agent user).
  - `scripts/install.sh` — one-command installer for a fresh Debian/Ubuntu VPS.
  - `scripts/setup.sh` — interactive first-time setup.
  - `workflows/` — per-project Nix dev shells (also serve as templates).

See `agent-box/README.md` for bootstrap and daily-use details.