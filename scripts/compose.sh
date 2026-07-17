#!/usr/bin/env bash
set -euo pipefail

project_name="${COMPOSE_PROJECT_NAME:-cowagentgpt}"

if docker compose version >/dev/null 2>&1; then
  exec docker compose --project-name "$project_name" "$@"
fi

if command -v docker-compose >/dev/null 2>&1; then
  exec docker-compose --project-name "$project_name" "$@"
fi

echo "Docker Compose is unavailable." >&2
exit 1
