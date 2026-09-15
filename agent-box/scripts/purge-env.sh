#!/usr/bin/env bash
# Remove an environment and optionally garbage collect the Nix store.

set -euo pipefail

ENV_NAME="${1:-}"

if [[ -z "$ENV_NAME" ]]; then
    echo "Usage: $0 <env-name>" >&2
    exit 1
fi

ENV_DIR="/etc/nixos/agent-box/agent/envs/$ENV_NAME"

if [[ ! -d "$ENV_DIR" ]]; then
    echo "ERROR: Environment '$ENV_NAME' not found at $ENV_DIR" >&2
    exit 1
fi

read -rp "Remove environment '$ENV_NAME'? [y/N] " CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    rm -rf "$ENV_DIR"
    echo "Removed $ENV_DIR"
    read -rp "Run nix-collect-garbage now? [y/N] " GC
    if [[ "$GC" =~ ^[Yy]$ ]]; then
        nix-collect-garbage -d
    fi
else
    echo "Cancelled."
fi
