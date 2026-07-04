# home/letta.nix — Letta Code memory-first agent.
#
# Primary talos agent runtime.
#
# Phase 3 (providers): fish wrapper with agenix secrets,
# environment variables for omniroute + fireworks.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  brainDir = "${config.home.homeDirectory}/Documents/talos-brain";
  talosAgentId = "agent-local-686d5667-5fc0-45c2-ab97-f3e984b22a27";
in {
  imports = [inputs.letta-code.homeManagerModules.default];

  programs.letta-code = {
    enable = true;
    package = pkgs.letta-code;
  };

  home.packages = with pkgs; [
    mcp-bridge
    mcp-nixos
    context7-mcp
    fetch-py
    uv
    github-mcp-server
  ];

  home.file = {
    ".letta/skills/nixos-options/SKILL.md" = {
      source = ../skills/nixos-options/SKILL.md;
    };
    ".letta/skills/context7-docs/SKILL.md" = {
      source = ../skills/context7-docs/SKILL.md;
    };
    ".letta/skills/web-fetch/SKILL.md" = {
      source = ../skills/web-fetch/SKILL.md;
    };
    ".letta/skills/omniroute-mcp/SKILL.md" = {
      source = ../skills/omniroute-mcp/SKILL.md;
    };
    ".letta/skills/github-mcp/SKILL.md" = {
      source = ../skills/github-mcp/SKILL.md;
    };
  };

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

  programs.fish.functions.talos = ''
    set -l brain "${brainDir}"

    if test (count $argv) -ge 1
      switch $argv[1]
        case 'help' '--help' '-h'
          echo "talos — sysadmin agent (letta + brain workdir)"
          echo ""
          echo "Usage:"
          echo "  talos                  Start TUI in $brain"
          echo "  talos help             This message"
          echo "  talos journal          Open today's journal entry"
          echo "  talos system <prompt>  Run with workdir = /etc/nixos"
          echo "  talos <args...>        Pass args to letta"
          return 0
      end
    end

    if not test -d "$brain"
      echo "talos: brain directory $brain not found." >&2
      return 1
    end

    # Source agenix secrets (OMNIROUTE_API_KEY, FIREWORKS_API_KEY,
    # CONTEXT7_API_KEY, LAZYWEB_MCP_TOKEN, OMNIROUTE_MCP_API_KEY) into
    # the letta process environment. The keys live in /run/agenix/tokens (decrypted at
    # boot, mode 400, owner=oonishi) and are never written to /nix/store.
    set -l tokens "/run/agenix/tokens"
    if not test -r "$tokens"
      echo "talos: $tokens missing or unreadable." >&2
      return 1
    end
    # shellcheck disable=SC2030
    set -l _talos_env (cat $tokens | string split '\n')
    for _line in $_talos_env
      if test -n "$_line"
        set -l _kv (string split -m 1 '=' $_line)
        set -gx $_kv[1] $_kv[2]
      end
    end

    set -gx LETTA_LOCAL_BACKEND_EXPERIMENTAL 1

    # GitHub MCP: source token from gh CLI (already auth'd via
    # gh auth login). Not stored in agenix — same pattern as
    # omo/omp. GITHUB_PERSONAL_ACCESS_TOKEN is consumed by
    # github-mcp-server via mcp-bridge (env inheritance).
    set -l gh_token (${pkgs.gh}/bin/gh auth token 2>/dev/null)
    if test -n "$gh_token"
      set -gx GITHUB_PERSONAL_ACCESS_TOKEN "$gh_token"
    else
      echo "talos: gh auth token returned empty — GitHub MCP will fail." >&2
    end

    cd "$brain"

    # No args — open TUI with talos agent
    if test (count $argv) -eq 0
      command letta --backend local --agent ${talosAgentId}
      return $status
    end

    switch $argv[1]
      case 'journal'
        command letta --backend local --agent ${talosAgentId} -p \
          "Open journal/"(date +%Y-%m-%d)".md and summarise what I did today. If the file does not exist, create it with a short opening note. Reply to me in Russian."
      case 'system'
        cd /etc/nixos
        if test (count $argv) -ge 2
          command letta --backend local --agent ${talosAgentId} $argv[2..]
        else
          command letta --backend local --agent ${talosAgentId}
        end
      case '*'
        command letta --backend local --agent ${talosAgentId} $argv
    end
  '';
}
