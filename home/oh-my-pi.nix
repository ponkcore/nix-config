# oh-my-pi — standalone coding agent.
# Nix owns the package, provider catalogue, MCP wiring, and secret injection.
# OMP owns writable config.yml state, seeded once with model-role defaults.
{
  pkgs,
  lib,
  ...
}: let
  ompConfigSeed = (pkgs.formats.yaml {}).generate "omp-config.yml" {
    modelRoles = {
      default = "omniroute/SSS-tier";
      smol = "omniroute/B-tier";
      slow = "omniroute/SSS-tier:high";
      plan = "omniroute/SSS-tier:high";
    };
    modelProviderOrder = ["omniroute"];
  };

  # mcp.json template — stored in /nix/store with PLACEHOLDER values.
  # The activation script below substitutes real keys from
  # /run/agenix/tokens via jq, writing the result to
  # ~/.omp/agent/mcp.json (chmod 600).
  # Secrets NEVER appear in /nix/store.
  ompMcpTemplate = pkgs.writeText "omp-mcp-template.json" (builtins.toJSON {
    "$schema" = "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json";
    mcpServers = {
      omniroute = {
        type = "http";
        url = "https://mcp.infinitycore.space/omp/sse";
        headers = {
          "X-API-Key" = "PLACEHOLDER_HEXSTRIKE_API_KEY";
          "X-Proxy-Key" = "PLACEHOLDER_OMP_PROXY_KEY";
        };
      };
      context7 = {
        type = "http";
        url = "https://mcp.context7.com/mcp";
        headers = {
          "X-Context7-API-Key" = "PLACEHOLDER_CONTEXT7_API_KEY";
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
          GITHUB_PERSONAL_ACCESS_TOKEN = "PLACEHOLDER_GITHUB_TOKEN";
        };
      };
      semgrep = {
        type = "stdio";
        command = "${pkgs.semgrep}/bin/semgrep";
        args = ["mcp"];
      };
      # HexStrike AI — remote pentest MCP on the VPS (FALK).
      # Caddy terminates TLS on :443, routes /hex/sse → :8890 (MCP SSE
      # bridge), /hex/messages/* → :8890, /hex/* → :8888 (Flask API).
      # DISABLED by default: 150+ offensive security tools. Enable
      # manually via: omp → /mcp → enable hexstrike
      hexstrike = {
        type = "http";
        url = "https://mcp.infinitycore.space/hex/mcp";
        headers = {
          "X-API-Key" = "PLACEHOLDER_HEXSTRIKE_API_KEY";
        };
      };
    };
    disabledServers = ["hexstrike"];
  });
in {
  home.packages = [
    pkgs.oh-my-pi
    pkgs.repomix
    pkgs.github-mcp-server
    pkgs.semgrep
  ];

  # --- Provider + model catalogue ---------------------------------------
  # models.yml is NOT a Home Manager symlink. It is generated fresh at every
  # `omp` launch by the fish wrapper (see home/fish.nix) from the shared
  # catalogue /etc/nixos/home/agent-models.json. Editing the catalogue needs
  # NO rebuild — the next `omp` launch re-renders models.yml. To add/remove a
  # model, edit home/agent-models.json.
  # The actual key values are injected via ~/.omp/agent/.env (see activation
  # script below) sourced from /run/agenix/tokens.

  # --- Model roles + settings -------------------------------------------
  # config.yml must remain writable: /settings and /models persist preferences
  # there. Home Manager seeds defaults only when the file does not exist; after
  # that OMP is the sole owner and rebuilds preserve its changes.
  home.activation.omp-config = lib.hm.dag.entryAfter ["linkGeneration"] ''
    config="$HOME/.omp/agent/config.yml"
    $DRY_RUN_CMD mkdir -p "$HOME/.omp/agent"
    if [ ! -e "$config" ]; then
      $DRY_RUN_CMD install -m 0644 ${ompConfigSeed} "$config"
    fi
  '';

  # --- MCP servers ------------------------------------------------------
  # omp-native mcp.json takes priority over auto-discovered opencode.json.
  # Unlike the old approach (home.file symlink with ${VAR} placeholders),
  # the template lives in /nix/store with PLACEHOLDER_* strings and is
  # rendered at activation time with real keys from /run/agenix/tokens.
  # This is necessary because omp does NOT expand ${VAR} from .env in
  # http headers — it only works with stdio env blocks AND requires the
  # var to be in the process environment. The activation script writes
  # the final mcp.json with real key values (chmod 600, owner-only).
  #
  # GITHUB_TOKEN is NOT substituted here — it is injected at runtime by
  # the `omp` fish wrapper from `gh auth token` (env var expansion).
  home.activation.omp-mcp = lib.hm.dag.entryAfter ["writeBoundary"] ''
    set -eu
    SECRETS="/run/agenix/tokens"
    OUT="$HOME/.omp/agent/mcp.json"
    if [ ! -r "$SECRETS" ]; then
      echo "ERROR: $SECRETS missing or unreadable." >&2
      exit 1
    fi
    . "$SECRETS"
    if [ -z "''${OMP_PROXY_KEY:-}" ]; then
      echo "ERROR: OMP_PROXY_KEY missing in $SECRETS" >&2
      exit 1
    fi
    if [ -z "''${CONTEXT7_API_KEY:-}" ]; then
      echo "ERROR: CONTEXT7_API_KEY missing in $SECRETS" >&2
      exit 1
    fi
    if [ -z "''${HEXSTRIKE_API_KEY:-}" ]; then
      echo "ERROR: HEXSTRIKE_API_KEY missing in $SECRETS" >&2
      exit 1
    fi
    if [ -z "''${GITHUB_TOKEN:-}" ]; then
      GITHUB_TOKEN="PLACEHOLDER_GITHUB_TOKEN"
    fi
    mkdir -p "$HOME/.omp/agent"
    umask 077
    ${pkgs.jq}/bin/jq \
      --arg proxy   "$OMP_PROXY_KEY" \
      --arg c7      "$CONTEXT7_API_KEY" \
      --arg hex     "$HEXSTRIKE_API_KEY" \
      --arg gh      "$GITHUB_TOKEN" \
      '.mcpServers.omniroute.headers["X-API-Key"] = $hex
       | .mcpServers.omniroute.headers["X-Proxy-Key"] = $proxy
       | .mcpServers.context7.headers["X-Context7-API-Key"] = $c7
       | .mcpServers.hexstrike.headers["X-API-Key"] = $hex
       | .mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN = $gh' \
      ${ompMcpTemplate} \
      > "$OUT.tmp"
    chmod 600 "$OUT.tmp"
    mv -f "$OUT.tmp" "$OUT"
  '';

  # --- Secret injection from agenix -------------------------------------
  # /run/agenix/tokens is a shell-sourceable VAR=value file decrypted at boot.
  # omp reads .env files: process env → $PWD/.env → ~/.omp/agent/.env → ...
  # The .env file contains secrets — must NOT be in /nix/store.
  #
  # Keys used by omp:
  #   OMNIROUTE_API_KEY  — provider apiKey (models.yml)
  #   OMP_PROXY_KEY      — VPS MCP proxy auth (mcp.json X-Proxy-Key)
  #   CONTEXT7_API_KEY   — context7 MCP (mcp.json X-Context7-API-Key)
  #   HEXSTRIKE_API_KEY  — hexstrike MCP (mcp.json X-API-Key)
  # GITHUB_TOKEN is NOT written here — it is injected at runtime by
  # the `omp` fish wrapper from `gh auth token` (env var expansion).
  home.activation.omp-env = lib.hm.dag.entryAfter ["writeBoundary"] ''
    set -eu
    SECRETS="/run/agenix/tokens"
    OUT="$HOME/.omp/agent/.env"
    if [ ! -r "$SECRETS" ]; then
      echo "ERROR: $SECRETS missing or unreadable." >&2
      exit 1
    fi
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
    if [ -z "''${HEXSTRIKE_API_KEY:-}" ]; then
      echo "ERROR: HEXSTRIKE_API_KEY missing in $SECRETS" >&2
      exit 1
    fi
    mkdir -p "$HOME/.omp/agent"
    umask 077
    cat > "$OUT" <<EOF
    OMNIROUTE_API_KEY=$OMNIROUTE_API_KEY
    OMP_PROXY_KEY=$OMP_PROXY_KEY
    CONTEXT7_API_KEY=$CONTEXT7_API_KEY
    HEXSTRIKE_API_KEY=$HEXSTRIKE_API_KEY
    EOF
  '';
}
