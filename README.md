# dotfiles

Declarative tooling layered over plain Nix. Currently contains `agent-box`, a
remote Linux server (VPS/VM) that runs OpenCode and Tailscale over Debian/Nix.

- `agent-box/` — agent box configuration (OpenCode, Tailscale, SSH, workflows).
  - `flake.nix` — agent toolchain buildEnv, pinned nixpkgs (OpenCode installs
    via its official installer and tracks the latest release).
  - `services/opencode.service` — OpenCode web UI systemd unit (agent user).
  - `scripts/install.sh` — one-command installer for a fresh Debian/Ubuntu VPS.
  - `scripts/setup.sh` — interactive first-time setup.
  - `workflows/` — per-project Nix dev shells (also serve as templates).

See `agent-box/README.md` for bootstrap and daily-use details.