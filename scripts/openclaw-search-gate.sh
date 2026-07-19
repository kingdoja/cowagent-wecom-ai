#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

load_openclaw_env

prompts=(
  "搜索今天的一条中文科技新闻，给出至少两个可打开URL，并用web_fetch核验其中一个来源。"
  "Find the current stable Node.js release from at least two sources, include URLs, and verify one source with web_fetch."
  "查找2026年7月1日至2026年7月15日之间发布的OpenClaw官方更新，附至少两个URL并抓取核验正文。"
)

for i in "${!prompts[@]}"; do
  session_id="search-gate-$((i + 1))-$$"
  session_trace="$OPENCLAW_HOME/agents/main/sessions/${session_id}.trajectory.jsonl"
  output="$(run_openclaw_agent_with_cleanup "$session_id" \
    --model daily \
    --message "${prompts[$i]}" \
    --timeout 240 \
    --json)"
  reply="$(jq -r '[.result.payloads[]? | select(.isError != true and .isReasoning != true) | .text // empty] | join("\n")' <<<"$output")"
  urls="$(grep -Eo 'https?://[^[:space:]>)"]+' <<<"$reply" || true)"
  url_count="$(sort -u <<<"$urls" | sed '/^$/d' | wc -l | tr -d ' ')"
  [[ "$url_count" -ge 2 ]] || die "search case $((i + 1)) returned fewer than two URLs"

  [[ -f "$session_trace" ]] || die "search case $((i + 1)) did not produce a trajectory"
  successful_fetches="$(jq -s '[
    .[]
    | select(.type == "model.completed")
    | .data.messagesSnapshot[]?
    | select(.role == "toolResult" and .toolName == "web_fetch" and .isError != true)
    | [.content[]? | select(.type == "text") | .text // ""]
    | join("")
    | select(length > 0)
  ] | length' "$session_trace")"
  [[ "$successful_fetches" -ge 1 ]] \
    || die "search case $((i + 1)) did not complete a successful web_fetch"

  printf 'Search case %d passed with %d URL(s) and %d successful web_fetch result(s).\n' \
    "$((i + 1))" "$url_count" "$successful_fetches"
done
