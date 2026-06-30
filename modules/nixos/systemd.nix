# systemd.nix — system-wide systemd manager tuning.
#
# Universal: applies the same shutdown timeout policy on every host.
# 30s for system services is the floor — going below risks SIGKILLing
# Docker/libvirtd mid-overlay2-stop and corrupting layers.
_: {
  # ── System manager timeouts (faster shutdown) ──
  systemd.settings.Manager = {
    DefaultTimeoutStopSec = "30s";
    DefaultDeviceTimeoutSec = "10s";
    # Hardware watchdog — pings /dev/watchdog (sp5100_tco on AMD
    # southbridge) every 15s. If the system freezes (e.g., amdgpu
    # DMCUB firmware crash → flip_done timeout → hard lockup),
    # pings stop and the hardware watchdog triggers a system reset
    # after 30s. This is the only reliable recovery mechanism for
    # DMCUB crashes: gpu_recovery=1 does not cover display firmware
    # hangs, and no kernel-level DMCUB reset path exists.
    # Source: researches/2026-06-30-amdgpu-dmcub-crash-deep-research.result.md §2,§7
    RuntimeWatchdogSec = "30s";
    RebootWatchdogSec = "5min";
    WatchdogDevice = "/dev/watchdog";
  };

  # ── User manager timeouts ──
  # systemd.user.settings.Manager does NOT exist as a NixOS option. Use
  # extraConfig (raw INI) for the per-user manager defaults. user@1000.service
  # has a hardcoded 2-minute TimeoutStopSec that we override specifically.
  systemd.user.extraConfig = ''
    DefaultTimeoutStopSec=10s
  '';
  systemd.services."user@".serviceConfig.TimeoutStopSec = "15s";
}
