#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/dotenv.sh"
cd "$ROOT_DIR"

./scripts/preflight.sh
./scripts/compose.sh --env-file .env up -d

load_dotenv_file .env

host="${COWAGENT_BIND_HOST:-127.0.0.1}"
[[ "$host" == "0.0.0.0" ]] && host="127.0.0.1"
echo "CowAgent started: http://${host}:${COWAGENT_WEB_PORT:-9899}"
