#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"
load_openclaw_env

results_dir="$ROOT_DIR/openclaw/test-results"
mkdir -p "$results_dir"
chmod 700 "$results_dir"
result="$results_dir/relay-gate-$(date +%Y%m%d-%H%M%S).json"

set +e
node "$ROOT_DIR/scripts/openclaw-relay-gate.mjs" | tee "$result"
status=${PIPESTATUS[0]}
set -e
chmod 600 "$result"
exit "$status"
