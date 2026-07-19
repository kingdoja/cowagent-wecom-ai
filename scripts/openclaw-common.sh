#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/dotenv.sh"

OPENCLAW_VERSION="2026.7.1"
PARALLEL_VERSION="2026.7.1"
WEIXIN_VERSION="2.4.6"
LUCEN_IMAGE_VERSION="1.1.0"
SANDBOX_IMAGE="cowagent-openclaw-sandbox:${OPENCLAW_VERSION}"
OPENCLAW_HOME="${HOME}/.openclaw"
OPENCLAW_WORKSPACE="${HOME}/OpenClawWorkspace"
OPENCLAW_ENV="${OPENCLAW_HOME}/.env"
OPENCLAW_MODELS_FILE="$ROOT_DIR/openclaw/models.json"
TAILSCALE_CLI="/Applications/Tailscale.app/Contents/MacOS/Tailscale"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

file_mode() {
  stat -f '%Lp' "$1"
}

filevault_enabled() {
  fdesetup status 2>/dev/null | grep -q 'FileVault is On'
}

load_openclaw_env() {
  [[ -f "$OPENCLAW_ENV" ]] || die "missing $OPENCLAW_ENV"
  load_dotenv_file "$OPENCLAW_ENV" || die "failed to parse $OPENCLAW_ENV"
}

plugin_version() {
  local plugin_id="$1"
  openclaw plugins list --json \
    | jq -r --arg id "$plugin_id" '.plugins[] | select(.id == $id) | .version' \
    | head -1
}

scrub_openclaw_models_snapshot() {
  local models_file="$OPENCLAW_HOME/agents/main/agent/models.json"
  local temporary_file

  [[ -f "$models_file" ]] || return 0
  temporary_file="$(mktemp "${models_file}.tmp.XXXXXX")"
  if ! jq '
    if (.providers.relay.apiKey? | type) == "string"
    then .providers.relay.apiKey = "secretref-managed"
    else .
    end
  ' "$models_file" > "$temporary_file"; then
    rm -f "$temporary_file"
    return 1
  fi
  chmod 600 "$temporary_file"
  mv "$temporary_file" "$models_file"
}

wait_and_scrub_openclaw_models_snapshot() {
  local attempt

  for attempt in {1..30}; do
    if [[ -f "$OPENCLAW_HOME/agents/main/agent/models.json" ]] \
      && openclaw gateway call health --json --token "$OPENCLAW_GATEWAY_TOKEN" \
        | jq -e '.ok == true' >/dev/null 2>&1; then
      scrub_openclaw_models_snapshot
      return
    fi
    sleep 1
  done
  die "OpenClaw Gateway or models snapshot was not ready after startup"
}

run_openclaw_agent_with_cleanup() {
  local session_id="$1"
  local output command_status
  shift

  set +e
  output="$(openclaw agent --session-id "$session_id" "$@")"
  command_status=$?
  set -e

  openclaw sandbox recreate \
    --session "agent:main:explicit:${session_id}" \
    --force >/dev/null 2>&1 || true
  scrub_openclaw_models_snapshot

  printf '%s' "$output"
  return "$command_status"
}
