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
}: let
  display = {
    internalMonitor = "eDP-1";
    internalMode = "2880x1800@120";
    internalModeEco = "2880x1800@60";
    internalScale = "1.8";
    wallpaperSize = "2880x1800";
  };
in {
  _module.args.hostDisplay = display;

  home-manager.extraSpecialArgs.hostDisplay = display;

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
  # using binary cache. The mac80211 TDLS patch is NOT applied. The
  # first non-kernel runtime workaround (dispatcher + `tdls_disabled 1`)
  # failed on this host because NetworkManager-managed wpa_supplicant
  # exposed no usable per-interface ctrl socket. The next non-kernel
  # path is compiling wpa_supplicant without TDLS support; if that also
  # proves insufficient, re-enable the patch from hosts/lecoo/patches/
  # after a dry-build check (it triggers a kernel source build).
  # Source: research 2026-07-08-wifi-tdls-no-kernel-workarounds.result.md
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Host-scoped overlays:
  # 26.05 migration: Hyprland flake overlay and unstable pull overlay
  # removed — 26.05 ships all ecosystem packages natively at the same
  # versions (hyprland 0.55.4, hyprpaper 0.8.4, etc.).
  # Only the lecoo-ctrl custom package overlay remains.
  #
  # wpa_supplicant overlay: compiles without TDLS support (CONFIG_TDLS
  # unset). This is a non-kernel workaround for the mac80211
  # ieee80211_add_key bug that rejects TDLS peer keys. Without TDLS
  # code in the binary, wpa_supplicant never issues
  # NL80211_CMD_NEW_KEY for a TDLS peer, so the buggy kernel path is
  # never reached. This is a userspace rebuild, not a kernel rebuild.
  # Source: research 2026-07-08-wifi-tdls-no-kernel-workarounds.result.md
  nixpkgs.overlays = [
    (final: _prev: {
      lecoo-ctrl = final.callPackage ./pkgs/lecoo-ctrl {};
      wpa_supplicant = _prev.wpa_supplicant.overrideAttrs (_old: {
        extraConfig = builtins.replaceStrings ["CONFIG_TDLS=y"] ["CONFIG_TDLS="] _prev.wpa_supplicant.extraConfig or "";
      });
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
