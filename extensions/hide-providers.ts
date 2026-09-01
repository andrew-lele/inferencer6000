import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Built-in providers to hide from the model picker. Registering a provider
// with an empty model list replaces its built-in catalog (models: [] wins).
const HIDDEN_PROVIDERS = ["anthropic"];

export default function (pi: ExtensionAPI) {
  for (const id of HIDDEN_PROVIDERS) {
    pi.registerProvider(id, { models: [] });
  }
}
