#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"
load_openclaw_env

require_command curl
require_command jq

printf 'OpenClaw: %s\n' "$(openclaw --version)"
health_status="$(openclaw gateway call health --json --timeout 10000 \
  --token "$OPENCLAW_GATEWAY_TOKEN")" \
  || die "authenticated Gateway health RPC failed"
jq -e '.ok == true' <<<"$health_status" >/dev/null \
  || die "Gateway health response was not ok"
echo "Authenticated Gateway RPC: ok"

now_ms="$(($(date +%s) * 1000))"
weixin_max_event_age_ms="${OPENCLAW_WEIXIN_MAX_EVENT_AGE_MS:-180000}"
if ! jq -e \
  --argjson now "$now_ms" \
  --argjson maxAge "$weixin_max_event_age_ms" '
    .channels["openclaw-weixin"]
    | .enabled == true
      and .configured == true
      and .running == true
      and .restartPending == false
      and .lastError == null
      and (.lastEventAt | type) == "number"
      and ($now - .lastEventAt) <= $maxAge
  ' <<<"$health_status" >/dev/null; then
  die "Weixin channel is not running or its long-poll heartbeat is stale"
fi
echo "Weixin long-poll heartbeat: ok"

status_model="${OPENCLAW_STATUS_MODEL:-${RELAY_MODEL:-$(jq -r '.defaultModelId' "$OPENCLAW_MODELS_FILE")}}"
default_model="relay/$status_model"
relay_model="${default_model#relay/}"
probe_payload="$(jq -cn --arg model "$relay_model" '
  {model:$model,messages:[{role:"user",content:"Reply with exactly: status-ok"}],stream:false,max_tokens:32}
')"
probe_file="$(mktemp)"
trap 'rm -f "$probe_file"' EXIT
probe_status="$(curl --silent --show-error \
  --connect-timeout 10 --max-time 60 \
  --output "$probe_file" --write-out '%{http_code}' \
  -H "Authorization: Bearer $RELAY_API_KEY" \
  -H "Content-Type: application/json" \
  --data "$probe_payload" \
  "${RELAY_API_BASE%/}/chat/completions" || true)"
probe_reply="$(jq -r '.choices[0].message.content // empty' "$probe_file" 2>/dev/null || true)"
if [[ "$probe_status" != "200" || "$probe_reply" != *status-ok* ]]; then
  probe_error="$(jq -r '.error.message // .error // empty' "$probe_file" 2>/dev/null || true)"
  [[ -n "$probe_error" ]] || probe_error="empty or invalid response"
  die "chat relay probe failed for $default_model (HTTP ${probe_status:-000}): $probe_error"
fi
echo "Chat relay ($default_model): ok"

if [[ -x "$TAILSCALE_CLI" ]]; then
  "$TAILSCALE_CLI" serve status || true
fi

cow_id="$($ROOT_DIR/scripts/compose.sh --env-file "$ROOT_DIR/.env" ps -q cowagent 2>/dev/null || true)"
if [[ -n "$cow_id" ]]; then
  printf 'CowAgent rollback: running (%s)\n' "${cow_id:0:12}"
else
  echo "CowAgent rollback: not running"
fi
