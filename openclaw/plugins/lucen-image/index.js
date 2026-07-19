import { createOpenAiCompatibleImageGenerationProvider } from "openclaw/plugin-sdk/image-generation";
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";

const PROVIDER_ID = "lucen-image";
const OPENAI_COMPAT_PROVIDER_ID = "openai";
const MODEL_ID = "gpt-image-2";
const DEFAULT_SIZE = "1024x1024";

function buildProvider() {
  return createOpenAiCompatibleImageGenerationProvider({
    id: PROVIDER_ID,
    label: "Lucen Image",
    defaultModel: MODEL_ID,
    models: [MODEL_ID],
    normalizeModel: () => MODEL_ID,
    defaultBaseUrl: "https://lucen.cc/v1",
    defaultTimeoutMs: 180_000,
    resolveCount: () => 1,
    capabilities: {
      generate: {
        maxCount: 1,
        supportsSize: true,
        supportsAspectRatio: false,
        supportsResolution: false,
      },
      edit: { enabled: false },
      geometry: {
        sizes: ["1024x1024", "1024x1536", "1536x1024"],
      },
    },
    buildGenerateRequest: ({ req, model, count }) => ({
      kind: "json",
      body: {
        model,
        prompt: req.prompt,
        n: count,
        size: req.size ?? DEFAULT_SIZE,
        output_format: req.outputFormat ?? "png",
        response_format: "b64_json",
        ...(req.quality ? { quality: req.quality } : {}),
      },
    }),
    buildEditRequest: () => {
      throw new Error("Lucen image editing is not enabled");
    },
    response: {
      defaultMimeType: "image/png",
      fileNamePrefix: "lucen-image",
      sniffMimeType: true,
    },
    missingApiKeyError: "Lucen image API key missing",
    failureLabels: {
      generate: "Lucen image generation failed",
      edit: "Lucen image editing failed",
    },
  });
}

function buildOpenAiCompatibilityProvider(lucenProvider) {
  return {
    ...lucenProvider,
    id: OPENAI_COMPAT_PROVIDER_ID,
    label: "Lucen Image (OpenAI compatibility)",
    models: ["gpt-image-1.5", MODEL_ID],
    async generateImage(req) {
      return lucenProvider.generateImage({ ...req, model: MODEL_ID });
    },
  };
}

export default definePluginEntry({
  id: "lucen-image",
  name: "Lucen Image",
  description: "OpenAI-compatible image generation through lucen.cc",
  register(api) {
    const lucenProvider = buildProvider();
    api.registerImageGenerationProvider(lucenProvider);
    api.registerImageGenerationProvider(
      buildOpenAiCompatibilityProvider(lucenProvider),
    );
  },
});
