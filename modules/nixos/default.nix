# modules/nixos/default.nix — universal NixOS layer.
#
# Imported by every host via lib/mkHost.nix. Holds everything that
# should hold on any hardware (laptop, desktop): nix daemon
# configuration, user account, locale, networking, security
# hardening, virtualisation, fonts, system services, full Wayland
# desktop stack.
#
# Headless variants (servers, VMs) need a different HM profile and
# should NOT use this aggregator — they should import individual
# leaves explicitly. Such a host is not yet defined in this flake;
# add `hosts/<name>/default.nix` and a slimmer aggregator when
# the need appears.
{...}: {
  imports = [
    ./boot.nix
    ./systemd.nix
    ./locale.nix
    ./networking.nix
    ./maintenance.nix
    ./nix.nix
    ./users.nix
    ./packages.nix
    ./audio.nix
    ./bluetooth.nix
    ./containers.nix
    ./firmware.nix
    ./services.nix
    ./secrets.nix
    ./storage.nix
    ./sync.nix
    ./security.nix
    ./fonts.nix
    ./tailscale.nix
    ./virtualisation.nix
    ./desktop
  ];
}
