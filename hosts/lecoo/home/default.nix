# hosts/lecoo/home/default.nix — Lecoo-only Home Manager extension.
#
# Aggregator for everything that lives at the user-level but only on
# this host: lecoo-ctrl-driven scripts.
#
# Wired into HM by hosts/lecoo/default.nix (which extends
# home-manager.users.${username}.imports).
{...}: {
  imports = [
    ./scripts.nix
  ];
}
