import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readdirSync, existsSync, statSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

// Unsloth Desktop exposes an OpenAI-compatible API at /v1 (default port 8888).
const BASE_URL = process.env.UNSLOTH_BASE_URL ?? "http://localhost:8888/v1";

// Unsloth tracks installed models in per-model manifest files under its
// studio home, not directly in the Hugging Face cache.
function studioHome(): string {
  return process.env.UNSLOTH_STUDIO_HOME ?? join(homedir(), ".unsloth", "studio");
}

function discoverFromManifests(): Map<string, { id: string }> {
  const models = new Map<string, { id: string }>();
  const dir = join(studioHome(), "cache", "hub-state", "manifests");
  if (!existsSync(dir)) return models;

  for (const sub of readdirSync(dir)) {
    const subDir = join(dir, sub);
    if (!statSync(subDir).isDirectory()) continue;
    for (const file of readdirSync(subDir)) {
      if (!file.startsWith("models--") || !file.endsWith(".json")) continue;
      try {
        const data = JSON.parse(readFileSync(join(subDir, file), "utf8"));
        if (typeof data?.repo_id === "string") models.set(data.repo_id, { id: data.repo_id });
      } catch {
        // Skip malformed manifest.
      }
    }
  }
  return models;
}

export default function (pi: ExtensionAPI) {
  const models = discoverFromManifests();

  pi.registerProvider("unsloth", {
    name: "Unsloth (local)",
    baseUrl: BASE_URL,
    apiKey: "$UNSLOTH_API_KEY",
    api: "openai-completions",
    models: [...models.values()].map(({ id }) => ({
      id,
      name: id,
      reasoning: true,
      input: ["text"],
      contextWindow: 128000,
      maxTokens: 32768,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      compat: {
        supportsDeveloperRole: false,
        supportsReasoningEffort: false,
      },
    })),
  });
}
