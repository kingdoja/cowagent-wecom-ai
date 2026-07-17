import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import test from "node:test";
import { fileURLToPath } from "node:url";

const rootUrl = new URL("../../", import.meta.url);
const gateUrl = new URL("../openclaw-relay-gate.mjs", import.meta.url);
const manifestUrl = new URL("../../openclaw/models.json", import.meta.url);
const manifest = JSON.parse(await readFile(manifestUrl, "utf8"));
let failedModel = null;

const server = createServer(async (request, response) => {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  const payload = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  const shouldFail = payload.model === failedModel;

  if (payload.stream) {
    response.writeHead(200, { "content-type": "text/event-stream" });
    const content = shouldFail ? "wrong-stream" : "stream-ok";
    response.end(`data: ${JSON.stringify({ choices: [{ delta: { content } }] })}\n\ndata: [DONE]\n\n`);
    return;
  }

  response.setHeader("content-type", "application/json");
  if (payload.tools) {
    const value = shouldFail ? "wrong-tool" : "gate-ok";
    response.end(JSON.stringify({
      choices: [{
        message: {
          tool_calls: [{
            function: { name: "gate_echo", arguments: JSON.stringify({ value }) },
          }],
        },
      }],
    }));
    return;
  }

  response.end(JSON.stringify({
    choices: [{ message: { content: shouldFail ? "wrong-text" : "text-ok" } }],
  }));
});

await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const { port } = server.address();

function runGate() {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [fileURLToPath(gateUrl)], {
      cwd: fileURLToPath(rootUrl),
      env: {
        ...process.env,
        RELAY_API_BASE: `http://127.0.0.1:${port}/v1`,
        RELAY_API_KEY: "test-key",
        OPENCLAW_RELAY_SMOKE_MODE: "1",
      },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stderr = "";
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => resolve({ code, stderr }));
  });
}

try {
  await test("relay gate succeeds when every model passes", async () => {
    failedModel = null;
    const result = await runGate();
    assert.equal(result.code, 0, result.stderr);
  });

  for (const model of manifest.models) {
    await test(`${model.id} maps to exit ${model.failureExitCode}`, async () => {
      failedModel = model.id;
      const result = await runGate();
      assert.equal(result.code, model.failureExitCode, result.stderr);
    });
  }
} finally {
  await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
}
