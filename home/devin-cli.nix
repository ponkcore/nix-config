# devin-cli.nix — Cognition Devin agentic CLI.
# Local derivation in pkgs/devin-cli/ pinned via manifest.json; license
# is unfree (allowed globally in modules/nixos/nix.nix).
{pkgs, ...}: {
  home.packages = [pkgs.devin-cli];
}
