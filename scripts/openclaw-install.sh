#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

require_command node
require_command npm
require_command docker

[[ "$(node --version)" == "v22.22.3" ]] \
  || die "Node v22.22.3 is required; found $(node --version)"

mkdir -p "$OPENCLAW_HOME" "$OPENCLAW_WORKSPACE" "$OPENCLAW_HOME/sandboxes"
chmod 700 "$OPENCLAW_HOME" "$OPENCLAW_WORKSPACE" "$OPENCLAW_HOME/sandboxes"

if [[ "$(openclaw --version 2>/dev/null | awk '{print $2}')" != "$OPENCLAW_VERSION" ]]; then
  npm install --global "openclaw@${OPENCLAW_VERSION}"
fi

openclaw plugins install --pin --force "@openclaw/parallel-plugin@${PARALLEL_VERSION}"
openclaw plugins install --pin --force "@tencent-weixin/openclaw-weixin@${WEIXIN_VERSION}"

build_ok=false
for attempt in 1 2 3; do
  if docker build \
    --pull \
    --tag "$SANDBOX_IMAGE" \
    "$ROOT_DIR/openclaw/sandbox"; then
    build_ok=true
    break
  fi
  printf 'Sandbox build attempt %d failed; retrying.\n' "$attempt" >&2
done
[[ "$build_ok" == true ]] || die "sandbox image build failed after three attempts"

printf 'Installed OpenClaw %s, Parallel %s, Weixin %s.\n' \
  "$OPENCLAW_VERSION" "$PARALLEL_VERSION" "$WEIXIN_VERSION"
printf 'Built sandbox image %s.\n' "$SANDBOX_IMAGE"
