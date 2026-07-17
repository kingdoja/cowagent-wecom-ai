#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/dotenv.sh"

fixture="$(mktemp)"
invalid_fixture="$(mktemp)"
trap 'rm -f "$fixture" "$invalid_fixture"' EXIT

cat > "$fixture" <<'EOF'
# Values are data, never shell code.
PLAIN=https://relay.example.com/v1
SPACED='value with spaces # and hash'
DANGEROUS=$(printf should-not-run)
SEMICOLON=alpha; false
export QUOTED="double quoted value"
EOF

load_dotenv_file "$fixture"
[[ "$PLAIN" == "https://relay.example.com/v1" ]]
[[ "$SPACED" == "value with spaces # and hash" ]]
[[ "$DANGEROUS" == '$(printf should-not-run)' ]]
[[ "$SEMICOLON" == 'alpha; false' ]]
[[ "$QUOTED" == "double quoted value" ]]

printf '%s\n' 'not-an-assignment' > "$invalid_fixture"
if load_dotenv_file "$invalid_fixture" 2>/dev/null; then
  echo "invalid dotenv syntax was accepted" >&2
  exit 1
fi

echo "dotenv parser tests passed."
