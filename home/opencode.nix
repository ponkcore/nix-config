# Home Manager module: declarative opencode configuration.
#
# - opencode binary from llm-agents flake
# - Plugin config (safe in nix store) via xdg.configFile
# - Provider config rendered at activation time, apiKey sourced from
#   /run/agenix/omniroute-key (decrypted by agenix from secrets/omniroute-key.age)
# - The nix-store template contains only a placeholder; the real key
#   appears ONLY in ~/.config/opencode/opencode.json (chmod 600, owner-only)
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
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
        context = 1040000;
        output = 100000;
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
        context = 262144;
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
        context = 128000;
        output = 8000;
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
  opencodeJsonTemplate = builtins.toFile "opencode-template.json" (builtins.toJSON {
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
    provider.omniroute = {
      npm = "@ai-sdk/openai-compatible";
      options = {
        baseURL = "https://omniroute.infinitycore.space:8443/v1";
        apiKey = "REPLACE_OMNIROUTE_KEY";
      };
      models = omnirouteModels;
    };
    # plugin: oh-my-openagent NOT loaded by default — use `omo` fish function
    # to launch opencode with the plugin (via OPENCODE_CONFIG_CONTENT env var).
    # This keeps vanilla opencode fast and plugin-free for simple tasks.
  });
in {
  # opencode binary from llm-agents flake
  home.packages = [
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode
  ];

  # opencode native config (.opencode.json — viper reads this).
  # Empty body — providers/models come from oh-my-openagent plugin via opencode.json.
  xdg.configFile."opencode/.opencode.json" = {
    source = builtins.toFile "opencode-native-config" (builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
    });
  };

  # oh-my-openagent plugin config (the plugin reads THIS file).
  # No secrets — safe to put in nix store via xdg.configFile.
  xdg.configFile."opencode/oh-my-openagent.json" = {
    source = builtins.toFile "oh-my-openagent-config" (builtins.toJSON {
      "$schema" = "https://raw.githubusercontent.com/code-yeongyu/oh-my-openagent/dev/assets/oh-my-opencode.schema.json";
      # All agents and categories temporarily routed to omniroute SSS-tier
      # combo router. omniroute picks the underlying model per request,
      # so per-agent variant/reasoningEffort knobs are dropped — the
      # router owns those decisions. Re-stratify per-agent later.
      agents = {
        sisyphus.model = "omniroute/SSS-tier";
        hephaestus.model = "omniroute/SSS-tier";
        atlas.model = "omniroute/SSS-tier";
        prometheus.model = "omniroute/SSS-tier";
        oracle.model = "omniroute/SSS-tier";
        metis.model = "omniroute/SSS-tier";
        momus.model = "omniroute/SSS-tier";
        explore.model = "omniroute/SSS-tier";
        librarian.model = "omniroute/SSS-tier";
        sisyphus-junior.model = "omniroute/SSS-tier";
        multimodal-looker.model = "omniroute/SSS-tier";
      };
      categories = {
        ultrabrain.model = "omniroute/SSS-tier";
        deep.model = "omniroute/SSS-tier";
        visual-engineering.model = "omniroute/SSS-tier";
        artistry.model = "omniroute/SSS-tier";
        quick.model = "omniroute/SSS-tier";
        unspecified-high.model = "omniroute/SSS-tier";
        unspecified-low.model = "omniroute/SSS-tier";
        writing.model = "omniroute/SSS-tier";
      };
      ralph_loop = {
        enabled = true;
        default_max_iterations = 10;
        default_strategy = "reset";
      };
      experimental = {
        dynamic_context_pruning = {
          enabled = false;
        };
      };
    });
  };

  # Render opencode.json with the real apiKey at activation time.
  # The key NEVER appears in /nix/store — only the template (with placeholder).
  #
  # Source of the key: /run/agenix/omniroute-key — decrypted at boot by
  # the agenix NixOS module from secrets/omniroute-key.age using this
  # host's SSH host key. Owner=oonishi, mode=400.
  #
  # The .age file contains:
  #   OMNIROUTE_API_KEY=sk-...
  #   FIREWORKS_API_KEY=...   (used by `opencode providers login` flow)
  #
  # If /run/agenix/omniroute-key is missing or unreadable, activation fails
  # loudly with the message below. To recover: re-encrypt the file with
  # `agenix -e secrets/omniroute-key.age` (see docs/handbook.md §Secrets).
  home.activation.opencode-config = lib.hm.dag.entryAfter ["writeBoundary"] ''
    set -eu
    SECRETS="/run/agenix/omniroute-key"
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
    mkdir -p "${config.xdg.configHome}/opencode"
    umask 077
    ${pkgs.jq}/bin/jq --arg key "$OMNIROUTE_API_KEY" \
      '.provider.omniroute.options.apiKey = $key' \
      ${opencodeJsonTemplate} \
      > "$OUT.tmp"
    chmod 600 "$OUT.tmp"
    mv -f "$OUT.tmp" "$OUT"
  '';
}
