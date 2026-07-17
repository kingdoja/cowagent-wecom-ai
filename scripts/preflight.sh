#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/dotenv.sh"
cd "$ROOT_DIR"

errors=0

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  errors=$((errors + 1))
}

if [[ ! -f .env ]]; then
  fail ".env is missing; run 'make bootstrap' first"
else
  load_dotenv_file .env || fail ".env contains invalid dotenv syntax"

  [[ "${RELAY_API_BASE:-}" == https://* || "${RELAY_API_BASE:-}" == http://127.0.0.1* || "${RELAY_API_BASE:-}" == http://localhost* ]] \
    || fail "RELAY_API_BASE must use HTTPS unless it points to localhost"
  [[ -n "${RELAY_MODEL:-}" && "${RELAY_MODEL}" != replace-* ]] \
    || fail "RELAY_MODEL still contains a placeholder"
  [[ -n "${RELAY_API_KEY:-}" && "${RELAY_API_KEY}" != replace-* ]] \
    || fail "RELAY_API_KEY still contains a placeholder"
  [[ "${COWAGENT_IMAGE:-}" == *@sha256:* ]] \
    || fail "COWAGENT_IMAGE must be pinned to an immutable sha256 digest"

  case "${RELAY_API_MODE:-chat_completions}" in
    chat_completions|responses) ;;
    *) fail "RELAY_API_MODE must be chat_completions or responses" ;;
  esac

  if [[ "${COWAGENT_BIND_HOST:-127.0.0.1}" != "127.0.0.1" ]]; then
    web_password="${COWAGENT_WEB_PASSWORD:-}"
    [[ ${#web_password} -ge 16 && "$web_password" != replace-* ]] \
      || fail "a non-local web binding requires a non-placeholder password of at least 16 characters"
  fi
fi

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v docker >/dev/null 2>&1 || fail "Docker is not installed or not on PATH"
if command -v docker >/dev/null 2>&1; then
  if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    fail "Docker Compose is unavailable"
  fi
fi

if (( errors > 0 )); then
  printf '\nPreflight failed with %d issue(s).\n' "$errors" >&2
  exit 1
fi

echo "Preflight passed."
