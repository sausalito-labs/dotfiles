#!/usr/bin/env bash
# Create a new agent environment from a template.

set -euo pipefail

ENV_NAME="${1:-}"
TEMPLATE_NAME="${2:-template}"

if [[ -z "$ENV_NAME" ]]; then
    echo "Usage: $0 <env-name> [template-name]" >&2
    echo "Available templates:" >&2
    ls -1 /etc/nixos/dotfiles/agent-box/templates/envs/ >&2
    exit 1
fi

TEMPLATE_DIR="/etc/nixos/dotfiles/agent-box/templates/envs/$TEMPLATE_NAME"
TARGET_DIR="/etc/nixos/dotfiles/agent-box/agent/envs/$ENV_NAME"

if [[ ! -d "$TEMPLATE_DIR" ]]; then
    echo "ERROR: Template '$TEMPLATE_NAME' not found at $TEMPLATE_DIR" >&2
    exit 1
fi

if [[ -d "$TARGET_DIR" ]]; then
    echo "ERROR: Environment '$ENV_NAME' already exists at $TARGET_DIR" >&2
    exit 1
fi

mkdir -p /etc/nixos/dotfiles/agent-box/agent/envs
cp -r "$TEMPLATE_DIR" "$TARGET_DIR"
chown -R agent:agent "$TARGET_DIR"

echo "Created environment '$ENV_NAME' at $TARGET_DIR"
echo "Edit /home/agent/envs/$ENV_NAME/flake.nix and run:"
echo "  enter-env.sh $ENV_NAME"
