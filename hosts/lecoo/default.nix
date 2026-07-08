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
  username,
  ...
}: {
  _module.args.hostDisplay = {
    internalMonitor = "eDP-1";
    internalMode = "2880x1800@120";
    internalModeEco = "2880x1800@60";
    internalScale = "1.8";
    wallpaperSize = "2880x1800";
  };

  home-manager.extraSpecialArgs.hostDisplay = {
    internalMonitor = "eDP-1";
    internalMode = "2880x1800@120";
    internalModeEco = "2880x1800@60";
    internalScale = "1.8";
    wallpaperSize = "2880x1800";
  };

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

  # Kernel — latest from main nixpkgs (7.1.2). No kernel patches —
  # using binary cache. mac80211 TDLS patch removed: it triggered
  # full kernel source builds on every nixpkgs revision bump.
  # If WiFi TDLS key failures recur (Syncthing devices on same BSS),
  # re-add the patch from hosts/lecoo/patches/ and build with
  # --max-jobs 2 --cores 2 on AC.
  # Source: research 2026-06-28-rtw89-key-addition-failure.result.md
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Host-scoped overlays:
  # 26.05 migration: Hyprland flake overlay and unstable pull overlay
  # removed — 26.05 ships all ecosystem packages natively at the same
  # versions (hyprland 0.55.4, hyprpaper 0.8.4, quickshell 0.3.0, etc.).
  # Only the lecoo-ctrl custom package overlay remains.
  nixpkgs.overlays = [
    (final: _prev: {
      lecoo-ctrl = final.callPackage ./pkgs/lecoo-ctrl {};
    })
  ];

  # Host-only Home Manager extension. Defines the lecoo-ctrl-driven
  # scripts and host-specific user helpers. Other hosts simply don't
  # extend HM with this layer.
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
