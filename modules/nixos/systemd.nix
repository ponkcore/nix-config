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
    RuntimeWatchdogSec = 0;
    RebootWatchdogSec = 0;
    WatchdogDevice = "/dev/null";
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
