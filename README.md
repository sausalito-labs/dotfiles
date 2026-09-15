# dotfiles

Declarative system configuration, organized by environment.

- `gamedev/` — NixOS config for a headless gamedev box (OpenCode, Godot,
  Tailscale/Headscale, One Arcade demo server).
  - `modules/gamedev-box.nix` — reusable, vendor-agnostic NixOS module.
  - `hosts/netcup/` — machine-specific config for the current netcup VPS.
  - `scripts/setup.sh` — interactive first-boot setup.

See `gamedev/hosts/netcup/README.md` for the full migration and daily-use guide.
