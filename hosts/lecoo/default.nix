# hosts/lecoo/default.nix — Lenovo Lecoo Pro 14 2025.
#
# Hardware: AMD Ryzen 7 H 255 (Zen 4), Radeon 780M iGPU, RTL8852BE WiFi,
# YMTC PC41Q 1TB NVMe, 30 GiB DDR5, ITE IT5571-07 EC.
#
# Composition pattern: import the universal NixOS layer (provided by
# lib/mkHost.nix), opt into hardware-class profiles (AMD CPU + AMD GPU
# + laptop form factor), then layer on host-only specifics
# (hardware-configuration, WiFi quirks, EC daemon, host-only HM).
{username, ...}: {
  imports = [
    # Generated mount points + kernel modules required to boot.
    ./hardware-configuration.nix

    # Hardware-class profiles — opt-in.
    ../../modules/hardware/cpu/amd.nix
    ../../modules/hardware/gpu/amd.nix
    ../../modules/hardware/form-factor/laptop.nix

    # Host-only.
    ./hardware.nix
    ./ec.nix
  ];

  system.stateVersion = "25.11";

  # Host-scoped overlay: lecoo-ctrl is platform-specific (ITE IT5571-07
  # EC chip on Emdoor N155A motherboards). Lives under hosts/lecoo/pkgs/
  # rather than the universal pkgs/ overlay so future hosts that don't
  # have this EC don't try to build it.
  nixpkgs.overlays = [
    (final: _prev: {
      lecoo-ctrl = final.callPackage ./pkgs/lecoo-ctrl {};
    })
  ];

  # Host-only Home Manager extension. Defines the lecoo-ctrl-driven
  # scripts (battery-lecoo, lecoo-toggle, lecoo-status) and the waybar
  # custom/battery fragment that consumes them. Other hosts simply
  # don't extend HM with this and the universal layout falls back to
  # the standard built-in `battery` slot.
  home-manager.users.${username}.imports = [./home];

  # Lecoo EC daemon — defined as a NixOS module under hosts/lecoo/ec.nix.
  # The option is host-specific because the EC chip is platform-specific.
  services.lecoo-ctrl.enable = true;

  # Real display name for the primary user. Surfaces in ReGreet and
  # any tool reading the GECOS field. Universal users.nix only sets
  # a host-agnostic default ("Primary user").
  users.users.${username}.description = "Oonishi";
}
