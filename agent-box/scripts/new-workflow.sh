#!/usr/bin/env bash
# Create a new workflow from an existing workflow template.

set -euo pipefail

WORKFLOW_NAME="${1:-}"
TEMPLATE_NAME="${2:-template}"
WORKFLOWS_DIR="/etc/nixos/dotfiles/agent-box/workflows"

if [[ -z "$WORKFLOW_NAME" ]]; then
    echo "Usage: $0 <workflow-name> [template-name]" >&2
    echo "Available templates:" >&2
    ls -1 "$WORKFLOWS_DIR"/ >&2
    exit 1
fi

TEMPLATE_DIR="$WORKFLOWS_DIR/$TEMPLATE_NAME"
TARGET_DIR="$WORKFLOWS_DIR/$WORKFLOW_NAME"

if [[ ! -d "$TEMPLATE_DIR" ]]; then
    echo "ERROR: Template '$TEMPLATE_NAME' not found at $TEMPLATE_DIR" >&2
    exit 1
fi

if [[ -d "$TARGET_DIR" ]]; then
    echo "ERROR: Workflow '$WORKFLOW_NAME' already exists at $TARGET_DIR" >&2
    exit 1
fi

cp -r "$TEMPLATE_DIR" "$TARGET_DIR"
chown -R agent:agent "$TARGET_DIR"

echo "Created workflow '$WORKFLOW_NAME' at $TARGET_DIR"
echo "Edit $TARGET_DIR/flake.nix and run:"
echo "  enter-workflow.sh $WORKFLOW_NAME"
