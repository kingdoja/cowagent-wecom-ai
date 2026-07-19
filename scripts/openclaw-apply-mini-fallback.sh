#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

patch_args=(--stdin)
dry_run=false
if [[ "${1:-}" == "--dry-run" ]]; then
  patch_args+=(--dry-run)
  dry_run=true
elif (( $# > 0 )); then
  die "usage: $0 [--dry-run]"
fi

jq -n --slurpfile policy "$OPENCLAW_MODELS_FILE" '
  ($policy[0]) as $policy
  | ($policy.models[] | select(.daily)) as $daily
  | ($policy.provider + "/" + $daily.id) as $dailyKey
  | {
      agents: {
        defaults: {
          model: {primary: $dailyKey, fallbacks: []},
          utilityModel: $dailyKey,
          thinkingDefault: $daily.reasoningEffort,
          models: (reduce $policy.models[] as $model ({};
            .[$policy.provider + "/" + $model.id] = (
              if $model.daily then {
                alias: $model.alias,
                params: {reasoningEffort: $model.reasoningEffort},
                agentRuntime: {id: "openclaw"},
                streaming: true
              } else null end
            )
          ))
        }
      }
    }
' | openclaw config patch "${patch_args[@]}"

if [[ "$dry_run" == true ]]; then
  exit 0
fi

openclaw config validate
"$ROOT_DIR/scripts/openclaw-gateway.sh" restart
echo "Only the validated daily model remains selectable."
