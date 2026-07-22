// talos-providers.mjs — Letta Code mod that registers custom LLM providers
// and models from the shared catalogue /etc/nixos/home/agent-models.json.
//
// The catalogue is the single source of truth for opencode/omo, omp, and
// letta. Edit it and restart letta — NO nixos-rebuild needed. NO secrets
// here: each provider names an env var (apiKeyEnv) that holds the key at
// runtime (sourced from /run/agenix/tokens by the `talos` fish wrapper).
//
// Deployed declaratively via home/letta.nix (home.file -> ~/.letta/mods/).
import { readFileSync } from "node:fs";

const CATALOG = process.env.AGENT_MODELS_PATH || "/etc/nixos/home/agent-models.json";

function loadCatalog() {
  try {
    return JSON.parse(readFileSync(CATALOG, "utf8"));
  } catch (err) {
    console.error(`[talos-providers] cannot read catalogue ${CATALOG}: ${err.message}`);
    return null;
  }
}

// letta rejects model ids containing "/" — the catalogue keys are already
// slash-free, and remoteId carries the real upstream id. Combo tiers have
// remoteId == key (no slash), so this is a safe identity for them.
function toLettaModel(key, m) {
  return {
    id: key,
    name: m.name || key,
    reasoning: !!m.reasoning,
    input: Array.isArray(m.input) ? m.input : ["text"],
    contextWindow: m.contextWindow,
    maxTokens: m.maxTokens,
    cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
  };
}

export default (letta) => {
  const catalog = loadCatalog();
  if (!catalog || !catalog.providers) return;

  for (const [provName, prov] of Object.entries(catalog.providers)) {
    // Models that belong to this provider, keyed by their catalogue key.
    const models = Object.entries(catalog.models || {})
      .filter(([, m]) => m.provider === provName)
      .map(([key, m]) => toLettaModel(key, m));

    if (models.length === 0) continue;

    letta.providers.register(provName, {
      name: provName,
      description: `${provName} — shared catalogue (${CATALOG})`,
      baseUrl: prov.baseUrl,
      apiKey: prov.apiKeyEnv,
      authHeader: prov.authHeader !== false,
      api: prov.api || "openai-completions",
      connect: false,
      models,
    });
  }
};
