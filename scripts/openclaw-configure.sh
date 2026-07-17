#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

source_env="${1:-$ROOT_DIR/openclaw/.env}"

filevault_enabled \
  || die "FileVault must be enabled before OpenClaw credentials are stored"

if [[ ! -f "$source_env" ]]; then
  cp "$ROOT_DIR/openclaw/openclaw.env.example" "$ROOT_DIR/openclaw/.env"
  chmod 600 "$ROOT_DIR/openclaw/.env"
  die "created openclaw/.env; add a new OpenClaw-only relay sub-key and rerun"
fi

[[ "$(file_mode "$source_env")" == "600" ]] \
  || die "$source_env must have mode 600"

load_dotenv_file "$source_env" || die "failed to parse $source_env"

[[ "${RELAY_API_BASE:-}" == https://* \
  || "${RELAY_API_BASE:-}" == http://127.0.0.1* \
  || "${RELAY_API_BASE:-}" == http://localhost* ]] \
  || die "RELAY_API_BASE must use HTTPS unless it is loopback"
[[ -n "${RELAY_API_KEY:-}" && "$RELAY_API_KEY" != replace-* ]] \
  || die "RELAY_API_KEY must be a new dedicated OpenClaw sub-key"
[[ "$RELAY_API_BASE" != *$'\n'* && "$RELAY_API_BASE" != *$'\r'* ]] \
  || die "RELAY_API_BASE contains a newline"
[[ "$RELAY_API_KEY" != *$'\n'* && "$RELAY_API_KEY" != *$'\r'* ]] \
  || die "RELAY_API_KEY contains a newline"
[[ "$RELAY_API_BASE" != *"'"* && "$RELAY_API_KEY" != *"'"* ]] \
  || die "relay values cannot contain a single quote"

if [[ -f "$ROOT_DIR/.env" ]]; then
  cow_key="$(dotenv_value "$ROOT_DIR/.env" RELAY_API_KEY)"
  [[ -z "$cow_key" || "$RELAY_API_KEY" != "$cow_key" ]] \
    || die "OpenClaw must not reuse CowAgent's relay key"
fi

if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" || "$OPENCLAW_GATEWAY_TOKEN" == replace-* ]]; then
  OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 48)"
fi

[[ -x "$TAILSCALE_CLI" ]] || die "Tailscale.app CLI is missing"
tailscale_dns="$($TAILSCALE_CLI status --json | jq -r '.Self.DNSName // empty' | sed 's/\.$//')"
[[ -n "$tailscale_dns" ]] || die "Tailscale MagicDNS name is unavailable"
OPENCLAW_TAILSCALE_ORIGIN="https://${tailscale_dns}"

mkdir -p "$OPENCLAW_HOME" "$OPENCLAW_HOME/sandboxes" "$OPENCLAW_WORKSPACE"
chmod 700 "$OPENCLAW_HOME" "$OPENCLAW_HOME/sandboxes" "$OPENCLAW_WORKSPACE"

workspace_tools="$OPENCLAW_WORKSPACE/TOOLS.md"
workspace_tools_marker="## Sandbox path rules"
if [[ ! -f "$workspace_tools" ]]; then
  cat > "$workspace_tools" <<'EOF'
# TOOLS.md - Local Notes
EOF
fi
if ! grep -Fq "$workspace_tools_marker" "$workspace_tools"; then
  cat >> "$workspace_tools" <<'EOF'

## Sandbox path rules

- Shell commands run inside Docker. The host workspace `~/OpenClawWorkspace` is mounted at `/workspace`.
- In `exec`, use `/workspace` or workspace-relative paths. Never pass `/Users/...` host paths to sandbox commands.
- File tools are workspace-scoped; prefer workspace-relative paths such as `IDENTITY.md`.
- Before removing a bootstrap marker, check whether it still exists. OpenClaw may clear `BOOTSTRAP.md` automatically when setup completes.
- Keep a mutation and its verification in separate tool calls when a valid verification can return nonzero.
EOF
fi
chmod 600 "$workspace_tools"

umask 077
{
  printf "RELAY_API_BASE='%s'\n" "$RELAY_API_BASE"
  printf "RELAY_API_KEY='%s'\n" "$RELAY_API_KEY"
  printf "OPENCLAW_GATEWAY_TOKEN='%s'\n" "$OPENCLAW_GATEWAY_TOKEN"
  printf "OPENCLAW_TAILSCALE_ORIGIN='%s'\n" "$OPENCLAW_TAILSCALE_ORIGIN"
} > "$OPENCLAW_ENV"
chmod 600 "$OPENCLAW_ENV"

cp "$ROOT_DIR/openclaw/openclaw.example.json5" "$OPENCLAW_HOME/openclaw.json"
chmod 600 "$OPENCLAW_HOME/openclaw.json"

openclaw approvals set --file "$ROOT_DIR/openclaw/exec-approvals.deny.json"
chmod 600 "$OPENCLAW_HOME/exec-approvals.json"

openclaw config validate
printf 'Configured %s without logging into WeChat or starting the Gateway.\n' "$OPENCLAW_HOME"
