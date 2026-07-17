#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

errors=0
fail() {
  printf 'ERROR: %s\n' "$1" >&2
  errors=$((errors + 1))
}

config_json() {
  openclaw config get --json "$1" 2>/dev/null || printf 'null\n'
}

for cmd in node npm docker jq openclaw; do
  command -v "$cmd" >/dev/null 2>&1 || fail "$cmd is required"
done

filevault_enabled || fail "FileVault is off"
[[ "$(node --version 2>/dev/null || true)" == "v22.22.3" ]] || fail "Node must be v22.22.3"
[[ "$(openclaw --version 2>/dev/null | awk '{print $2}')" == "$OPENCLAW_VERSION" ]] \
  || fail "OpenClaw must be $OPENCLAW_VERSION"
[[ "$(plugin_version parallel 2>/dev/null || true)" == "$PARALLEL_VERSION" ]] \
  || fail "Parallel plugin must be $PARALLEL_VERSION"
[[ "$(plugin_version openclaw-weixin 2>/dev/null || true)" == "$WEIXIN_VERSION" ]] \
  || fail "Weixin plugin must be $WEIXIN_VERSION"

docker image inspect "$SANDBOX_IMAGE" >/dev/null 2>&1 || fail "sandbox image is missing"

for dir in "$OPENCLAW_HOME" "$OPENCLAW_WORKSPACE"; do
  [[ -d "$dir" ]] || fail "$dir is missing"
  [[ ! -d "$dir" || "$(file_mode "$dir")" == "700" ]] || fail "$dir must have mode 700"
done

for file in "$OPENCLAW_ENV" "$OPENCLAW_HOME/openclaw.json" "$OPENCLAW_HOME/exec-approvals.json"; do
  [[ -f "$file" ]] || fail "$file is missing"
  [[ ! -f "$file" || "$(file_mode "$file")" == "600" ]] || fail "$file must have mode 600"
done

if [[ -f "$OPENCLAW_ENV" ]]; then
  load_openclaw_env
  [[ "${RELAY_API_BASE:-}" == https://* \
    || "${RELAY_API_BASE:-}" == http://127.0.0.1* \
    || "${RELAY_API_BASE:-}" == http://localhost* ]] \
    || fail "RELAY_API_BASE must use HTTPS unless it is loopback"
  [[ -n "${RELAY_API_KEY:-}" && "$RELAY_API_KEY" != replace-* ]] \
    || fail "RELAY_API_KEY is missing or still a placeholder"
  gateway_token="${OPENCLAW_GATEWAY_TOKEN:-}"
  [[ ${#gateway_token} -ge 64 ]] \
    || fail "OPENCLAW_GATEWAY_TOKEN must be at least 64 characters"
  if [[ -f "$ROOT_DIR/.env" ]]; then
    cow_key="$(dotenv_value "$ROOT_DIR/.env" RELAY_API_KEY)"
    [[ -z "$cow_key" || "$RELAY_API_KEY" != "$cow_key" ]] \
      || fail "OpenClaw is reusing CowAgent's relay key"
  fi
fi

gateway_cfg="$(config_json gateway)"
agent_cfg="$(config_json agents.defaults)"
tools_cfg="$(config_json tools)"
session_cfg="$(config_json session)"
plugins_cfg="$(config_json plugins)"
models_cfg="$(config_json models)"
model_policy="$(jq -c . "$OPENCLAW_MODELS_FILE")"

[[ "$(jq -r '.mode // empty' <<<"$gateway_cfg")" == 'local' ]] || fail "gateway.mode must be local"
[[ "$(jq -r '.bind // empty' <<<"$gateway_cfg")" == 'loopback' ]] || fail "gateway.bind must be loopback"
[[ "$(jq -r '.port // 0' <<<"$gateway_cfg")" == '18789' ]] || fail "gateway.port must be 18789"
[[ "$(jq -r '.tailscale.mode // empty' <<<"$gateway_cfg")" == 'serve' ]] || fail "Tailscale mode must be serve"
[[ "$(jq -r '.terminal.enabled' <<<"$gateway_cfg")" == 'false' ]] || fail "operator terminal must be disabled"
jq -e '.auth.mode == "token" and .auth.allowTailscale == true and .tailscale.preserveFunnel == false' \
  <<<"$gateway_cfg" >/dev/null || fail "Gateway token/Tailscale Serve auth policy drifted"
[[ "$(jq -r '.sandbox.mode // empty' <<<"$agent_cfg")" == 'all' ]] || fail "sandbox mode must be all"
[[ "$(jq -r '.sandbox.scope // empty' <<<"$agent_cfg")" == 'session' ]] || fail "sandbox scope must be session"
[[ "$(jq -r '.sandbox.docker.network // empty' <<<"$agent_cfg")" == 'none' ]] || fail "sandbox network must be none"
[[ "$(jq -r '.sandbox.docker.readOnlyRoot // empty' <<<"$agent_cfg")" == 'true' ]] || fail "sandbox rootfs must be read-only"
jq -e '.sandbox.workspaceAccess == "rw"
  and .sandbox.docker.image == "cowagent-openclaw-sandbox:2026.7.1"
  and .sandbox.docker.user == "1000:1000"
  and .sandbox.docker.capDrop == ["ALL"]
  and .sandbox.docker.binds == []
  and .sandbox.browser.enabled == false
  and .sandbox.browser.allowHostControl == false' \
  <<<"$agent_cfg" >/dev/null || fail "sandbox image, mounts, user, capabilities, or browser policy drifted"
[[ "$(jq -r '.exec.host // empty' <<<"$tools_cfg")" == 'sandbox' ]] || fail "exec host must be sandbox"
[[ "$(jq -r '.fs.workspaceOnly // empty' <<<"$tools_cfg")" == 'true' ]] || fail "filesystem tools must be workspace-only"
[[ "$(jq -r '.elevated.enabled' <<<"$tools_cfg")" == 'false' ]] || fail "elevated tools must be disabled"
jq -e '.web.search.enabled == true and .web.search.provider == "parallel-free"
  and .web.search.openaiCodex.enabled == false and .web.fetch.enabled == true' \
  <<<"$tools_cfg" >/dev/null || fail "web search/fetch policy drifted"
jq -e '(["message", "cron", "gateway", "nodes", "sessions_spawn", "subagents", "browser"] - (.deny // [])) == []' \
  <<<"$tools_cfg" >/dev/null || fail "one or more prohibited tools are no longer denied"
[[ "$(jq -r '.dmScope // empty' <<<"$session_cfg")" == 'per-account-channel-peer' ]] || fail "DM scope is not isolated"

jq -e --argjson policy "$model_policy" '
  . as $config
  | $policy.provider as $provider
  | ($policy.models | map($provider + "/" + .id) | sort) as $fullSet
  | ($policy.models | map(select(.daily) | $provider + "/" + .id) | sort) as $dailySet
  | (.models | keys | sort) as $enabledSet
  | ($enabledSet == $fullSet or $enabledSet == $dailySet)
    and (.model.primary == $dailySet[0])
    and ((.model.fallbacks // []) == [])
    and all($policy.models[];
      . as $model
      | ($provider + "/" + $model.id) as $key
      | (($enabledSet | index($key)) == null)
        or (
          $config.models[$key].alias == $model.alias
          and $config.models[$key].params.reasoningEffort == $model.reasoningEffort
          and $config.models[$key].agentRuntime.id == "openclaw"
          and $config.models[$key].streaming == true
        )
    )
' <<<"$agent_cfg" >/dev/null || fail "approved model set, aliases, or fallback policy drifted"
jq -e '(.allow // []) | sort == ["memory-core", "openclaw-weixin", "parallel"]' \
  <<<"$plugins_cfg" >/dev/null || fail "plugin allowlist must contain only Memory Core, Parallel, and Weixin"
jq -e '(.models // {} | to_entries) as $models | ($models | length) > 0 and ($models | all(.value.agentRuntime.id == "openclaw"))' \
  <<<"$agent_cfg" >/dev/null || fail "every allowed model must use the OpenClaw runtime"
jq -e --argjson policy "$model_policy" '.mode == "replace"
  and .providers[$policy.provider].api == "openai-completions"
  and ((.providers[$policy.provider].models // []) | map(.id) | sort) == ($policy.models | map(.id) | sort)
  and ((.providers[$policy.provider].models // []) | all(.agentRuntime.id == "openclaw"))' \
  <<<"$models_cfg" >/dev/null || fail "relay provider catalog/runtime policy drifted"

openclaw approvals get --json 2>/dev/null \
  | jq -e '.file.defaults.security == "deny" and .file.defaults.ask == "off" and .file.defaults.askFallback == "deny"' >/dev/null \
  || fail "host exec approvals must be deny/off/deny"

ac_sleep="$(pmset -g custom | awk '/AC Power/{ac=1; next} ac && $1=="sleep"{print $2; exit}')"
[[ "$ac_sleep" == "0" ]] || fail "AC system sleep must be 0; currently ${ac_sleep:-unknown}"

[[ -x "$TAILSCALE_CLI" ]] || fail "Tailscale.app CLI is missing"
if [[ -x "$TAILSCALE_CLI" ]]; then
  "$TAILSCALE_CLI" status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null \
    || fail "Tailscale is not connected"
fi

if [[ -f "$ROOT_DIR/.env" ]]; then
  cow_id="$($ROOT_DIR/scripts/compose.sh --env-file "$ROOT_DIR/.env" ps -q cowagent 2>/dev/null || true)"
  [[ -n "$cow_id" ]] || fail "CowAgent rollback container is not running"
fi

if [[ -f "$OPENCLAW_HOME/openclaw.json" ]]; then
  openclaw config validate >/dev/null || fail "OpenClaw config validation failed"
fi

if (( errors > 0 )); then
  printf '\nOpenClaw preflight failed with %d issue(s).\n' "$errors" >&2
  exit 1
fi

echo "OpenClaw preflight passed."
