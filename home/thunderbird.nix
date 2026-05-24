# thunderbird.nix — Mozilla Thunderbird email client.
#
# MPL-2.0, no allowUnfree gate. Plain package install — accounts and
# profiles are configured interactively in the app, not declaratively.
{pkgs, ...}: {
  home.packages = [pkgs.thunderbird];
}
