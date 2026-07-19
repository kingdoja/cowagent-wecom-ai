#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

load_openclaw_env

node <<'NODE'
const baseUrl = process.env.IMAGE_API_BASE.replace(/\/$/, "");
const response = await fetch(`${baseUrl}/models`, {
  headers: { authorization: `Bearer ${process.env.IMAGE_API_KEY}` },
  signal: AbortSignal.timeout(30_000),
});
if (!response.ok) throw new Error(`image model catalog HTTP ${response.status}`);
const body = await response.json();
const ids = (body.data || []).map((entry) => String(entry.id || ""));
if (!ids.includes("gpt-image-2")) throw new Error("gpt-image-2 missing from image endpoint");
NODE

session_id="image-gate-$(date +%Y%m%d%H%M%S)-$$"
session_key="agent:main:explicit:${session_id}"
session_file="$OPENCLAW_HOME/agents/main/sessions/${session_id}.jsonl"

cleanup() {
  openclaw sandbox recreate --session "$session_key" --force >/dev/null 2>&1 || true
  scrub_openclaw_models_snapshot
}
trap cleanup EXIT

output="$(openclaw agent \
  --session-id "$session_id" \
  --model terra \
  --timeout 300 \
  --json \
  --message 'Call image_generate exactly once to generate one 1:1 PNG showing a single white geometric object on a blue studio background. No text, logo, or watermark. Do not use exec, write, SVG, or any other image method. Wait for the image generation completion event.')"

jq -e '.status == "ok"
  and .result.meta.toolSummary.calls == 1
  and .result.meta.toolSummary.tools == ["image_generate"]
  and .result.meta.toolSummary.failures == 0' \
  <<<"$output" >/dev/null || die "image_generate did not start cleanly"

completion=""
for _ in {1..120}; do
  completion="$(jq -r '
    select(.type == "message" and .message.role == "user")
    | select((.message.content // "") | type == "string")
    | select(.message.content | contains("source: image_generation"))
    | .message.content
    | if contains("status: completed successfully") then "success"
      elif contains("status: failed") then "failed"
      else empty
      end
  ' "$session_file" 2>/dev/null | tail -1)"
  [[ -n "$completion" ]] && break
  sleep 2
done

[[ "$completion" == success ]] || die "image generation completion status: ${completion:-timeout}"

media_path=""
for _ in {1..30}; do
  media_path="$(jq -r '
    select(.type == "message" and .message.role == "assistant")
    | .message.content[]?
    | select(.type == "text")
    | .text
    | capture("MEDIA:(?<path>[^\\r\\n]+)")
    | .path
  ' "$session_file" 2>/dev/null | tail -1)"
  [[ -n "$media_path" ]] && break
  sleep 1
done

[[ -n "$media_path" ]] \
  || die "image generation completed without returning media path"
[[ "$media_path" == "$OPENCLAW_HOME/media/tool-image-generation/"* ]] \
  || die "image generation returned an unexpected media path"
[[ -f "$media_path" ]] || die "generated image file is missing"

IMAGE_GATE_MEDIA_PATH="$media_path" node <<'NODE'
import { readFileSync } from "node:fs";

const image = readFileSync(process.env.IMAGE_GATE_MEDIA_PATH);
const isPng = image.length >= 24
  && image[0] === 0x89
  && image.toString("ascii", 1, 4) === "PNG";
if (!isPng) throw new Error("generated media is not PNG");
const width = image.readUInt32BE(16);
const height = image.readUInt32BE(20);
if (width < 256 || height < 256) throw new Error(`generated PNG is too small: ${width}x${height}`);
console.log(`Image generation gate passed: ${width}x${height} PNG.`);
NODE
