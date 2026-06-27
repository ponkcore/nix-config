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

  # Kernel — latest (7.1.1) from nixpkgs-unstable overlay. Upgraded
  # from 7.0.5 for:
  #   - amd_dynamic_epp (CONFIG_X86_AMD_PSTATE_DYNAMIC_EPP, 7.1+)
  #     — dynamic EPP adjustments by CPD goroutine
  #   - PSR-SU re-enablement (7.0.x temporarily disabled for DCN
  #     glitch avoidance; 7.1 may restore — pending verification)
  #   - sched_ext production-ready (services.scx in NixOS 25.11)
  #   - rtw89 WiFi PS beacon tracking (already in 7.0.5, carried forward)
  #   - DC_SKIP_DETECTION_LT (0x200000) stable across versions
  # Not LTS — but no ZFS, no out-of-tree modules on lecoo → low risk.
  # Rollback: nixos-rebuild switch --rollback.
  # Source: research 2026-06-27-kernel-7-migration-research +
  #         2026-06-27-final-comprehensive-upgrade-study
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Host-scoped overlays:
  # 1. Hyprland ecosystem — hyprland-packages overlay from the Hyprland
  #    flake composes all core dependencies (aquamarine, hyprlang,
  #    hyprutils, hyprland-protocols, hyprwayland-scanner, hyprcursor,
  #    hyprgraphics) at matching versions.
  # 2. User-facing ecosystem tools + kernel pinned from nixpkgs-unstable:
  #    hyprland 0.55.x, hyprpaper 0.8.0+ (mandatory — IPC protocol
  #    changed in 0.53), hypridle, hyprlock, xdg-desktop-portal-hyprland,
  #    linuxPackages_latest (kernel 7.1.x — amd_dynamic_epp, sched_ext).
  #    Uncomment mesa pin if RDNA3 rendering issues appear.
  # 3. lecoo-ctrl — platform-specific EC daemon (ITE IT5571-07 on
  #    Emdoor N155A). Lives here so future hosts without this EC
  #    don't try to build it.
  nixpkgs.overlays = [
    inputs.hyprland.overlays.hyprland-packages
    (final: _prev: let
      pkgsUnstable = import inputs.nixpkgs-unstable {
        inherit (final.stdenv.hostPlatform) system;
        inherit (final) config;
      };
    in {
      inherit (pkgsUnstable) hyprland hyprpaper hypridle hyprlock xdg-desktop-portal-hyprland waybar linuxPackages_latest;
      # Mesa: Hyprland wiki recommends matching mesa from unstable for
      # RDNA3 to avoid lag/FPS drops. However, mesa 26.1.3 from unstable
      # does NOT have a binary cache for our nixpkgs commit (8fd9daa) —
      # it compiles from source (20+ min, 100% CPU). Using mesa 25.2.6
      # from stable for now. If rendering issues appear, pin mesa from
      # unstable and run the build with a longer timeout.
      # Waybar 0.15.0+ required for Hyprland 0.55.x Lua IPC dispatch.
      # Source: research 2026-06-27-final-comprehensive-upgrade-study §5-6
    })
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
