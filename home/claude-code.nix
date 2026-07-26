# claude-code.nix — Anthropic Claude Code coding agent.
# Nix owns the pinned binary and secret-injecting launcher; authentication,
# settings, MCP registration, and session state remain mutable user state.
# License: unfree (allowed globally via nixpkgs.config.allowUnfreePredicate).
{pkgs, ...}: {
  home.packages = [
    pkgs.claude-code
  ];

  # Load MCP credentials into the Claude process environment without writing
  # their values to ~/.claude.json, the Nix store, or command arguments.
  # MCP config references these names through Claude's ${VAR} expansion.
  programs.fish.functions.claude = ''
    set -l tokens /run/agenix/tokens
    if not test -r "$tokens"
      echo "claude: $tokens missing or unreadable — authenticated MCP servers will fail." >&2
    else
      while read -l line
        set -l kv (string split -m 1 '=' -- $line)
        if test (count $kv) -eq 2
          set -gx $kv[1] $kv[2]
        end
      end < "$tokens"
    end

    set -l gh_token (${pkgs.gh}/bin/gh auth token 2>/dev/null)
    if test -n "$gh_token"
      set -gx GITHUB_PERSONAL_ACCESS_TOKEN "$gh_token"
    else
      echo "claude: gh auth token returned empty — GitHub MCP will fail." >&2
    end

    command claude $argv
  '';
}
