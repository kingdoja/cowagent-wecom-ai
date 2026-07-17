import { readFileSync } from "node:fs";

const baseUrl = (process.env.RELAY_API_BASE || "").replace(/\/$/, "");
const apiKey = process.env.RELAY_API_KEY || "";

if (!baseUrl || !apiKey) {
  console.error("RELAY_API_BASE and RELAY_API_KEY are required");
  process.exit(2);
}

const manifestUrl = process.env.OPENCLAW_MODELS_FILE
  ? new URL(`file://${process.env.OPENCLAW_MODELS_FILE}`)
  : new URL("../openclaw/models.json", import.meta.url);
const manifest = JSON.parse(readFileSync(manifestUrl, "utf8"));
const allModels = manifest.models;
const fallbackMode = process.env.OPENCLAW_RELAY_FALLBACK_MODE === "1";
const smokeMode = process.env.OPENCLAW_RELAY_SMOKE_MODE === "1";
const dailyModel = allModels.find((model) => model.daily);
if (!dailyModel || !Number.isInteger(dailyModel.failureExitCode)) {
  throw new Error("model manifest must define one daily model with a failureExitCode");
}
const models = fallbackMode ? [dailyModel] : allModels;

async function request(payload) {
  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(180_000),
  });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }
  return response;
}

async function testText(model) {
  const response = await request({
    model: model.id,
    reasoning_effort: model.reasoningEffort,
    messages: [{ role: "user", content: "Reply with exactly: text-ok" }],
    stream: false,
  });
  const body = await response.json();
  const text = body?.choices?.[0]?.message?.content?.trim() || "";
  return { ok: text.includes("text-ok") };
}

async function testStream(model) {
  const started = performance.now();
  const response = await request({
    model: model.id,
    reasoning_effort: model.reasoningEffort,
    messages: [{ role: "user", content: "Reply with exactly: stream-ok" }],
    stream: true,
  });
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let text = "";
  let firstVisibleMs = null;

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
      if (typeof delta === "string" && delta.length > 0) {
        if (firstVisibleMs === null) firstVisibleMs = Math.round(performance.now() - started);
        text += delta;
      }
    }
  }
  return {
    ok: text.includes("stream-ok") && firstVisibleMs !== null,
    firstVisibleMs,
  };
}

async function testStreamSamples(model) {
  const sampleCount = !smokeMode && model.id === dailyModel.id ? 20 : 1;
  const samples = [];
  for (let index = 0; index < sampleCount; index += 1) {
    samples.push(await testStream(model));
  }
  const timings = samples
    .map((sample) => sample.firstVisibleMs)
    .filter((value) => Number.isFinite(value))
    .sort((left, right) => left - right);
  const p95Index = Math.max(0, Math.ceil(timings.length * 0.95) - 1);
  const p95FirstVisibleMs = timings[p95Index] ?? null;
  return {
    ok: samples.every((sample) => sample.ok)
      && p95FirstVisibleMs !== null
      && p95FirstVisibleMs <= model.maxFirstVisibleMs,
    samples: sampleCount,
    p95FirstVisibleMs,
    maxFirstVisibleMs: timings.at(-1) ?? null,
  };
}

async function testTool(model) {
  const response = await request({
    model: model.id,
    reasoning_effort: model.reasoningEffort,
    messages: [{ role: "user", content: "Call gate_echo with value gate-ok." }],
    tools: [{
      type: "function",
      function: {
        name: "gate_echo",
        description: "Record the model compatibility probe.",
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
  const call = response?.body ? (await response.json())?.choices?.[0]?.message?.tool_calls?.[0] : null;
  let args = {};
  try {
    args = JSON.parse(call?.function?.arguments || "{}");
  } catch {
    args = {};
  }
  return { ok: call?.function?.name === "gate_echo" && args.value === "gate-ok" };
}

const results = {};
for (const model of models) {
  const modelResult = { text: { ok: false }, stream: { ok: false }, tool: { ok: false } };
  for (const [name, test] of [["text", testText], ["stream", testStreamSamples], ["tool", testTool]]) {
    try {
      modelResult[name] = await test(model);
    } catch (error) {
      modelResult[name] = { ok: false, error: error instanceof Error ? error.message : String(error) };
    }
  }
  modelResult.ok = modelResult.text.ok && modelResult.stream.ok && modelResult.tool.ok;
  results[model.id] = modelResult;
}

console.log(JSON.stringify({ testedAt: new Date().toISOString(), results }, null, 2));

for (const model of models) {
  if (!results[model.id]?.ok) process.exit(model.failureExitCode);
}
