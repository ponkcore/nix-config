# home/talos.nix — talos sysadmin agent (gptme runtime + brain workdir).
#
# Three responsibilities:
#   1. Install pkgs.gptme into the user environment.
#   2. Render ~/.config/gptme/config.toml at activation, substituting
#      OMNIROUTE_API_KEY and OMNIROUTE_BASE_URL from /run/agenix/tokens.
#      Same pattern as home/opencode.nix (the secret never lands in
#      /nix/store; only the template with placeholders does).
#   3. Provide a fish function `talos` that opens gptme in the brain
#      workdir (~/Documents/talos-brain) by default, with a few short
#      subcommands for common workflows.
#
# Brain workdir is checked at run time, not at activation time. The
# directory belongs to a separate repo (ponkcore/talos-brain) and
# lives outside this flake on purpose: nix-config carries the
# system declaration; the brain carries the agent's persistent
# memory (lessons, runbooks, ADRs, journal). Different change
# rhythms, different review surfaces.
{
  config,
  lib,
  pkgs,
  ...
}: let
  brainDir = "${config.home.homeDirectory}/Documents/talos-brain";

  # MCP server runners. Both go through `uvx` for now:
  #   - mcp-server-fetch: not in nixpkgs at all; uvx pulls from PyPI.
  #   - mcp-nixos: ships a flake but its build chain depends on the
  #     nixpkgs `python3Packages.fastmcp` derivation, which is
  #     currently broken on nixos-25.11 — fastmcp 3.2.4 is missing
  #     `platformdirs` in propagatedBuildInputs and fails the import
  #     check phase. Running `uvx mcp-nixos` sidesteps the broken
  #     derivation entirely (uv resolves real PyPI deps).
  # When upstream nixpkgs fixes fastmcp, we can switch mcp-nixos back
  # to the native flake binary (input is already wired in flake.nix).
  uvx-bin = "${pkgs.uv}/bin/uvx";

  # mcp-nix requires Python ≥3.13 and gptme's runtime is Python
  # 3.12, so we have to give uvx an explicit interpreter. uv would
  # otherwise auto-download a generic-linux CPython 3.13 from
  # python-build-standalone, which fails on NixOS (the binary is
  # dynamically linked against /lib64/ld-linux* that NixOS does not
  # provide). Pinning uvx at the Nix-built python313 sidesteps both
  # the version mismatch and the loader incompatibility. Path
  # interpolated via Nix so the closure tracks python313 and the
  # pin survives channel updates.
  python313-bin = "${pkgs.python313}/bin/python3.13";

  # TOML template living in /nix/store — apiKey / baseUrl are
  # placeholders, replaced at activation time using values read from
  # /run/agenix/tokens. The `.toml` literal itself is safe to commit
  # because it contains no secret material.
  configTemplate = pkgs.writeText "gptme-config.toml.template" ''
    # gptme config — rendered by home/talos.nix activation script.
    # Edit the source module, not this file (HM rewrites it on rebuild).

    [env]
    # Default model for talos sessions: GLM-5.1 directly from
    # Fireworks. See PROVIDERS.md in the brain for the full
    # catalogue. Override at run time with
    # `gptme --model <provider>/<id>` or with the `MODEL` env var.
    MODEL = "fireworks/accounts/fireworks/models/glm-5p1"

    # Direct Fireworks endpoint — fast path, no omniroute hop.
    # FIREWORKS_API_KEY is sourced from tokens.age (which bundles
    # OMNIROUTE_API_KEY, FIREWORKS_API_KEY, and LAZYWEB_MCP_TOKEN).
    #
    # Catalogue (Fireworks model cards / /v1/models, 2026-05-22):
    #   fireworks/accounts/fireworks/models/glm-5p1         (default; ctx 202k)
    #   fireworks/accounts/fireworks/models/deepseek-v4-pro (ctx 1M)
    #   fireworks/accounts/fireworks/models/kimi-k2p6       (ctx 262k, vision)
    #   fireworks/accounts/fireworks/models/qwen3p6-plus    (ctx 256k)
    #   fireworks/accounts/fireworks/models/minimax-m2p7    (ctx 200k)
    #
    # /v1/models only lists models enabled on serverless tier for the
    # current key; on-demand / build-tier models are reachable via
    # chat/completions even when absent from /v1/models. Do NOT trust
    # /v1/models as a complete catalogue.
    # Per-model metadata is carried inline via the `models` table,
    # consumed by the local custom-provider-model-metadata patch in
    # pkgs/gptme/patches/. Keys are model ids relative to the
    # provider (everything after `<provider>/`). Without these
    # entries gptme assumes context = 128k and supports_vision =
    # false for any model under a custom provider. Plain TOML
    # `[providers.<name>.models."<id>"]` headers cannot follow a
    # `[[providers]]` array element — they would create a top-level
    # `providers.<name>` key that ProviderConfig.__init__ rejects.
    [[providers]]
    name = "fireworks"
    base_url = "https://api.fireworks.ai/inference/v1"
    api_key = "@FIREWORKS_API_KEY@"
    default_model = "accounts/fireworks/models/glm-5p1"
    # Numbers come from the live Fireworks /v1/models endpoint
    # (context_length, supports_image_input). reasoning support is
    # marked true for all chat models in our roster — Fireworks tools
    # routing handles it whether we set it or not, but vision support
    # actually matters because it gates `view_image`.
    models = { "accounts/fireworks/models/glm-5p1" = { context = 202_752, supports_vision = false, supports_reasoning = true }, "accounts/fireworks/models/deepseek-v4-pro" = { context = 1_048_576, supports_vision = false, supports_reasoning = true }, "accounts/fireworks/models/kimi-k2p6" = { context = 262_144, supports_vision = true, supports_reasoning = true }, "accounts/fireworks/models/qwen3p6-plus" = { context = 256_000, supports_vision = false, supports_reasoning = true }, "accounts/fireworks/models/minimax-m2p7" = { context = 200_000, supports_vision = false, supports_reasoning = true } }

    # Omniroute proxy — Kiro Claude family only.
    # See PROVIDERS.md for the catalogue (opus-4.7/4.6,
    # sonnet-4.6/4.5, haiku-4.5).
    [[providers]]
    name = "omniroute"
    base_url = "@OMNIROUTE_BASE_URL@"
    api_key = "@OMNIROUTE_API_KEY@"
    default_model = "kr/claude-opus-4.7"
    # NOTE: supports_vision = false on every Kiro Claude model even
    # though the upstream models accept images. The omniroute proxy is
    # fronted by Angie with `client_max_body_size 1m`, and gptme's
    # `view_image` always sends base64-in-body — a typical 2880x1800
    # PNG screenshot exceeds the cap and trips HTTP 413 mid-session.
    # Marking the models as no-vision tells gptme to short-circuit
    # `view_image` with a clean "Model does not support vision"
    # warning instead. See decisions/0008-no-vision-on-omniroute.md
    # in talos-brain. Flip back to true once Angie is loosened or
    # gptme grows an image-URL flow.
    # Combo router models (owned_by = "combo" in /v1/models). Omniroute
    # picks the underlying model per request; per-tier limits mirror
    # home/opencode.nix comboModels (operator-supplied tier table).
    # Hermes/Talos combos intentionally omitted — not exposed to gptme.
    # supports_vision is forced false on every combo for the same Angie
    # 1 MiB cap reason as kr/claude-* — see decisions/0008-no-vision-
    # on-omniroute.md. Flip when Angie loosens.
    models = { "kr/claude-opus-4.7" = { context = 1_000_000, max_output = 128_000, supports_vision = false, supports_reasoning = true }, "kr/claude-opus-4.6" = { context = 1_000_000, max_output = 128_000, supports_vision = false, supports_reasoning = true }, "kr/claude-sonnet-4.6" = { context = 200_000, max_output = 64_000, supports_vision = false, supports_reasoning = true }, "kr/claude-sonnet-4.5" = { context = 200_000, max_output = 64_000, supports_vision = false, supports_reasoning = true }, "kr/claude-haiku-4.5" = { context = 200_000, max_output = 64_000, supports_vision = false, supports_reasoning = true }, "SSS-tier" = { context = 1_000_000, max_output = 64_000, supports_vision = false, supports_reasoning = true }, "SS-tier" = { context = 220_000, max_output = 32_000, supports_vision = false, supports_reasoning = true }, "S-tier" = { context = 200_000, max_output = 128_000, supports_vision = false, supports_reasoning = true }, "A-tier" = { context = 128_000, max_output = 64_000, supports_vision = false, supports_reasoning = false }, "B-tier" = { context = 128_000, max_output = 32_000, supports_vision = false, supports_reasoning = false }, "cx/gpt-5.5" = { context = 220_000, max_output = 32_000, supports_vision = false, supports_reasoning = true }, "cx/gpt-5.5-high" = { context = 220_000, max_output = 32_000, supports_vision = false, supports_reasoning = true }, "cx/gpt-5.5-xhigh" = { context = 220_000, max_output = 32_000, supports_vision = false, supports_reasoning = true }, "cx/gpt-5.5-medium" = { context = 220_000, max_output = 32_000, supports_vision = false, supports_reasoning = true } }

    # MCP servers — extend gptme's tool surface with Model Context
    # Protocol providers. Tools become available as `<server>.<tool>`
    # in conversation. See researches/ for evaluation notes.
    [mcp]
    enabled = true
    auto_start = true

    # mcp-nixos — utensils/mcp-nixos. Searchable NixOS option +
    # package documentation. Runs through uvx because the upstream
    # nix flake currently breaks on nixpkgs' fastmcp derivation
    # (missing platformdirs). uvx pulls real PyPI deps and works.
    [[mcp.servers]]
    name = "nixos"
    enabled = true
    command = "${uvx-bin}"
    args = ["mcp-nixos"]

    # mcp-nix — felixdorn/mcp-nix. Second-layer Nix MCP that
    # complements mcp-nixos by exposing what mcp-nixos doesn't:
    # derivation source code (read_derivation), option declaration
    # files with line numbers (read_option_declaration), search
    # across ecosystem modules outside core nixpkgs (sops-nix,
    # disko, impermanence, microvm, nixos-hardware, nix-nomad,
    # simple-nixos-mailserver), and Nix stdlib lookups (Noogle).
    # Decision rule between the two — see SOUL.md §9.
    #
    # `--python ${python313-bin}` is mandatory: mcp-nix requires
    # Python ≥3.13 (gptme's interpreter is 3.12, would fail uv's
    # version resolver) and uv's auto-download path picks up a
    # generic-linux build that NixOS cannot run (dynamic loader
    # mismatch). Pointing uvx at the Nix-built python313 fixes
    # both — see python313-bin in the let-block above.
    [[mcp.servers]]
    name = "nix"
    enabled = true
    command = "${uvx-bin}"
    args = ["--python", "${python313-bin}", "mcp-nix"]

    # context7 — Upstash hosted documentation lookup. HTTP remote;
    # X-Context7-API-Key auth. Pulls up-to-date library/framework
    # docs into the LLM context. Useful when working with libraries
    # whose APIs have shifted post-training-cutoff.
    [[mcp.servers]]
    name = "context7"
    enabled = true
    url = "https://mcp.context7.com/mcp"
    headers = { X-Context7-API-Key = "@CONTEXT7_API_KEY@" }

    # fetch — modelcontextprotocol/servers `src/fetch`. Fetches a URL
    # and converts HTML to markdown. Not packaged in nixpkgs; we use
    # `uvx` to grab + run it from PyPI on first use, transparently.
    # uvx caches the venv after first run, so subsequent starts are
    # near-instant.
    [[mcp.servers]]
    name = "fetch"
    enabled = true
    command = "${uvx-bin}"
    args = ["mcp-server-fetch"]
  '';

  # Fish function — defined as a separate file so home-manager picks
  # it up via programs.fish.functions cleanly. The function lives in
  # XDG_CONFIG_HOME/fish/functions/talos.fish at activation.
  #
  # YOLO mode: every `command gptme` call passes `-y` (--no-confirm)
  # so the runtime never blocks on patch / shell / save confirmations.
  # The behavioural guardrails (SOUL §2 destructive-operation tiers,
  # privacy zones) still live in the system prompt and apply
  # regardless of -y; -y only disables the gptme-level confirmations,
  # not the agent-level ones.
  #
  # Session prehook: before every `gptme` invocation that targets the
  # brain workdir we run scripts/build-runtime-context.sh, which
  # regenerates RUNTIME_CONTEXT.md (last 3 journal entries, hostname,
  # the four INDEX.md files, pointer to MAP.md). gptme.toml [prompt]
  # .files lists RUNTIME_CONTEXT.md last so a fresh copy is read at
  # session start. A failure of the prehook never blocks talos: the
  # function logs a warning to stderr and continues into gptme.
  talosFish = ''
    set -l brain "${brainDir}"
    set -l prehook "$brain/scripts/build-runtime-context.sh"

    # `help` works regardless of brain presence — it is a pure local
    # message and the user may legitimately be running `talos help`
    # before they have cloned the brain repo.
    if test (count $argv) -ge 1
      switch $argv[1]
        case 'help' '--help' '-h'
          echo "talos — sysadmin agent (gptme + brain workdir)"
          echo ""
          echo "Usage:"
          echo "  talos                  Start TUI in $brain"
          echo "  talos help             This message"
          echo "  talos journal          Open today's journal entry"
          echo "  talos system <prompt>  Run with workdir = /etc/nixos"
          echo "  talos <prompt...>      Run in brain with prompt"
          return 0
      end
    end

    if not test -d "$brain"
      echo "talos: brain directory $brain not found." >&2
      echo "       Clone ponkcore/talos-brain to $brain before invoking talos." >&2
      return 1
    end

    # Refresh RUNTIME_CONTEXT.md before launching gptme. Non-fatal:
    # a broken prehook must never prevent talos from starting.
    if test -x "$prehook"
      bash "$prehook"; or echo "talos: prehook $prehook failed; continuing" >&2
    end

    # No args — open TUI in brain workdir.
    if test (count $argv) -eq 0
      cd "$brain"
      command gptme -y
      return $status
    end

    switch $argv[1]
      case 'journal'
        cd "$brain"
        command gptme -y \
          "Open journal/"(date +%Y-%m-%d)".md and summarise what I did today. If the file does not exist, create it with a short opening note. Reply to me in Russian."
      case 'system'
        cd /etc/nixos
        if test (count $argv) -ge 2
          command gptme -y $argv[2..]
        else
          command gptme -y
        end
      case '*'
        cd "$brain"
        command gptme -y $argv
    end
  '';
in {
  # uv ships uvx alongside, used by gptme's [[mcp.servers]] block
  # to launch mcp-server-fetch from PyPI on first use (no nixpkgs
  # entry for that python package).
  home.packages = [pkgs.gptme pkgs.uv];

  programs.fish.functions.talos = talosFish;

  # Render ~/.config/gptme/config.toml from configTemplate, substituting
  # the secrets read from /run/agenix/tokens. Mirrors the opencode-
  # config activation in home/opencode.nix.
  home.activation.talos-config = lib.hm.dag.entryAfter ["writeBoundary"] ''
    set -eu
    SECRETS="/run/agenix/tokens"
    OUT="${config.xdg.configHome}/gptme/config.toml"
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
    if [ -z "''${FIREWORKS_API_KEY:-}" ]; then
      echo "ERROR: FIREWORKS_API_KEY missing in $SECRETS" >&2
      exit 1
    fi
    if [ -z "''${CONTEXT7_API_KEY:-}" ]; then
      echo "ERROR: CONTEXT7_API_KEY missing in $SECRETS" >&2
      exit 1
    fi
    # OMNIROUTE_BASE_URL is not part of tokens.age (the opencode module
    # hard-codes the URL); keep it overridable here in case a future
    # host fronts a different proxy.
    : "''${OMNIROUTE_BASE_URL:=https://omniroute.infinitycore.space:8443/v1}"

    mkdir -p "${config.xdg.configHome}/gptme"
    umask 077
    ${pkgs.gnused}/bin/sed \
      -e "s|@OMNIROUTE_BASE_URL@|$OMNIROUTE_BASE_URL|g" \
      -e "s|@OMNIROUTE_API_KEY@|$OMNIROUTE_API_KEY|g" \
      -e "s|@FIREWORKS_API_KEY@|$FIREWORKS_API_KEY|g" \
      -e "s|@CONTEXT7_API_KEY@|$CONTEXT7_API_KEY|g" \
      ${configTemplate} > "$OUT.tmp"
    chmod 600 "$OUT.tmp"
    mv -f "$OUT.tmp" "$OUT"
  '';

  # Regenerate ~/Documents/talos-brain/MAP.md after every nixos-rebuild
  # switch, so the brain's flat index reflects the freshly switched
  # /etc/nixos tree without the user having to run anything by hand.
  #
  # Non-fatal: if the brain workdir is missing or the script errors,
  # we log to stderr and continue. A failed MAP regen must never block
  # a system rebuild.
  # Regenerate ~/Documents/talos-brain/MAP.md after every nixos-rebuild
  # switch.
  #
  # Why we hard-code the bash + awk paths instead of relying on the
  # script's `#!/usr/bin/env bash` shebang: home-manager activation
  # runs with a minimal PATH containing only coreutils, findutils,
  # gnugrep, gnused, systemd. Neither bash nor gawk are on it, so
  # `env bash` fails with "No such file or directory" and the script
  # never even starts. Using ${pkgs.bash}/bin/bash and exporting an
  # extended PATH that includes ${pkgs.gawk} makes the call work
  # under the activation environment without depending on the user
  # shell's PATH being available (which it is not at activation).
  #
  # Non-fatal by design: if the brain workdir is missing, the script
  # errors out, or any tool blows up, we WARN to stderr and continue.
  # A failed MAP regeneration must never block a system rebuild.
  home.activation.talos-mapgen = lib.hm.dag.entryAfter ["writeBoundary"] ''
    BRAIN="${brainDir}"
    SCRIPT="$BRAIN/scripts/regen-map.sh"
    if [ -r "$SCRIPT" ]; then
      export PATH="${pkgs.bash}/bin:${pkgs.gawk}/bin:$PATH"
      if ! ${pkgs.bash}/bin/bash "$SCRIPT" >/dev/null 2>&1; then
        echo "WARN: talos-mapgen: $SCRIPT failed; continuing rebuild." >&2
      fi
    else
      echo "INFO: talos-mapgen: $SCRIPT not found or unreadable; skipping." >&2
    fi
  '';
}
