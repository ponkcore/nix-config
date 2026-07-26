# claude-code.nix — Anthropic Claude Code coding agent.
# Nix owns the pinned binary; authentication, settings, and mutable
# session state remain user-owned under the tool's standard paths.
# License: unfree (allowed globally via nixpkgs.config.allowUnfreePredicate).
{pkgs, ...}: {
  home.packages = [
    pkgs.claude-code
  ];
}
