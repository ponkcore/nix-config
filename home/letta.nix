# home/letta.nix — Letta Code memory-first agent.
#
# Replaces gptme as the talos agent runtime (see
# decisions/0015-migrate-to-letta-code.md).
#
# Phase 3 (providers): fish wrapper with agenix secrets,
# environment variables for omniroute + fireworks.
#
# home/talos.nix (gptme) is NOT modified — rollback is a revert
# of this module. The talos fish function here uses mkForce
# to override the gptme-era definition from home/talos.nix.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  brainDir = "${config.home.homeDirectory}/Documents/talos-brain";
in {
  imports = [inputs.letta-code.homeManagerModules.default];

  programs.letta-code = {
    enable = true;
    package = pkgs.letta-code;
  };

  home.packages = with pkgs; [
    mcp-bridge
    mcp-nixos
    mcp-nix
  ];

  home.file.".letta/skills/nixos-options/SKILL.md" = {
    source = ../skills/nixos-options/SKILL.md;
  };

  programs.fish.functions.talos = lib.mkForce ''
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

    # Source agenix secrets (OMNIROUTE_API_KEY, FIREWORKS_API_KEY)
    # into the letta process environment. The keys live in
    # /run/agenix/tokens (decrypted at boot, mode 400, owner=oonishi)
    # and are never written to /nix/store.
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

    cd "$brain"

    # No args — open TUI with default agent
    if test (count $argv) -eq 0
      command letta --backend local
      return $status
    end

    switch $argv[1]
      case 'journal'
        command letta --backend local -p \
          "Open journal/"(date +%Y-%m-%d)".md and summarise what I did today. If the file does not exist, create it with a short opening note. Reply to me in Russian."
      case 'system'
        cd /etc/nixos
        if test (count $argv) -ge 2
          command letta --backend local $argv[2..]
        else
          command letta --backend local
        end
      case '*'
        command letta --backend local $argv
    end
  '';
}
