#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

openclaw gateway stop || true
"$ROOT_DIR/scripts/compose.sh" --env-file "$ROOT_DIR/.env" up -d cowagent

container_id="$($ROOT_DIR/scripts/compose.sh --env-file "$ROOT_DIR/.env" ps -q cowagent)"
[[ -n "$container_id" ]] || die "CowAgent did not start"

echo "OpenClaw stopped; CowAgent rollback container is running."
