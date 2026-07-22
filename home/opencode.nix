# Home Manager module: declarative opencode configuration.
#
# - opencode binary from llm-agents flake
# - Plugin config (safe in nix store) via xdg.configFile
# - Provider config + lazyweb MCP Bearer rendered at activation time,
#   secrets sourced from /run/agenix/tokens (decrypted by agenix from
#   secrets/tokens.age — bundles OMNIROUTE_API_KEY, LAZYWEB_MCP_TOKEN).
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

  # Models and providers are NOT declared here. They live in the shared
  # catalogue /etc/nixos/home/agent-models.json and are merged into the
  # opencode config at launch time by the `opencode`/`omo` fish wrappers
  # (see home/fish.nix) via OPENCODE_CONFIG_CONTENT. Editing the catalogue
  # needs NO rebuild — the next agent launch picks it up.
  #
  # This on-disk opencode.json keeps only MCP servers, compaction tuning,
  # and the secret apiKey placeholders (substituted by the activation
  # script below). To add/remove a model, edit home/agent-models.json.

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
    # NOTE: no `provider` block here. Providers + models are merged in at
    # launch time by the fish wrappers from home/agent-models.json.
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
      # Semgrep — SAST (Static Application Security Testing). Scans
      # code for security vulnerabilities by structural AST rules:
      # SQL injection, XSS, hardcoded secrets, insecure deserialization,
      # taint flows. Runs as `semgrep mcp` (stdio). LGPL-2.1 (fine for
      # personal use — no distribution). In nixpkgs as semgrep 1.161.0.
      semgrep = {
        type = "local";
        command = ["${pkgs.semgrep}/bin/semgrep" "mcp"];
        enabled = true;
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
    pkgs.semgrep
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
        # The tier table (context/output/flags) lives in the shared catalogue
        # home/agent-models.json — edit it there. The combo router picks the
        # underlying model per request, so no per-agent variant/reasoningEffort
        # knobs.
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
  #   CONTEXT7_API_KEY   — X-Context7-API-Key header for context7 MCP
  #   OMP_PROXY_KEY      — X-Proxy-Key header for VPS MCP proxy
  #
  # GITHUB_PERSONAL_ACCESS_TOKEN is NOT in tokens.age — it is injected
  # at runtime by the `omo`/`opencode` fish wrappers from `gh auth token`.
  # The on-disk opencode.json keeps a placeholder; the wrappers substitute
  # the real token via jq + OPENCODE_CONFIG_CONTENT at launch time.
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
    if [ -z "''${CONTEXT7_API_KEY:-}" ]; then
      echo "ERROR: CONTEXT7_API_KEY missing in $SECRETS" >&2
      exit 1
    fi
    if [ -z "''${OMP_PROXY_KEY:-}" ]; then
      echo "ERROR: OMP_PROXY_KEY missing in $SECRETS" >&2
      exit 1
    fi
    mkdir -p "${config.xdg.configHome}/opencode"
    umask 077
    # Provider apiKey is NOT substituted here — providers+models are
    # merged at launch time from home/agent-models.json by the fish
    # wrappers, which source the key themselves.
    ${pkgs.jq}/bin/jq \
      --arg c7  "$CONTEXT7_API_KEY" \
      --arg proxy "$OMP_PROXY_KEY" \
      '.mcp.context7.headers["X-Context7-API-Key"] = $c7
       | .mcp.omniroute.headers["X-Proxy-Key"] = $proxy' \
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
