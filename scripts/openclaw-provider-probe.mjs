const baseUrl = (process.env.OPENCLAW_PROBE_BASE_URL || "").replace(/\/$/, "");
const apiKey = process.env.OPENCLAW_PROBE_API_KEY || "";
const model = process.env.OPENCLAW_PROBE_MODEL || "";

if (!baseUrl || !apiKey || !model) {
  console.error("OPENCLAW_PROBE_BASE_URL, OPENCLAW_PROBE_API_KEY, and OPENCLAW_PROBE_MODEL are required");
  process.exit(2);
}

async function request(payload) {
  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ model, ...payload }),
    signal: AbortSignal.timeout(60_000),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response;
}

async function textProbe() {
  const response = await request({
    messages: [{ role: "user", content: "Reply with exactly: probe-ok" }],
    stream: false,
    max_tokens: 32,
  });
  const body = await response.json();
  return (body?.choices?.[0]?.message?.content || "").includes("probe-ok");
}

async function streamProbe() {
  const response = await request({
    messages: [{ role: "user", content: "Reply with exactly: stream-ok" }],
    stream: true,
    max_tokens: 32,
  });
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let text = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() || "";
    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line.startsWith("data:") || line === "data: [DONE]") continue;
      const event = JSON.parse(line.slice(5).trim());
      const delta = event?.choices?.[0]?.delta?.content;
      if (typeof delta === "string") text += delta;
    }
  }
  return text.includes("stream-ok");
}

async function toolProbe() {
  const response = await request({
    messages: [{ role: "user", content: "Call probe_echo with value tool-ok." }],
    tools: [{
      type: "function",
      function: {
        name: "probe_echo",
        description: "Verify tool-call compatibility.",
        parameters: {
          type: "object",
          properties: { value: { type: "string" } },
          required: ["value"],
          additionalProperties: false,
        },
      },
    }],
    tool_choice: "required",
    stream: false,
  });
  const body = await response.json();
  const call = body?.choices?.[0]?.message?.tool_calls?.[0];
  let args = {};
  try {
    args = JSON.parse(call?.function?.arguments || "{}");
  } catch {
    return false;
  }
  return call?.function?.name === "probe_echo" && args.value === "tool-ok";
}

const result = { model, text: false, confirmation: false, stream: false, tool: false };
try {
  result.text = await textProbe();
  result.confirmation = await textProbe();
  result.stream = await streamProbe();
  result.tool = await toolProbe();
} catch (error) {
  result.error = error instanceof Error ? error.message : String(error);
}
result.ok = result.text && result.confirmation && result.stream && result.tool;
console.log(JSON.stringify(result));
if (!result.ok) process.exit(1);
