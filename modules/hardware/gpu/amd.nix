# gpu/amd.nix — AMD GPU enablement profile.
#
# Opt-in for any host with an AMD GPU (integrated or discrete). Provides:
#   - amdgpu kernel module loaded early (initrd) for Plymouth + early KMS
#   - Mesa drivers with 32-bit support for Steam / Wine
#   - VA-API (libva) and VDPAU→VA-API bridge for hardware video decode
#   - Power & display feature masks tuned for Phoenix/Strix-class APUs:
#       · ABM (Adaptive Backlight Management) level 1 — DMCU firmware
#         optimises backlight power electronics at low brightness.
#         Est. saving 0.1–0.3 W at min brightness.
#         Source: research 2026-06-29-battery-autonomy-9h §4a
#       · ppfeaturemask=0xfff7ffff — unmasks GPU OD / power-profile control
#         (matches upstream amd-power-profiles defaults; safe on Phoenix2).
#       · sg_display=0 — disables scatter-gather display path; works around
#         intermittent flicker on certain eDP panels under VRR.
#   On hosts that aren't Phoenix/Strix these masks are still safe defaults.
#
# Notably NOT included: ROCm (rocmPackages.clr). It's a discrete-GPU GPGPU
# stack and adds ~500 MB of unused store paths on integrated cards. Hosts
# that need it should re-add via their host-specific module.
{pkgs, ...}: {
  boot = {
    initrd.kernelModules = ["amdgpu"];
    kernelModules = ["amdgpu"];

    kernelParams = [
      "amdgpu.abmlevel=1"
      # ppfeaturemask: kernel default 0xfff7bfff is correct for this
      # APU. The previous value 0xfff7ffff enabled PP_OVERDRIVE_MASK
      # (bit 14, OD clock/voltage tables), but the Radeon 780M
      # firmware does not expose pp_od_clk_voltage — the bit is a
      # no-op. Reverted to default to avoid a misleading config entry.
      # Source: research 2026-06-27-nixos-followup-research §1.2
      "amdgpu.sg_display=0"
      # Disable Panel Replay (0x400) + skip detection link training
      # on DPMS-on (0x200000). PSR v1 stays alive (0x10 NOT set) —
      # keeps the eDP link alive during blanking. DC_SKIP_DETECTION_LT
      # (0x200000) was added in kernel 6.16; requires linuxPackages_6_18
      # (set in hosts/lecoo/default.nix). Combined: zero DPMS-on
      # latency — link stays alive (PSR v1) + detection LT skipped.
      # dcdebugmask defaults to 0 in kernel 6.18 — both bits still
      # necessary, cannot simplify to 0x400.
      # Source: research 2026-06-26-system-pain-points-deep-research §2.3-2.4
      # Source: research 2026-06-27-nixos-followup-research §1.3
      "amdgpu.dcdebugmask=0x200400"
    ];
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      # Mesa's radeonsi already provides the VA-API driver. libva is the
      # runtime loader; libvdpau-va-gl bridges VDPAU clients to VA-API.
      libva
      libvdpau-va-gl
    ];
  };
}
