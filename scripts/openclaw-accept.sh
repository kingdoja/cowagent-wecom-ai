#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

"$ROOT_DIR/scripts/openclaw-preflight.sh"
"$ROOT_DIR/scripts/openclaw-audit.sh"

daily_status="$(jq -r '.models[] | select(.daily) | .failureExitCode' "$OPENCLAW_MODELS_FILE")"

set +e
OPENCLAW_RELAY_SMOKE_MODE=1 "$ROOT_DIR/scripts/openclaw-relay-gate.sh"
relay_status=$?
set -e

if (( relay_status != 0 )); then
  if [[ "$relay_status" == "$daily_status" ]]; then
    die "daily model failed its relay gate; main WeChat cutover is prohibited"
  fi

  failed_model="$(jq -r --argjson status "$relay_status" \
    '.models[] | select(.failureExitCode == $status) | .id' "$OPENCLAW_MODELS_FILE")"
  [[ -n "$failed_model" ]] \
    || die "relay compatibility gate failed with unknown status $relay_status"

  printf '%s failed its relay gate; running the 20-sample daily fallback gate.\n' "$failed_model" >&2
  if ! OPENCLAW_RELAY_FALLBACK_MODE=1 "$ROOT_DIR/scripts/openclaw-relay-gate.sh"; then
    die "daily model failed its 20-sample fallback gate; main WeChat cutover is prohibited"
  fi
  echo "Daily model passed; removing every unvalidated manual model alias." >&2
  "$ROOT_DIR/scripts/openclaw-apply-mini-fallback.sh"
fi

"$ROOT_DIR/scripts/openclaw-model-gate.sh"
"$ROOT_DIR/scripts/openclaw-search-gate.sh"
"$ROOT_DIR/scripts/openclaw-sandbox-gate.sh"
"$ROOT_DIR/scripts/openclaw-image-gate.sh"

mkdir -p "$ROOT_DIR/openclaw/test-results"
touch "$ROOT_DIR/openclaw/test-results/READY_FOR_WEIXIN"
chmod 600 "$ROOT_DIR/openclaw/test-results/READY_FOR_WEIXIN"
echo "Non-channel acceptance passed. The second-account WeChat QR gate is unlocked."
