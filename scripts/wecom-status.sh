#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

container_id="$(./scripts/compose.sh --env-file .env ps -q cowagent)"
if [[ -z "$container_id" ]]; then
  echo "CowAgent container is not running. Start it with: make up"
  exit 1
fi

running="$(docker inspect --format '{{.State.Running}}' "$container_id")"
if [[ "$running" != "true" ]]; then
  echo "CowAgent container exists but is not running. Start it with: make up"
  exit 1
fi

recent_logs="$(docker logs --since 24h "$container_id" 2>&1)"

if grep -qE '\[WecomBot\].*(Subscribe success|WebSocket connected|connected successfully)' \
  <<<"$recent_logs"; then
  echo "WeCom Bot is connected."
  exit 0
fi

if grep -qE '\[WecomBot\].*(required|failed|error|closed|disconnect)' \
  <<<"$recent_logs"; then
  echo "WeCom Bot was started but is not healthy. Check sanitized recent logs with:"
  echo "  docker logs --since 10m cowagent-wecom-gpt 2>&1 | grep '\[WecomBot\]'"
  exit 2
fi

echo "CowAgent is running, but no successful WeCom Bot subscription was detected."
echo "Open the Web console, choose Channels > WeCom Bot, and complete QR onboarding."
exit 2
