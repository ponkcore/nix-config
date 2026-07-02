# Home Manager module: declarative opencode configuration.
#
# - opencode binary from llm-agents flake
# - Plugin config (safe in nix store) via xdg.configFile
# - Provider config + lazyweb MCP Bearer rendered at activation time,
#   secrets sourced from /run/agenix/tokens (decrypted by agenix from
#   secrets/tokens.age — bundles OMNIROUTE_API_KEY, FIREWORKS_API_KEY,
#   LAZYWEB_MCP_TOKEN).
# - The nix-store template contains only placeholders; the real keys
#   appear ONLY in ~/.config/opencode/opencode.json (chmod 600, owner-only)
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  # Nix-store oh-my-openagent plugin root. `omo` injects this file:// spec
  # into OPENCODE_CONFIG_CONTENT, so OpenCode treats it as a local plugin and
  # skips runtime Npm.add()/Bun install.
  ohMyOpenagentPlugin = "file://${pkgs.oh-my-openagent}/lib/node_modules/oh-my-openagent";

  # omo-codegraph — NixOS-compatible launcher for the codegraph MCP
  # that oh-my-openagent provisions in ~/.omo/codegraph/.
  #
  # omo downloads a standalone Node binary for generic Linux that NixOS
  # cannot run (dynamically linked, no ld-linux). This wrapper uses the
  # NixOS Node from nix-store instead. The OMO_CODEGRAPH_BIN env var
  # (set below) tells omo to use this wrapper as the codegraph command,
  # bypassing the broken provisioned binary entirely.
  #
  # --liftoff-only avoids V8 turboshaft WASM Zone OOM (codegraph #293).
  omoCodegraph = pkgs.writeShellScriptBin "omo-codegraph" ''
    exec ${pkgs.nodejs_22}/bin/node --liftoff-only \
      "$HOME/.omo/codegraph/lib/dist/bin/codegraph.js" "$@"
  '';

  # Shared Fireworks model catalogue.
  # IDs use direct Fireworks format: accounts/fireworks/models/<name>.
  # omniroute proxy prepends "fireworks/" routing prefix via fireworksModels.
  fireworksBase = {
    glm-5p1 = {
      id = "accounts/fireworks/models/glm-5p1";
      name = "GLM 5.1";
      limit = {
        context = 202752;
        output = 8192;
      };
    };
    kimi-k2p6 = {
      id = "accounts/fireworks/models/kimi-k2p6";
      name = "Kimi K2.6";
      limit = {
        context = 262144;
        output = 16384;
      };
    };
    minimax-m2p7 = {
      id = "accounts/fireworks/models/minimax-m2p7";
      name = "MiniMax M2.7";
      limit = {
        context = 196608;
        output = 8192;
      };
    };
    deepseek-v4-pro = {
      id = "accounts/fireworks/models/deepseek-v4-pro";
      name = "DeepSeek V4 Pro";
      limit = {
        context = 1048576;
        output = 163840;
      };
    };
    qwen-3p6-plus = {
      id = "accounts/fireworks/models/qwen3p6-plus";
      name = "Qwen 3.6 Plus";
      limit = {
        context = 262144;
        output = 8192;
      };
    };
  };

  # Fireworks models: omniroute requires "fireworks/" routing prefix.
  fireworksModels = builtins.mapAttrs (_: m: m // {id = "fireworks/${m.id}";}) fireworksBase;

  # Claude (Anthropic via Kiro proxy) models. IDs already include the "kr/"
  # routing prefix and are passed through unchanged. Only `kr/*` variants
  # are listed: the API also exposes `kiro/*` IDs, but they are aliases
  # (parent: kr/*) and would just create duplicates in the model picker.
  #
  # Capability flags (verified live against
  # GET https://omniroute.infinitycore.space:8443/v1/models on 2026-05-19;
  # context/output figures from kiro.dev official table, 2026-05-24):
  #
  #   model       | vision | tool | reason | thinking | context | output |
  #   ----------- ------- ------ -------- ---------- --------- -------
  #   opus-4.7    |   ✓    |  ✓   |   ✓    |    ✓     |    1M   |  128K  |
  #   opus-4.6    |   ✓    |  ✓   |   ✓    |    —     |    1M   |  128K  |
  #   sonnet-4.6  |   ✓    |  ✓   |   ✓    |    —     |    1M   |   64K  |
  #   sonnet-4.5  |   ✓    |  ✓   |   ✓    |    —     |   200K  |   64K  |
  #   haiku-4.5   |   ✓    |  ✓   |   ✓    |    —     |   200K  |   64K  |
  #
  # Why these values: OmniRoute's providerRegistry exposes a
  # defaultContextLength of 200000 which @omniroute/opencode-provider
  # propagates verbatim into opencode's per-model `limit.context` —
  # but Kiro (the upstream proxy) accepts 1M for Opus and Sonnet 4.6/4.7
  # via per-model overrides. Without raising the value here, opencode
  # triggers compaction at ~87K (about 87% of 100K, opencode's prune
  # threshold) instead of the expected 870K, and the user loses the
  # entire benefit of the wider window.
  #
  # Output limits matter for compaction-induced regenerations: setting
  # 8192 here forced the proxy to stream long replies in chunks even
  # when Kiro itself supports 64K-128K. Aligning to the table above
  # eliminates one source of fragmentation.
  #
  # opencode's per-model boolean flags map to: attachment (vision),
  # tool_call, reasoning, temperature. Extended thinking is a runtime
  # knob (reasoningEffort = "high"/"max" at the agent level) and only
  # actually fires on opus-4.7; setting it on the others is harmless
  # (the Kiro proxy ignores it).
  claudeDefaults = {
    attachment = true; # vision/image input
    tool_call = true; # native function calling
    reasoning = true; # extended-reasoning capable
    temperature = true; # honours `temperature` parameter
  };
  claudeModels = {
    "claude-opus-4.7" =
      claudeDefaults
      // {
        id = "kr/claude-opus-4.7";
        name = "Claude Opus 4.7";
        limit = {
          context = 1000000;
          output = 128000;
        };
      };
    "claude-opus-4.6" =
      claudeDefaults
      // {
        id = "kr/claude-opus-4.6";
        name = "Claude Opus 4.6";
        limit = {
          context = 1000000;
          output = 128000;
        };
      };
    "claude-sonnet-4.6" =
      claudeDefaults
      // {
        id = "kr/claude-sonnet-4.6";
        name = "Claude Sonnet 4.6";
        limit = {
          context = 1000000;
          output = 64000;
        };
      };
    "claude-sonnet-4.5" =
      claudeDefaults
      // {
        id = "kr/claude-sonnet-4.5";
        name = "Claude Sonnet 4.5";
        limit = {
          context = 200000;
          output = 64000;
        };
      };
    "claude-haiku-4.5" =
      claudeDefaults
      // {
        id = "kr/claude-haiku-4.5";
        name = "Claude Haiku 4.5";
        limit = {
          context = 200000;
          output = 64000;
        };
      };
  };

  # Combo router models — omniroute picks the underlying model per
  # request (owned_by = "combo" in /v1/models). Per-tier capability
  # flags + window come from the operator-supplied tier table; no
  # shared defaults because each tier has its own quirks (SS lacks
  # temperature, B drops reasoning + attachment).
  comboModels = {
    "SSS-tier" = {
      id = "SSS-tier";
      name = "SSS — Premium Flagship";
      limit = {
        context = 1000000;
        output = 64000;
      };
      reasoning = true;
      attachment = true;
      temperature = true;
      tool_call = true;
    };
    "SS-tier" = {
      id = "SS-tier";
      name = "SS — GPT Reasoning";
      limit = {
        context = 200000;
        output = 32000;
      };
      reasoning = true;
      attachment = true;
      temperature = false;
      tool_call = true;
    };
    "S-tier" = {
      id = "S-tier";
      name = "S — Mid Flagship";
      limit = {
        context = 200000;
        output = 32000;
      };
      reasoning = true;
      attachment = false;
      temperature = true;
      tool_call = true;
    };
    "A-tier" = {
      id = "A-tier";
      name = "A — Mixed (Opus + GPT + Kimi)";
      limit = {
        context = 200000;
        output = 32000;
      };
      reasoning = true;
      attachment = true;
      temperature = true;
      tool_call = true;
    };
    "B-tier" = {
      id = "B-tier";
      name = "B — Nano Fallback";
      limit = {
        context = 200000;
        output = 32000;
      };
      reasoning = false;
      attachment = false;
      temperature = true;
      tool_call = true;
    };
  };

  # Final omniroute model catalogue — Fireworks + Claude + combo merged.
  # NOTE: this file is regenerated at every Home Manager activation.
  # Any models added manually to ~/.config/opencode/opencode.json will be
  # overwritten on the next rebuild. To add a model permanently, edit
  # this file and rebuild.
  omnirouteModels = fireworksModels // claudeModels // comboModels;

  # JSON template stored in /nix/store. Contains placeholders, NOT real keys.
  # The activation script below substitutes apiKeys at runtime using jq.
  # pkgs.writeText (not builtins.toFile) because the template references
  # nix store paths (omoCodegraph, nodejs_22, oh-my-openagent) —
  # builtins.toFile cannot embed derivation references.
  opencodeJsonTemplate = pkgs.writeText "opencode-template.json" (builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    autoupdate = false; # NixOS: updates only via flake lock + rebuild
    # Compaction tuning — wider context windows above only help if
    # opencode actually uses them before triggering automatic
    # compaction. The default thresholds were calibrated for ~200K
    # context; raising the per-model limits to 1M without these
    # overrides leaves opencode prunning at ~87K (the default
    # ~87% × 100K trigger). `reserved: 32000` also keeps a safety
    # margin against Kiro's ~615KB payload hard-limit during the
    # compaction request itself — without it, compaction can fail
    # with "[400] Improperly formed request".
    compaction = {
      auto = true;
      prune = true;
      reserved = 32000;
    };
    # OmniRoute MCP tool filter. The VPS proxy already filters to only
    # web_search + web_fetch, so the massive per-tool denylist is no
    # longer needed. Keep built-in webfetch off (prefer MCP version).
    tools = {
      webfetch = false;
      omniroute_web_fetch = true;
      omniroute_web_search = true;
    };
    provider.omniroute = {
      npm = "@ai-sdk/openai-compatible";
      options = {
        baseURL = "https://omniroute.infinitycore.space:8443/v1";
        apiKey = "REPLACE_OMNIROUTE_KEY";
      };
      models = omnirouteModels;
    };
    # MCP servers — opencode-native remote transport. Tokens are
    # placeholders in the nix-store template; the activation script
    # below substitutes them from /run/agenix/tokens.
    mcp = {
      # Context7 — Upstash hosted documentation lookup
      # (https://context7.com). Pulls up-to-date library/framework
      # docs into the LLM context. Free anonymous tier works without
      # auth but rate-limits aggressively; supplying CONTEXT7_API_KEY
      # via the X-Context7-API-Key header lifts those caps.
      context7 = {
        type = "remote";
        url = "https://mcp.context7.com/mcp";
        enabled = true;
        headers = {
          X-Context7-API-Key = "REPLACE_CONTEXT7_KEY";
        };
      };
      # OmniRoute MCP — VPS proxy that filters to only web_search +
      # web_fetch. The proxy holds the real OmniRoute MCP key; omp/omo
      # only need the proxy auth key.
      omniroute = {
        type = "remote";
        url = "https://mcp.infinitycore.space:8443/omp/sse";
        enabled = true;
        headers = {
          X-Proxy-Key = "REPLACE_OMP_PROXY_KEY";
        };
      };
      # LSP — Language Server Protocol bridge from oh-my-openagent.
      # Provides diagnostics, goto_definition, find_references,
      # rename, symbols via real language servers (tsserver, pyright,
      # rust-analyzer, etc.). Runs the lsp-daemon CLI from the
      # oh-my-openagent nix-store path with NixOS Node.
      # When omo is loaded, this entry overrides omo's built-in lsp
      # (userMcp spreads last in the MCP merge) — same binary, same
      # result. When omo is NOT loaded, plain opencode uses this
      # entry directly.
      lsp = {
        type = "local";
        command = [
          "${pkgs.nodejs_22}/bin/node"
          "${pkgs.oh-my-openagent}/lib/node_modules/oh-my-openagent/packages/lsp-daemon/dist/cli.js"
          "mcp"
        ];
        enabled = true;
        environment = {
          LSP_TOOLS_MCP_PROJECT_CONFIG = ".opencode/lsp.json:.omo/lsp.json:.omo/lsp-client.json";
        };
      };
      # Codegraph — semantic code graph from oh-my-openagent.
      # Provides codegraph_search, codegraph_callers, codegraph_callees,
      # codegraph_impact, codegraph_explore via tree-sitter AST.
      # Uses our omo-codegraph wrapper (NixOS Node) instead of the
      # broken provisioned standalone binary.
      codegraph = {
        type = "local";
        command = [
          "${omoCodegraph}/bin/omo-codegraph"
          "serve"
          "--mcp"
        ];
        enabled = true;
        environment = {
          CODEGRAPH_INSTALL_DIR = "${config.home.homeDirectory}/.omo/codegraph";
          CODEGRAPH_NO_DOWNLOAD = "1";
          CODEGRAPH_TELEMETRY = "0";
          DO_NOT_TRACK = "1";
        };
      };
      # Repomix — packs an entire repository into a single AI-readable
      # file. Complements codegraph (symbol-level) with whole-repo
      # context for planning large refactors. MCP mode: `repomix --mcp`.
      repomix = {
        type = "local";
        command = ["${pkgs.repomix}/bin/repomix" "--mcp"];
        enabled = true;
      };
      # GitHub MCP — official GitHub MCP server. 86 tools across 22
      # toolsets. We enable a focused set (not "all") to avoid prompt
      # pollution: repos, pull_requests, issues, code_security,
      # secret_protection. GITHUB_PERSONAL_ACCESS_TOKEN is read from
      # environment — gh CLI is already auth'd, but the MCP server
      # needs the token explicitly. The activation script below
      # injects it from /run/agenix/tokens.
      github = {
        type = "local";
        command = [
          "${pkgs.github-mcp-server}/bin/github-mcp-server"
          "stdio"
          "--toolsets=default,code_security,secret_protection"
        ];
        enabled = true;
        environment = {
          GITHUB_PERSONAL_ACCESS_TOKEN = "REPLACE_GITHUB_TOKEN";
        };
      };
    };
    # plugin: oh-my-openagent NOT loaded by default — use `omo` fish function
    # to launch opencode with the Nix-store file:// plugin spec via
    # OPENCODE_CONFIG_CONTENT. This keeps vanilla opencode fast and
    # plugin-free for simple tasks.
  });
in {
  # opencode binary from llm-agents flake
  home.packages = [
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode
    omoCodegraph
    pkgs.repomix
    pkgs.github-mcp-server
  ];

  # Tell omo to use our NixOS-compatible wrapper instead of the broken
  # provisioned binary in ~/.omo/codegraph/bin/codegraph.
  home.sessionVariables.OMO_CODEGRAPH_BIN = "${omoCodegraph}/bin/omo-codegraph";

  # opencode declarative state — Home Manager symlinks into
  # ~/.config/opencode/ from /nix/store. Three families:
  #   - .opencode.json    : viper bootstrap (just the $schema)
  #   - oh-my-openagent.json : agent/category model routing
  #   - skill/<name>/SKILL.md : lazyweb MCP playbooks
  # No secrets in any of these (Bearer token is patched into
  # opencode.json at activation, see home.activation.opencode-config).

  xdg.configFile =
    {
      "opencode/.opencode.json".source = builtins.toFile "opencode-native-config" (builtins.toJSON {
        "$schema" = "https://opencode.ai/config.json";
      });

      "opencode/oh-my-openagent.plugin".text = ohMyOpenagentPlugin;

      "opencode/oh-my-openagent.json".source = builtins.toFile "oh-my-openagent-config" (builtins.toJSON {
        "$schema" = "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json";
        # Per-agent and per-category routing onto omniroute combo tiers.
        # Tier table (operator-supplied) lives in comboModels above. The
        # combo router picks the underlying model per request, so no
        # per-agent variant/reasoningEffort knobs.
        agents = {
          # Top tier — flagship reasoning + vision (when underlying allows).
          sisyphus.model = "omniroute/SSS-tier";
          prometheus.model = "omniroute/SSS-tier";
          multimodal-looker.model = "omniroute/SSS-tier";

          # Second tier — heavy reasoning, GPT-flavoured.
          hephaestus.model = "omniroute/SS-tier";
          oracle.model = "omniroute/SS-tier";
          momus.model = "omniroute/SS-tier";

          # Mid flagship — fast, no attachments.
          metis.model = "omniroute/S-tier";

          # Mixed pool — Opus + GPT + Kimi rotation.
          atlas.model = "omniroute/A-tier";
          sisyphus-junior.model = "omniroute/A-tier";
          librarian.model = "omniroute/A-tier";
          explore.model = "omniroute/A-tier";

          # Override agents (opencode built-ins overridden by oh-my-openagent).
          build.model = "omniroute/SSS-tier";
          OpenCode-Builder.model = "omniroute/SSS-tier";
          plan.model = "omniroute/SS-tier";
        };
        categories = {
          # Visual + creative + writing + unspecified-high → flagship.
          visual-engineering.model = "omniroute/SSS-tier";
          artistry.model = "omniroute/SSS-tier";
          unspecified-high.model = "omniroute/SSS-tier";
          writing.model = "omniroute/SSS-tier";

          # Deep reasoning workloads → SS (GPT reasoning).
          ultrabrain.model = "omniroute/SS-tier";
          deep.model = "omniroute/SS-tier";

          # Routine ↓ tier.
          unspecified-low.model = "omniroute/A-tier";
          quick.model = "omniroute/B-tier";
        };
        ralph_loop = {
          enabled = true;
          default_max_iterations = 10;
          default_strategy = "reset";
        };
        # Disable omo built-in MCP servers that duplicate our own:
        #   websearch — duplicates omniroute web_search
        #   grep_app  — not needed
        # context7 is NOT disabled: the remote context7 from
        # opencode.json overrides omo's built-in context7 in the MCP
        # merge (userMcp spreads last), so there is no duplication.
        # Disabling it via disabled_mcps kills BOTH (delete merged[name]).
        disabled_mcps = ["websearch" "grep_app"];
        experimental = {
          dynamic_context_pruning = {
            enabled = false;
          };
        };
      });
    }
    // builtins.listToAttrs (map (skill: {
        name = "opencode/skill/${skill}/SKILL.md";
        value = {source = ./opencode-skills/${skill}/SKILL.md;};
      }) [
        "lazyweb-add-inspo-source"
        "lazyweb-design-brainstorm"
        "lazyweb-design-improve"
        "lazyweb-design-research"
        "lazyweb-quick-references"
        "lazyweb-remove-inspo-source"
      ]);

  # Render opencode.json with real secrets at activation time. Tokens
  # NEVER appear in /nix/store — only the template (with placeholders).
  #
  # Source of secrets: /run/agenix/tokens — decrypted at boot by the
  # agenix NixOS module from secrets/tokens.age using this host's SSH
  # host key. Owner = oonishi, mode 400.
  #
  # The .age file bundles:
  #   OMNIROUTE_API_KEY  — opencode omniroute provider apiKey
  #   FIREWORKS_API_KEY  — `opencode providers login` flow
  #   CONTEXT7_API_KEY   — X-Context7-API-Key header for context7 MCP
  #   OMP_PROXY_KEY      — X-Proxy-Key header for VPS MCP proxy
  #
  # GITHUB_PERSONAL_ACCESS_TOKEN is NOT in tokens.age — it is sourced
  # from `gh auth token` at activation time (gh CLI is already auth'd).
  #
  # If /run/agenix/tokens is missing or unreadable, activation fails
  # loudly with the message below. To recover: re-encrypt the file
  # with `agenix -e secrets/tokens.age` (see docs/handbook.md §Secrets).
  home.activation.opencode-config = lib.hm.dag.entryAfter ["writeBoundary"] ''
    set -eu
    SECRETS="/run/agenix/tokens"
    OUT="${config.xdg.configHome}/opencode/opencode.json"
    if [ ! -r "$SECRETS" ]; then
      echo "ERROR: $SECRETS missing or unreadable." >&2
      echo "       Check 'systemctl status agenix' and that the host's" >&2
      echo "       SSH host key is listed in secrets/secrets.nix." >&2
      exit 1
    fi
    # shellcheck disable=SC1090
    . "$SECRETS"
    if [ -z "''${OMNIROUTE_API_KEY:-}" ]; then
      echo "ERROR: OMNIROUTE_API_KEY missing in $SECRETS" >&2
      exit 1
    fi
    if [ -z "''${CONTEXT7_API_KEY:-}" ]; then
      echo "ERROR: CONTEXT7_API_KEY missing in $SECRETS" >&2
      exit 1
    fi
    if [ -z "''${OMP_PROXY_KEY:-}" ]; then
      echo "ERROR: OMP_PROXY_KEY missing in $SECRETS" >&2
      exit 1
    fi
    # GitHub token from gh CLI (already auth'd, no need to store in agenix)
    GH_TOKEN="$(${pkgs.gh}/bin/gh auth token 2>/dev/null || true)"
    if [ -z "$GH_TOKEN" ]; then
      echo "ERROR: gh auth token returned empty — run 'gh auth login' first." >&2
      exit 1
    fi
    mkdir -p "${config.xdg.configHome}/opencode"
    umask 077
    ${pkgs.jq}/bin/jq \
      --arg key "$OMNIROUTE_API_KEY" \
      --arg c7  "$CONTEXT7_API_KEY" \
      --arg proxy "$OMP_PROXY_KEY" \
      --arg ghtoken "$GH_TOKEN" \
      '.provider.omniroute.options.apiKey = $key
       | .mcp.context7.headers["X-Context7-API-Key"] = $c7
       | .mcp.omniroute.headers["X-Proxy-Key"] = $proxy
       | .mcp.github.environment.GITHUB_PERSONAL_ACCESS_TOKEN = $ghtoken' \
      ${opencodeJsonTemplate} \
      > "$OUT.tmp"
    chmod 600 "$OUT.tmp"
    mv -f "$OUT.tmp" "$OUT"
  '';

  # Remove stale npm-plugin cache entries now that `omo` loads the plugin from
  # /nix/store via a file:// spec. Keep unrelated OpenCode cache intact.
  home.activation.opencode-openagent-cache-cleanup = lib.hm.dag.entryAfter ["writeBoundary"] ''
    rm -rf \
      "${config.home.homeDirectory}/.cache/opencode/packages/oh-my-openagent@"* \
      "${config.home.homeDirectory}/.cache/opencode/packages/oh-my-opencode@"* \
      "${config.home.homeDirectory}/.cache/opencode/oh-my-openagent@"* \
      "${config.home.homeDirectory}/.cache/opencode/oh-my-opencode@"* \
      2>/dev/null || true
  '';
}
