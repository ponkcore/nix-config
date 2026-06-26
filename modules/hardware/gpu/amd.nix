# gpu/amd.nix — AMD GPU enablement profile.
#
# Opt-in for any host with an AMD GPU (integrated or discrete). Provides:
#   - amdgpu kernel module loaded early (initrd) for Plymouth + early KMS
#   - Mesa drivers with 32-bit support for Steam / Wine
#   - VA-API (libva) and VDPAU→VA-API bridge for hardware video decode
#   - Power & display feature masks tuned for Phoenix/Strix-class APUs:
#       · ABM (Adaptive Backlight Modulation) disabled — avoids the slow
#         backlight ramp after eDP DPMS-on / lid-open on this panel.
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
      "amdgpu.abmlevel=0"
      "amdgpu.ppfeaturemask=0xfff7ffff"
      "amdgpu.sg_display=0"
      # Disable Panel Self Refresh (0x10) + Panel Replay (0x400) +
      # IPS dynamic mode (0x1000). On Phoenix/780M these low-power
      # eDP features add latency to every DPMS transition — the
      # driver enters/exits PSR/PR around each modeset, and IPS
      # transitions add a re-init delay on DPMS-on. Disabling all
      # three (0x1410) is the most aggressive latency reduction
      # available on kernel 6.12.
      # Source: research 2026-06-25-amd-phoenix-power-ec-deep-research §3b
      "amdgpu.dcdebugmask=0x1410"
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
