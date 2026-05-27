# idle.nix — Hyprland idle manager (hypridle).
#
# Policy: hypridle owns lock-on-sleep only. No idle-driven DPMS, no
# idle-driven suspend. Screen blanking is exclusively driven by the
# lid switch (see bindl in session.nix), and the box never suspends
# on a timer — battery state is the operator's responsibility.
#
# Why no idle DPMS:
# AOC 24G2W1G4 on HDMI-A-1 mis-handles DPMS off — the panel drops
# the HDMI link entirely, Hyprland sees a monitor hot-unplug and
# translates every HDMI-pinned floating-window X coordinate by
# -monitor.x. On the subsequent monitoradded the coordinates are
# not restored, so windows end up stacked on eDP-1. Even targeting
# only eDP-1 leaves a footgun: any future revert to "dpms off"
# without a monitor argument re-arms the bug. Removing all DPMS
# listeners is the durable fix.
#
# Why no idle suspend:
# Per operator policy: the laptop only sleeps on lid close (handled
# by logind/Hyprland bindl, not here). Idle-suspend would also
# expose the Hyprland 0.52.1 multi-monitor resume bug
# (mis-recomputed floating coords + hyprlock scale on
# eDP-1@scale2 + HDMI-A-1@scale1).
#
# This module currently consumes no _module.args from the laptop
# form-factor profile. If a battery-only listener is reintroduced,
# add `on-battery` back to the argument set — the helper is
# already exported by modules/hardware/form-factor/laptop.nix.
_: {
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [];
    };
  };
}
