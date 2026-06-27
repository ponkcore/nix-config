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

  # Kernel — latest (7.0.5). Upgraded from 6.18 LTS for:
  #   - rtw89 WiFi PS beacon tracking fix (kernel 6.20+, in 7.0.5)
  #     → enables WiFi power-save re-enabling (0.5-1.5 W saving)
  #   - amdgpu improvements past 6.18.x regression window
  #   - DC_SKIP_DETECTION_LT (0x200000) still present in amd_shared.h
  #     (enum is stable across versions, confirmed via source)
  # Not LTS — but no ZFS, no out-of-tree modules on lecoo → low risk.
  # Rollback: nixos-rebuild switch --rollback.
  # Source: research 2026-06-27-battery-unsolved-deep-research §12
  boot.kernelPackages = pkgs.linuxPackages_latest;

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
