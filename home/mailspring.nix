# mailspring.nix — Mailspring desktop email client.
#
# Free for personal use; the optional Mailspring Pro features live
# behind a paid account and are not enabled by default. The package is
# GPL-3.0+, so no allowUnfree gate is needed.
{pkgs, ...}: {
  home.packages = [pkgs.mailspring];
}
