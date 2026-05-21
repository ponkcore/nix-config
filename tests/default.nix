# tests/default.nix — aggregates nixosTests for `flake.checks`.
#
# Wired into flake.checks.<system> by flake.nix. Each entry must be a
# self-contained derivation (typically the result of
# pkgs.testers.runNixOSTest) so `nix build .#checks.<system>.<name>`
# is the full failure surface.
{
  pkgs,
  inputs,
}: {
  secrets = import ./secrets.nix {inherit pkgs inputs;};
  users = import ./users.nix {inherit pkgs;};
}
