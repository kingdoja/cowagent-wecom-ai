#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

load_openclaw_env
openclaw config validate
openclaw doctor
openclaw gateway call health --json --token "$OPENCLAW_GATEWAY_TOKEN" \
  | jq -e '.ok == true' >/dev/null \
  || die "authenticated Gateway health RPC failed"
openclaw security audit
openclaw sandbox explain
scrub_openclaw_models_snapshot
openclaw secrets audit --check
