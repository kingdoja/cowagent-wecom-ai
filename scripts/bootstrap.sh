#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  echo ".env already exists; leaving it unchanged."
else
  cp .env.example .env
  chmod 600 .env
  echo "Created .env with mode 600. Replace the placeholder values before starting."
fi

mkdir -p data/cow

