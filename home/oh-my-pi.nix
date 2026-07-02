# oh-my-pi — standalone coding agent.
# Binary packaged from a pinned upstream release asset. Declarative config:
#   - models.yml : omniroute provider + 5 tier models (env-var apiKey)
#   - config.yml : model roles and settings
#   - mcp.json   : omniroute (sse) + context7 (http), no lazyweb
#   - .env       : API keys from /run/agenix/tokens (activation script)
{
  pkgs,
  lib,
  ...
}: {
  home.packages = [
    pkgs.oh-my-pi
    pkgs.repomix
    pkgs.github-mcp-server
  ];

  # --- Provider + model catalogue ---------------------------------------
  # omp reads env-var names first for apiKey, then literal tokens.
  # The actual key values are injected via ~/.omp/agent/.env (see activation
  # script below) sourced from /run/agenix/tokens.
  home.file.".omp/agent/models.yml".text = ''
    providers:
      omniroute:
        baseUrl: https://omniroute.infinitycore.space:8443/v1
        apiKey: OMNIROUTE_API_KEY
        api: openai-completions
        auth: apiKey
        authHeader: true
        models:
          - id: SSS-tier
            name: SSS — Premium Flagship
            reasoning: true
            input: [text, image]
            contextWindow: 1000000
            maxTokens: 64000
          - id: SS-tier
            name: SS — GPT Reasoning
            reasoning: true
            input: [text, image]
            contextWindow: 200000
            maxTokens: 32000
          - id: S-tier
            name: S — Mid Flagship
            reasoning: true
            input: [text]
            contextWindow: 200000
            maxTokens: 32000
          - id: A-tier
            name: A — Mixed (Opus + GPT + Kimi)
            reasoning: true
            input: [text, image]
            contextWindow: 200000
            maxTokens: 32000
          - id: B-tier
            name: B — Nano Fallback
            reasoning: false
            input: [text]
            contextWindow: 200000
            maxTokens: 32000
  '';

  # --- Model roles + settings -------------------------------------------
  home.file.".omp/agent/config.yml".text = ''
    modelRoles:
      default: omniroute/SSS-tier
      smol: omniroute/B-tier
      slow: omniroute/SSS-tier:high
      plan: omniroute/SSS-tier:high

    modelProviderOrder:
      - omniroute
  '';

  # --- MCP servers ------------------------------------------------------
  # omp-native mcp.json takes priority over auto-discovered opencode.json.
  # omniroute goes through the VPS proxy (https://.../omp/sse) which filters
  # to only web_search + web_fetch and holds the real OmniRoute MCP key.
  # context7 is a direct HTTP connection with our API key.
  # ${VAR} is expanded by omp at discovery time from env / .env.
  home.file.".omp/agent/mcp.json".text = builtins.toJSON {
    "$schema" = "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json";
    mcpServers = {
      omniroute = {
        type = "http";
        url = "https://mcp.infinitycore.space:8443/omp/sse";
        headers = {
          "X-Proxy-Key" = "\${OMP_PROXY_KEY}";
        };
      };
      context7 = {
        type = "http";
        url = "https://mcp.context7.com/mcp";
        headers = {
          "X-Context7-API-Key" = "\${CONTEXT7_API_KEY}";
        };
      };
      repomix = {
        type = "stdio";
        command = "${pkgs.repomix}/bin/repomix";
        args = ["--mcp"];
      };
      github = {
        type = "stdio";
        command = "${pkgs.github-mcp-server}/bin/github-mcp-server";
        args = ["stdio" "--toolsets=default,code_security,secret_protection"];
        env = {
          GITHUB_PERSONAL_ACCESS_TOKEN = "\${GITHUB_TOKEN}";
        };
      };
    };
    disabledServers = [];
  };

  # --- Secret injection from agenix -------------------------------------
  # /run/agenix/tokens is a shell-sourceable VAR=value file decrypted at boot.
  # omp reads .env files: process env → $PWD/.env → ~/.omp/agent/.env → ...
  # The .env file contains secrets — must NOT be in /nix/store.
  #
  # Keys used by omp:
  #   OMNIROUTE_API_KEY  — provider apiKey (models.yml)
  #   OMP_PROXY_KEY      — VPS MCP proxy auth (mcp.json X-Proxy-Key)
  #   CONTEXT7_API_KEY   — context7 MCP (mcp.json X-Context7-API-Key)
  home.activation.omp-env = lib.hm.dag.entryAfter ["writeBoundary"] ''
    set -eu
    SECRETS="/run/agenix/tokens"
    OUT="$HOME/.omp/agent/.env"
    if [ ! -r "$SECRETS" ]; then
      echo "ERROR: $SECRETS missing or unreadable." >&2
      exit 1
    fi
    # shellcheck disable=SC1090
    . "$SECRETS"
    if [ -z "''${OMNIROUTE_API_KEY:-}" ]; then
      echo "ERROR: OMNIROUTE_API_KEY missing in $SECRETS" >&2
      exit 1
    fi
    if [ -z "''${OMP_PROXY_KEY:-}" ]; then
      echo "ERROR: OMP_PROXY_KEY missing in $SECRETS" >&2
      echo "       Add it via: keys → agenix -e tokens.age → OMP_PROXY_KEY=..." >&2
      exit 1
    fi
    if [ -z "''${CONTEXT7_API_KEY:-}" ]; then
      echo "ERROR: CONTEXT7_API_KEY missing in $SECRETS" >&2
      exit 1
    fi
    mkdir -p "$HOME/.omp/agent"
    umask 077
    GH_TOKEN="$(${pkgs.gh}/bin/gh auth token 2>/dev/null || true)"
    if [ -z "$GH_TOKEN" ]; then
      echo "ERROR: gh auth token returned empty — run 'gh auth login' first." >&2
      exit 1
    fi
    cat > "$OUT" <<EOF
    OMNIROUTE_API_KEY=$OMNIROUTE_API_KEY
    OMP_PROXY_KEY=$OMP_PROXY_KEY
    CONTEXT7_API_KEY=$CONTEXT7_API_KEY
    GITHUB_TOKEN=$GH_TOKEN
    EOF
  '';
}
