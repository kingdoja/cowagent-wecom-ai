#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/dotenv.sh"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  echo "Missing .env; run 'make bootstrap' first." >&2
  exit 1
fi

load_dotenv_file .env

for name in RELAY_API_BASE RELAY_API_KEY RELAY_MODEL; do
  if [[ -z "${!name:-}" || "${!name}" == replace-* ]]; then
    echo "$name is not configured." >&2
    exit 1
  fi
done

base="${RELAY_API_BASE%/}"
mode="${RELAY_API_MODE:-chat_completions}"

if [[ "$mode" == "responses" ]]; then
  endpoint="$base/responses"
  payload="$(jq -n --arg model "$RELAY_MODEL" '{model:$model,input:"Reply with exactly: relay-ok",store:false}')"
else
  endpoint="$base/chat/completions"
  payload="$(jq -n --arg model "$RELAY_MODEL" '{model:$model,messages:[{role:"user",content:"Reply with exactly: relay-ok"}],stream:false}')"
fi

echo "Testing $mode at $endpoint with model $RELAY_MODEL ..."
response="$(curl --fail-with-body --silent --show-error \
  --connect-timeout 10 --max-time 120 \
  -H "Authorization: Bearer $RELAY_API_KEY" \
  -H "Content-Type: application/json" \
  --data "$payload" \
  "$endpoint")"

error_message="$(echo "$response" | jq -r '.error.message // empty')"
if [[ -n "$error_message" ]]; then
  echo "Relay returned an API error: $error_message" >&2
  exit 1
fi

if [[ "$mode" == "responses" ]]; then
  reply="$(echo "$response" | jq -r '.output_text // ([.output[]?.content[]? | select(.type == "output_text") | .text] | join("")) // empty')"
else
  reply="$(echo "$response" | jq -r '.choices[0].message.content // empty')"
fi

if [[ -z "$reply" ]]; then
  echo "Relay returned a successful response without text content." >&2
  exit 1
fi

echo "$reply"
