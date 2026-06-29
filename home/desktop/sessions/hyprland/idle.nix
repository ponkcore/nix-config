# idle.nix — Hyprland idle manager (hypridle).
#
# Architecture: hypridle is reduced to an idle SIGNAL generator + lock/
# sleep hooks. It does NOT call hyprctl dispatch dpms directly. Instead,
# the idle listener touches/clears a flag file ($XDG_RUNTIME_DIR/
# hyprland-idle) that the lid-monitor service polls every 200 ms.
# lid-monitor is the sole owner of DPMS/backlight state, which
# eliminates the race where hypridle's on-resume re-enables a closed
# panel on mouse activity.
#
# Policy:
#   - lock on sleep (before_sleep_cmd)
#   - idle flag set after 30s on battery, cleared on any input
#   - never idle-suspend: the laptop only sleeps on lid close (handled
#     by logind/Hyprland bindl, not here).
#   - after_sleep_cmd removed: lid-monitor handles post-resume display
#     state via its normal poll cycle (lid open + no idle flag → dpms on).
#
# Research: 2026-06-25-lid-blanking-hyprland, Design 3.
{on-battery, ...}: let
  # Flag file polled by lid-monitor. On battery only — on AC the
  # on-battery helper exits 1 and the flag is never created, so
  # lid-monitor never sees an idle state on AC.
  idleFlag = "\${XDG_RUNTIME_DIR:-/tmp}/hyprland-idle";
in {
  services.hypridle = {
    enable = true;
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
