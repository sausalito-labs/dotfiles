#!/usr/bin/env bash
# Enter a Nix development environment.

set -euo pipefail

ENV_NAME="${1:-}"

if [[ -z "$ENV_NAME" ]]; then
    echo "Usage: $0 <env-name>" >&2
    exit 1
fi

ENV_DIR="/home/agent/envs/$ENV_NAME"

if [[ ! -d "$ENV_DIR" ]]; then
    echo "ERROR: Environment '$ENV_NAME' not found at $ENV_DIR" >&2
    echo "Create it with: new-env.sh $ENV_NAME" >&2
    exit 1
fi

cd "$ENV_DIR"
exec nix develop
