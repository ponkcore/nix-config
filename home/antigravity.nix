# antigravity.nix — Agentic IDE (Google Antigravity).
# FHS-wrapped variant so extensions install without Nix-specific hacks.
# License: unfree (allowed globally via nixpkgs.config.allowUnfree).
{pkgs, ...}: {
  home.packages = [
    pkgs.antigravity-fhs
  ];
}
