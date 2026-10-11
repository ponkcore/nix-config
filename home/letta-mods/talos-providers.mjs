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

// letta validates static `models` ids: "id must be unprefixed and cannot
// contain '/'" (validateModel, still true in v0.34.10). But `listModels`
// results bypass that validator (listRegisteredPiProviderModels does NOT
// re-validate), so slashed upstream ids are served through `listModels`
// instead. pi-ai sends model.id on the wire verbatim, and letta's handle
// parsing is first-slash based (handle.split("/").slice(1).join("/")), so
// handle "omniroute/zai/glm-5.3" resolves to model id "zai/glm-5.3" and
// omniroute gets the prefixed id it needs to route. Combo tiers keep
// slash-free ids and stay in the static list as well.
function toLettaModel(key, m) {
  const id = m.remoteId || key;
  return {
    id,
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
    // ALL models of this provider, with remoteId as the id (slashed for
    // direct routes, key otherwise).
    const all = Object.entries(catalog.models || {})
      .filter(([, m]) => m.provider === provName)
      .map(([key, m]) => toLettaModel(key, m));

    if (all.length === 0) continue;

    // Static list carries only slash-free ids (validator constraint);
    // listModels returns the full set (tiers + slashed direct routes) and
    // overrides statics by id at merge time, so callers that only consult
    // listModels still see everything.
    const staticModels = all.filter((m) => !m.id.includes("/"));

    letta.providers.register(provName, {
      name: provName,
      description: `${provName} — shared catalogue (${CATALOG})`,
      baseUrl: prov.baseUrl,
      apiKey: prov.apiKeyEnv,
      authHeader: prov.authHeader !== false,
      api: prov.api || "openai-completions",
      connect: false,
      models: staticModels,
      listModels: () => all,
    });
  }
};
