#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

require_command jq
load_openclaw_env

runs="${OPENCLAW_GATE_RUNS:-20}"
enabled_models="$(openclaw config get --json agents.defaults.models)"
daily_alias="$(jq -r '.dailyAlias' "$OPENCLAW_MODELS_FILE")"
jq -e --arg alias "$daily_alias" 'to_entries | any(.value.alias == $alias)' \
  <<<"$enabled_models" >/dev/null || die "daily model alias is not enabled"
results_dir="$ROOT_DIR/openclaw/test-results"
mkdir -p "$results_dir"
chmod 700 "$results_dir"
results_file="$results_dir/model-gate-$(date +%Y%m%d-%H%M%S).jsonl"
touch "$results_file"
chmod 600 "$results_file"

run_agent() {
  local model="$1"
  local prompt="$2"
  local expected="$3"
  local label="$4"
  local started ended elapsed output reply ok command_ok session_id session_file

  session_id="gate-${label}-$$-${RANDOM}"
  session_file="$OPENCLAW_HOME/agents/main/sessions/${session_id}.jsonl"
  started="$(date +%s)"
  if output="$(openclaw agent \
    --session-id "$session_id" \
    --model "$model" \
    --message "$prompt" \
    --timeout 180 \
    --json 2>/dev/null)"; then
    command_ok=true
  else
    command_ok=false
  fi
  ended="$(date +%s)"
  elapsed=$((ended - started))
  reply="$(jq -r '[.result.payloads[]? | select(.isError != true and .isReasoning != true) | .text // empty] | join("\n")' <<<"${output:-{}}" 2>/dev/null || true)"
  if [[ -z "$reply" && -f "$session_file" ]]; then
    reply="$(jq -rs '
      [
        .[]
        | select(.type == "message" and .message.role == "assistant")
        | [.message.content[]? | select(.type == "text") | .text]
        | join("\n")
        | select(length > 0)
      ]
      | last // ""
    ' "$session_file" 2>/dev/null || true)"
  fi
  [[ "$command_ok" == true && "$reply" == *"$expected"* ]] && ok=true || ok=false

  jq -cn \
    --arg model "$model" \
    --arg label "$label" \
    --argjson elapsed "$elapsed" \
    --argjson commandOk "$command_ok" \
    --argjson ok "$ok" \
    '{model:$model,label:$label,elapsedSeconds:$elapsed,commandOk:$commandOk,ok:$ok}' \
    >> "$results_file"
  printf '%-18s %-5s %3ss\n' "$label" "$ok" "$elapsed"
  [[ "$ok" == true ]]
}

failures=0
while IFS=$'\t' read -r model_key alias; do
  if ! jq -e --arg key "$model_key" 'has($key)' <<<"$enabled_models" >/dev/null; then
    continue
  fi
  if [[ "$alias" == "$daily_alias" ]]; then
    for ((i = 1; i <= runs; i++)); do
      run_agent "$alias" "Reply with exactly: gate-ok" "gate-ok" "${alias}-${i}" \
        || failures=$((failures + 1))
    done
  else
    run_agent "$alias" "Reply with exactly: ${alias}-ok" "${alias}-ok" "$alias" \
      || failures=$((failures + 1))
  fi
done < <(jq -r '
  .provider as $provider
  | .models[]
  | [$provider + "/" + .id, .alias]
  | @tsv
' "$OPENCLAW_MODELS_FILE")
tool_loop_file="gate/tool-loop-$$-${RANDOM}.txt"
run_agent "$daily_alias" \
  "Use the write tool to create ${tool_loop_file} containing tool-loop-ok, then read it and reply with exactly: tool-loop-ok" \
  "tool-loop-ok" "tool-loop" || failures=$((failures + 1))
rm -f "$OPENCLAW_WORKSPACE/$tool_loop_file"

p95="$(jq -s --arg prefix "${daily_alias}-" \
  '[.[] | select(.label | startswith($prefix)) | .elapsedSeconds] | sort | .[((length * 95 + 99) / 100 | floor) - 1]' \
  "$results_file")"
printf 'Daily total-time P95: %ss (CLI total time; streaming TTFT is checked separately).\n' "$p95"

if (( failures > 0 )); then
  printf 'Model gate failed: %d empty/invalid response(s). Results: %s\n' "$failures" "$results_file" >&2
  exit 1
fi

echo "Model gate passed. Results: $results_file"
