# antigravity.nix — Google Antigravity CLI (agy).
# Standalone Go binary from local overlay — not yet in 25.11
# channel. The IDE (antigravity-fhs) was removed; only the CLI
# is kept for occasional use.
# License: unfree (allowed globally via nixpkgs.config.allowUnfree).
{pkgs, ...}: {
  home.packages = [
    pkgs.antigravity-cli
  ];
}
