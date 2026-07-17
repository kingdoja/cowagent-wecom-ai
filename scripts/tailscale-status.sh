#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/dotenv.sh"
cd "$ROOT_DIR"

TAILSCALE_CLI="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
if [[ ! -x "$TAILSCALE_CLI" ]]; then
  echo "Tailscale.app is not installed." >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  echo "Missing .env." >&2
  exit 1
fi

load_dotenv_file .env

tailscale_ip="$($TAILSCALE_CLI ip -4)"
if [[ -z "$tailscale_ip" ]]; then
  echo "Tailscale is not connected." >&2
  exit 1
fi

port="${COWAGENT_WEB_PORT:-9899}"
echo "Tailscale IP: $tailscale_ip"
echo "CowAgent URL: http://${tailscale_ip}:${port}"

if [[ "${COWAGENT_BIND_HOST:-}" != "$tailscale_ip" ]]; then
  echo "WARNING: COWAGENT_BIND_HOST does not match the active Tailscale IP." >&2
  exit 1
fi

http_code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "http://${tailscale_ip}:${port}/" 2>/dev/null || true)"
case "$http_code" in
  200|302|303|401) echo "CowAgent check: HTTP $http_code" ;;
  *)
    echo "CowAgent check failed: HTTP ${http_code:-000}" >&2
    exit 1
    ;;
esac
