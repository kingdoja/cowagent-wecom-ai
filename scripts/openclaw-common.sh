#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/dotenv.sh"

OPENCLAW_VERSION="2026.7.1"
PARALLEL_VERSION="2026.7.1"
WEIXIN_VERSION="2.4.6"
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
