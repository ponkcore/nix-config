# windsurf.nix — Codeium Windsurf (agentic VSCode fork).
# Stays user-level (state in ~/.config/Windsurf). License is unfree
# (allowed globally in modules/nixos/nix.nix).
{pkgs, ...}: {
  home.packages = [pkgs.windsurf];
}
