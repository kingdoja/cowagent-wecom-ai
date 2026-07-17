#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

container_id="$(./scripts/compose.sh --env-file .env ps -q cowagent)"
if [[ -z "$container_id" ]]; then
  echo "CowAgent container is not running. Start it with: make up" >&2
  exit 1
fi

if ! output="$(docker exec -w /app "$container_id" python /opt/cowagent/test_streaming.py 2>&1)"; then
  echo "$output" | tail -40 >&2
  exit 1
fi

echo "$output" | grep -E '\[StreamingPatch\] reply complete|Streaming smoke test passed'
