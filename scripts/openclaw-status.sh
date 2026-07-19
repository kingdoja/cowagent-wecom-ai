#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"
load_openclaw_env

printf 'OpenClaw: %s\n' "$(openclaw --version)"
printf 'Parallel plugin: %s\n' "$(plugin_version parallel)"
printf 'Weixin plugin: %s\n' "$(plugin_version openclaw-weixin)"
printf 'Config: %s\n' "$(openclaw config file)"
openclaw gateway status --no-probe
openclaw gateway call health --json --token "$OPENCLAW_GATEWAY_TOKEN" \
  | jq -e '.ok == true' >/dev/null \
  || die "authenticated Gateway health RPC failed"
echo "Authenticated Gateway RPC: ok"

if [[ -x "$TAILSCALE_CLI" ]]; then
  "$TAILSCALE_CLI" serve status || true
fi

cow_id="$($ROOT_DIR/scripts/compose.sh --env-file "$ROOT_DIR/.env" ps -q cowagent 2>/dev/null || true)"
if [[ -n "$cow_id" ]]; then
  printf 'CowAgent rollback: running (%s)\n' "${cow_id:0:12}"
else
  echo "CowAgent rollback: not running"
fi
