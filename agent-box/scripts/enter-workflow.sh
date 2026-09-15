#!/usr/bin/env bash
# Enter a Nix development workflow.

set -euo pipefail

WORKFLOW_NAME="${1:-}"

if [[ -z "$WORKFLOW_NAME" ]]; then
    echo "Usage: $0 <workflow-name>" >&2
    exit 1
fi

WORKFLOW_DIR="/home/agent/workflow/$WORKFLOW_NAME"

if [[ ! -d "$WORKFLOW_DIR" ]]; then
    echo "ERROR: Workflow '$WORKFLOW_NAME' not found at $WORKFLOW_DIR" >&2
    echo "Create it with: new-workflow.sh $WORKFLOW_NAME" >&2
    exit 1
fi

cd "$WORKFLOW_DIR"
exec nix develop
