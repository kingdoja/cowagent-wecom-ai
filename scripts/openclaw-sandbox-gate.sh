#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw-common.sh"

load_openclaw_env
explain="$(openclaw sandbox explain --json)"
docker_policy="$(openclaw config get agents.defaults.sandbox.docker --json)"

jq -e '.. | objects | select(.mode? == "all")' <<<"$explain" >/dev/null \
  || die "effective sandbox mode is not all"
jq -e '.network == "none"
  and .readOnlyRoot == true
  and .capDrop == ["ALL"]
  and .binds == []
  and .user == "1000:1000"' <<<"$docker_policy" >/dev/null \
  || die "Docker sandbox isolation policy drifted"

docker run --rm \
  --read-only \
  --network none \
  --user 1000:1000 \
  --cap-drop ALL \
  --tmpfs /tmp:rw,noexec,nosuid,size=32m,uid=1000,gid=1000 \
  --tmpfs /workspace:rw,noexec,nosuid,size=16m,uid=1000,gid=1000 \
  --workdir /workspace \
  --entrypoint /bin/sh \
  "$SANDBOX_IMAGE" \
  -c 'printf "%s" "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"32\"><rect width=\"32\" height=\"32\" fill=\"#1677ff\"/><text x=\"4\" y=\"23\" font-family=\"Noto Sans CJK SC\" font-size=\"18\">图</text></svg>" > input.svg && rsvg-convert input.svg --output output.png && python3 -c "from PIL import Image; image = Image.open(\"output.png\"); assert image.format == \"PNG\" and image.size == (32, 32)"' \
  || die "sandbox SVG-to-PNG rendering failed"

rm -f "$OPENCLAW_WORKSPACE/gate/sandbox-ok.txt"
session_id="sandbox-gate-$$"
output="$(run_openclaw_agent_with_cleanup "$session_id" \
  --model daily \
  --timeout 240 \
  --json \
  --message "Use exec to create gate/sandbox-ok.txt in the workspace. Then verify: (1) it can be read, (2) network access fails, (3) the host path ${HOME}/.ssh cannot be read, and (4) the Docker socket is absent. Reply with sandbox-gate-ok only if all four checks have the expected result.")"
reply="$(jq -r '[.result.payloads[]? | select(.isError != true and .isReasoning != true) | .text // empty] | join("\n")' <<<"$output")"

[[ -f "$OPENCLAW_WORKSPACE/gate/sandbox-ok.txt" ]] || die "sandbox did not write the workspace file"
[[ "$reply" == *"sandbox-gate-ok"* ]] || die "sandbox isolation checks failed"

echo "Sandbox gate passed."
