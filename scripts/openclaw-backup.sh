#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

backup_root="${HOME}/OpenClawBackups"
stamp="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_root"
chmod 700 "$backup_root"

tar -C "$HOME" -czf "$backup_root/openclaw-${stamp}.tar.gz" \
  .openclaw OpenClawWorkspace
chmod 600 "$backup_root/openclaw-${stamp}.tar.gz"

if [[ -d "$ROOT_DIR/data/cow" ]]; then
  tar -C "$ROOT_DIR" -czf "$backup_root/cowagent-${stamp}.tar.gz" \
    data docker-compose.yml .env
  chmod 600 "$backup_root/cowagent-${stamp}.tar.gz"
fi

find "$backup_root" -type f -name '*.tar.gz' -mtime +30 -delete
echo "Backups written to $backup_root; archives older than 30 days were removed."
