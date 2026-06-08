# antigravity.nix — Google Antigravity IDE + CLI.
# FHS-wrapped IDE so extensions install without Nix-specific hacks.
# CLI (agy) from local overlay — not yet in 25.11 channel.
# License: unfree (allowed globally via nixpkgs.config.allowUnfree).
{pkgs, ...}: {
  home.packages = [
    pkgs.antigravity-fhs
    pkgs.antigravity-cli
  ];
}
