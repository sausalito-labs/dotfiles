#!/usr/bin/env bash
# Remove a workflow and optionally garbage collect the Nix store.

set -euo pipefail

WORKFLOW_NAME="${1:-}"

if [[ -z "$WORKFLOW_NAME" ]]; then
    echo "Usage: $0 <workflow-name>" >&2
    exit 1
fi

WORKFLOW_DIR="/etc/nixos/dotfiles/agent-box/workflow/$WORKFLOW_NAME"

if [[ ! -d "$WORKFLOW_DIR" ]]; then
    echo "ERROR: Workflow '$WORKFLOW_NAME' not found at $WORKFLOW_DIR" >&2
    exit 1
fi

read -rp "Remove workflow '$WORKFLOW_NAME'? [y/N] " CONFIRM
if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    rm -rf "$WORKFLOW_DIR"
    echo "Removed $WORKFLOW_DIR"
    read -rp "Run nix-collect-garbage now? [y/N] " GC
    if [[ "$GC" =~ ^[Yy]$ ]]; then
        nix-collect-garbage -d
    fi
else
    echo "Cancelled."
fi
