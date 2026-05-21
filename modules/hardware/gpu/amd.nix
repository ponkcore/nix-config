# gpu/amd.nix — AMD GPU enablement profile.
#
# Opt-in for any host with an AMD GPU (integrated or discrete). Provides:
#   - amdgpu kernel module loaded early (initrd) for Plymouth + early KMS
#   - Mesa drivers with 32-bit support for Steam / Wine
#   - VA-API (libva) and VDPAU→VA-API bridge for hardware video decode
#   - Power & display feature masks tuned for Phoenix/Strix-class APUs:
#       · ABM (Adaptive Backlight Modulation) on level 2 — battery saver
#         that dims the LED panel proportionally to dark scene content.
#       · dcfeaturemask=0x8 — enable PSR-SU (Selective Update); cuts panel
#         self-refresh power draw on static content (terminal, code review).
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
      "amdgpu.abmlevel=2"
      "amdgpu.dcfeaturemask=0x8"
      "amdgpu.ppfeaturemask=0xfff7ffff"
      "amdgpu.sg_display=0"
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
