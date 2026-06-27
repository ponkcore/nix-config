# hosts/lecoo/default.nix — Lenovo Lecoo Pro 14 2025.
#
# Hardware: AMD Ryzen 7 H 255 (Zen 4), Radeon 780M iGPU, RTL8852BE WiFi,
# YMTC PC41Q 1TB NVMe, 30 GiB DDR5, ITE IT5571-07 EC.
#
# Composition pattern: import the universal NixOS layer (provided by
# lib/mkHost.nix), opt into hardware-class profiles (AMD CPU + AMD GPU
# + laptop form factor), then layer on host-only specifics
# (hardware-configuration, WiFi quirks, EC daemon, host-only HM).
{
  lib,
  pkgs,
  inputs,
  username,
  ...
}: {
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

  # Kernel — latest (7.1.1). 26.05 ships linuxPackages_latest = 7.1.1
  # natively — no unstable overlay needed.
  # Not LTS — but no ZFS, no out-of-tree modules on lecoo → low risk.
  # Rollback: nixos-rebuild switch --rollback.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Host-scoped overlays:
  # 26.05 migration: Hyprland flake overlay and unstable pull overlay
  # removed — 26.05 ships all ecosystem packages natively at the same
  # versions (hyprland 0.55.4, waybar 0.15.0, hyprpaper 0.8.4, etc.).
  # Only the lecoo-ctrl custom package overlay remains.
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

  # Real display name for the primary user. Surfaces in nwg-hello
  # and any tool reading the GECOS field. Universal users.nix only
  # sets a host-agnostic default ("Primary user").
  users.users.${username}.description = "Oonishi";

  # ── Specialisations ─────────────────────────────────────────────
  # Fallback: if backlight-only lid blanking proves unsuitable (residual
  # glow, power draw), boot into "dpms-lid" to revert to the old DPMS
  # approach. Select from the boot menu or `nixos-rebuild switch
  # --specialisation dpms-lid`.
  specialisation.dpms-lid.configuration = {
    hardware.laptop.lidMonitor.blanking = lib.mkForce "dpms";
  };
}
