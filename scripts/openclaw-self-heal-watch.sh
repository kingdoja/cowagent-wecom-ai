#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY_LOG="${OPENCLAW_GATEWAY_LOG:-$HOME/Library/Logs/openclaw/gateway.log}"
TRIGGER_LOG="$HOME/.openclaw/self-heal-trigger.log"
COOLDOWN_FILE="$HOME/.openclaw/self-heal-trigger.timestamp"
COOLDOWN_SECONDS="${OPENCLAW_SELF_HEAL_EVENT_COOLDOWN_SECONDS:-300}"

mkdir -p "$HOME/.openclaw"
touch "$GATEWAY_LOG" "$TRIGGER_LOG"
chmod 600 "$TRIGGER_LOG"

is_failure_event() {
  local line="$1"
  [[ "$line" =~ \[model-fetch\].*status=5[0-9][0-9] ]] \
    || [[ "$line" =~ FailoverError:.*5[0-9][0-9] ]] \
    || [[ "$line" =~ (Sandbox\ mode\ requires\ Docker|Cannot\ connect\ to\ the\ Docker\ daemon) ]] \
    || [[ "$line" =~ openclaw-weixin.*(unauthorized|expired|disconnected|login\ required) ]] \
    || [[ "$line" =~ health-monitor.*(unhealthy|stale|restart) ]]
}

handle_line() {
  local line="$1" now last=0
  is_failure_event "$line" || return 0

  now="$(date +%s)"
  [[ -f "$COOLDOWN_FILE" ]] && last="$(cat "$COOLDOWN_FILE" 2>/dev/null || echo 0)"
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  if (( now - last < COOLDOWN_SECONDS )); then
    return 0
  fi
  printf '%s\n' "$now" > "$COOLDOWN_FILE"
  chmod 600 "$COOLDOWN_FILE"
  printf '%s matched Gateway failure event\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" >> "$TRIGGER_LOG"

  if [[ "${OPENCLAW_SELF_HEAL_EVENT_DRY_RUN:-0}" == "1" ]]; then
    return 0
  fi
  OPENCLAW_SELF_HEAL_EVENT_TRIGGER=1 \
    "$ROOT_DIR/scripts/openclaw-self-heal.sh" >> "$TRIGGER_LOG" 2>&1 || true
}

if [[ "${1:-}" == "--line" ]]; then
  handle_line "${2:-}"
  exit 0
fi

tail -n 0 -F "$GATEWAY_LOG" | while IFS= read -r line; do
  handle_line "$line"
done
