#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

SELF_HEAL_ENV="${OPENCLAW_SELF_HEAL_ENV:-$OPENCLAW_HOME/self-heal.env}"
STATE_FILE="$OPENCLAW_HOME/self-heal-state.json"
LOG_FILE="$OPENCLAW_HOME/self-heal.log"
BACKUP_DIR="$OPENCLAW_HOME/self-heal-backups"
LOCK_DIR="${TMPDIR:-/tmp}/openclaw-self-heal-$(id -u).lock"

[[ -f "$SELF_HEAL_ENV" ]] || die "missing $SELF_HEAL_ENV"
load_dotenv_file "$SELF_HEAL_ENV" || die "failed to parse $SELF_HEAL_ENV"
load_openclaw_env
require_command curl
require_command jq
require_command node
require_command docker

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "OpenClaw self-heal is already running."
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" | tee -a "$LOG_FILE"
}

write_state() {
  local failures="$1" status="$2" detail="$3" candidate="${4:-}"
  local temporary
  temporary="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
  jq -cn \
    --argjson failures "$failures" \
    --arg status "$status" \
    --arg detail "$detail" \
    --arg candidate "$candidate" \
    --arg updatedAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    '{consecutiveFailures:$failures,status:$status,detail:$detail,candidate:$candidate,updatedAt:$updatedAt}' \
    > "$temporary"
  chmod 600 "$temporary"
  mv "$temporary" "$STATE_FILE"
}

notify_failure() {
  local message="$1"
  /usr/bin/osascript -e "display notification \"${message//\"/} \" with title \"OpenClaw self-heal needs attention\"" \
    >/dev/null 2>&1 || true
}

docker_ready() {
  docker info >/dev/null 2>&1
}

recover_docker() {
  local timeout_seconds="${OPENCLAW_SELF_HEAL_DOCKER_START_TIMEOUT_SECONDS:-90}"
  local app_name="${OPENCLAW_SELF_HEAL_DOCKER_APP:-Docker}"
  local attempt

  if docker_ready; then
    return 0
  fi

  if [[ "${OPENCLAW_SELF_HEAL_DOCKER_AUTO_START:-1}" != "1" ]]; then
    log "Docker daemon unavailable and automatic Docker Desktop start is disabled"
    return 1
  fi

  log "Docker daemon unavailable; starting Docker Desktop (${app_name})"
  /usr/bin/open -a "$app_name" >/dev/null 2>&1 || true
  for ((attempt = 1; attempt <= timeout_seconds; attempt += 2)); do
    if docker_ready; then
      log "Docker daemon recovered after $((attempt - 1))s"
      return 0
    fi
    sleep 2
  done
  log "Docker daemon did not recover within ${timeout_seconds}s"
  return 1
}

run_status() {
  "$ROOT_DIR/scripts/openclaw-status.sh" 2>&1
}

docker_recovered=true
if ! recover_docker; then
  docker_recovered=false
  status_output="ERROR: Docker daemon is unavailable"
  status_ok=false
elif [[ "${OPENCLAW_SELF_HEAL_FORCE_FAILURE:-0}" == "1" ]]; then
  status_output="ERROR: forced self-heal test failure"
  status_ok=false
else
  status_output="$(run_status)" && status_ok=true || status_ok=false
fi
if [[ "$status_ok" == true ]]; then
  write_state 0 healthy "all checks passed"
  log "healthy: Gateway, Weixin heartbeat, and chat relay passed"
  exit 0
fi

previous_failures="$(jq -r '.consecutiveFailures // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
failures=$((previous_failures + 1))
failure_detail="$(tail -1 <<<"$status_output")"
log "failure ${failures}: $failure_detail"

if [[ "$docker_recovered" != true ]]; then
  write_state "$failures" unresolved "Docker daemon is unavailable"
  notify_failure "Docker Desktop did not recover; OpenClaw remains unavailable."
  exit 1
fi

if grep -Eq 'Gateway health|Gateway RPC|Weixin channel|heartbeat is stale' <<<"$failure_detail"; then
  log "attempting Gateway and Weixin restart"
  if "$ROOT_DIR/scripts/openclaw-gateway.sh" restart >>"$LOG_FILE" 2>&1 \
    && status_output="$(run_status)"; then
    write_state 0 repaired "Gateway restart restored service"
    log "repaired: Gateway restart restored all checks"
    exit 0
  fi
fi

if [[ "${OPENCLAW_SELF_HEAL_EVENT_TRIGGER:-0}" == "1" ]]; then
  threshold=1
else
  threshold="${OPENCLAW_SELF_HEAL_FAILURE_THRESHOLD:-2}"
fi
if (( failures < threshold )); then
  write_state "$failures" observing "waiting for failure threshold"
  log "observing: failure threshold is $threshold"
  exit 0
fi

candidate_names="${OPENCLAW_SELF_HEAL_CANDIDATES:-}"
current_base="${RELAY_API_BASE%/}"
current_model="${RELAY_MODEL:-$(jq -r '.defaultModelId' "$OPENCLAW_MODELS_FILE")}"

candidate_value() {
  local candidate="$1" suffix="$2" candidate_upper variable
  candidate_upper="$(tr '[:lower:]' '[:upper:]' <<<"$candidate")"
  variable="OPENCLAW_SELF_HEAL_${candidate_upper}_${suffix}"
  printf '%s' "${!variable:-}"
}

candidate_key() {
  local candidate="$1" direct key_file key_name
  direct="$(candidate_value "$candidate" API_KEY)"
  if [[ -n "$direct" ]]; then
    printf '%s' "$direct"
    return
  fi
  key_file="$(candidate_value "$candidate" KEY_FILE)"
  key_name="$(candidate_value "$candidate" KEY_NAME)"
  [[ -n "$key_file" && -n "$key_name" && -f "$key_file" ]] || return 1
  dotenv_value "$key_file" "$key_name"
}

write_runtime_env() {
  local target="$1" base="$2" key="$3" model="$4" temporary
  temporary="$(mktemp "${target}.tmp.XXXXXX")"
  umask 077
  {
    printf "RELAY_API_BASE='%s'\n" "$base"
    printf "RELAY_API_KEY='%s'\n" "$key"
    printf "RELAY_MODEL='%s'\n" "$model"
    printf "IMAGE_API_BASE='%s'\n" "$IMAGE_API_BASE"
    printf "IMAGE_API_KEY='%s'\n" "$IMAGE_API_KEY"
    printf "OPENCLAW_GATEWAY_TOKEN='%s'\n" "$OPENCLAW_GATEWAY_TOKEN"
    printf "OPENCLAW_TAILSCALE_ORIGIN='%s'\n" "$OPENCLAW_TAILSCALE_ORIGIN"
  } > "$temporary"
  chmod 600 "$temporary"
  mv "$temporary" "$target"
}

apply_model_config() {
  local model="$1" name="$2"
  jq -cn --arg model "$model" --arg name "$name" '
    {
      models: {providers: {relay: {models: [{
        id:$model, name:$name, reasoning:true, input:["text","image"],
        agentRuntime:{id:"openclaw"},
        compat:{supportsTools:true,supportsReasoningEffort:true,supportsUsageInStreaming:true}
      }]}}},
      agents: {defaults: {
        model:{primary:("relay/" + $model),fallbacks:[]},
        utilityModel:("relay/" + $model),
        thinkingDefault:"high",
        models:{($model | "relay/" + .):{
          alias:"daily",params:{reasoningEffort:"high"},agentRuntime:{id:"openclaw"},streaming:true
        }}
      }}
    }
  ' | openclaw config patch --stdin \
    --replace-path models.providers.relay.models \
    --replace-path agents.defaults.models >/dev/null
}

for candidate in ${candidate_names//,/ }; do
  base="$(candidate_value "$candidate" BASE_URL)"
  key="$(candidate_key "$candidate" || true)"
  model="$(candidate_value "$candidate" MODEL)"
  name="$(candidate_value "$candidate" MODEL_NAME)"
  [[ -n "$base" && -n "$key" && -n "$model" ]] || continue
  [[ "${base%/}" == "$current_base" && "$model" == "$current_model" ]] && continue

  log "probing candidate $candidate ($model)"
  probe_file="$(mktemp)"
  if OPENCLAW_PROBE_BASE_URL="$base" \
    OPENCLAW_PROBE_API_KEY="$key" \
    OPENCLAW_PROBE_MODEL="$model" \
    node "$ROOT_DIR/scripts/openclaw-provider-probe.mjs" >"$probe_file" 2>>"$LOG_FILE"; then
    log "candidate $candidate passed two text, streaming, and tool-call probes"
  else
    probe_error="$(jq -r '.error // "compatibility probe failed"' "$probe_file" 2>/dev/null || echo 'compatibility probe failed')"
    log "candidate $candidate rejected: $probe_error"
    rm -f "$probe_file"
    continue
  fi
  rm -f "$probe_file"

  stamp="$(date +%Y%m%d-%H%M%S)"
  backup="$BACKUP_DIR/$stamp"
  mkdir -p "$backup"
  chmod 700 "$backup"
  cp "$OPENCLAW_ENV" "$backup/runtime.env"
  cp "$ROOT_DIR/openclaw/.env" "$backup/repository.env"
  cp "$OPENCLAW_HOME/openclaw.json" "$backup/openclaw.json"
  chmod 600 "$backup"/*

  if [[ "${OPENCLAW_SELF_HEAL_DRY_RUN:-0}" == "1" ]]; then
    write_state "$failures" dry-run "candidate verified; activation skipped" "$candidate"
    log "dry-run: candidate $candidate verified; activation skipped"
    exit 0
  fi

  if write_runtime_env "$OPENCLAW_ENV" "$base" "$key" "$model" \
    && write_runtime_env "$ROOT_DIR/openclaw/.env" "$base" "$key" "$model" \
    && apply_model_config "$model" "${name:-$model}" \
    && "$ROOT_DIR/scripts/openclaw-gateway.sh" restart >>"$LOG_FILE" 2>&1 \
    && OPENCLAW_STATUS_MODEL="$model" run_status >>"$LOG_FILE" 2>&1 \
    && agent_output="$(openclaw agent --session-id "self-heal-$stamp" \
      --message 'Reply with exactly: self-heal-ok' --timeout "$OPENCLAW_RUN_TIMEOUT_SECONDS" --json 2>>"$LOG_FILE")" \
    && jq -e '[.result.payloads[]?.text // empty] | join("\n") | contains("self-heal-ok")' \
      <<<"$agent_output" >/dev/null; then
    write_state 0 switched "switched after verified failure" "$candidate"
    log "switched: $candidate ($model) is active and verified"
    exit 0
  fi

  log "candidate $candidate failed after activation; restoring previous configuration"
  cp "$backup/runtime.env" "$OPENCLAW_ENV"
  cp "$backup/repository.env" "$ROOT_DIR/openclaw/.env"
  cp "$backup/openclaw.json" "$OPENCLAW_HOME/openclaw.json"
  "$ROOT_DIR/scripts/openclaw-gateway.sh" restart >>"$LOG_FILE" 2>&1 || true
done

write_state "$failures" unresolved "no verified fallback provider available"
log "unresolved: no verified fallback provider is currently available"
notify_failure "No verified fallback provider is available."
exit 1
