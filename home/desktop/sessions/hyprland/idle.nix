# idle.nix — Hyprland idle manager (hypridle).
#
# hypridle is DISABLED. Caelestia IdleMonitors (Phase 3E) owns the
# idle path. Idle policy is configured in shell.json:
#   - timeouts: [] (no idle-timeout DPMS/suspend — lid-monitor
#     handles DPMS via lid polling, same as prior hypridle policy)
#   - lockBeforeSleep: true (Caelestia Lock engages on suspend)
#   - inhibitWhenAudio: true (no idle actions during playback)
#
# The old hypridle configuration is retained for reference below. If
# Caelestia IdleMonitors needs to be reverted, set enable = true and
# pin caelestia-shell back to phase3a-wallpaper-theme.
{on-battery, ...}: let
  # Flag file polled by lid-monitor. On battery only — on AC the
  # on-battery helper exits 1 and the flag is never created, so
  # lid-monitor never sees an idle state on AC.
  idleFlag = "\${XDG_RUNTIME_DIR:-/tmp}/hyprland-idle";
in {
  # Phase 3e TEST: hypridle disabled — Caelestia IdleMonitors owns the
  # idle path. Revert to enable = true after test.
  services.hypridle = {
    enable = false;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session; rm -f ${idleFlag}";
      };
      # Idle screen blanking on battery DISABLED — system autonomy
      # testing. The listener below was the only idle trigger: 30s
      # idle on battery → touch idle flag → lid-monitor DPMS-off.
      # With the listener removed the screen stays on indefinitely
      # on battery. Lid-close blanking (lid-monitor polling
      # /proc/acpi/button/lid) is unaffected — only the idle-timeout
      # path is gone. hypridle still locks the session on sleep
      # (before_sleep_cmd above).
      # To re-enable, restore the listener block:
      #   listener = [{
      #     timeout = 30;
      #     on-timeout = "${on-battery}/bin/on-battery && touch ${idleFlag}";
      #     on-resume = "rm -f ${idleFlag}";
      #   }];
      listener = [];
    };
  };
}
