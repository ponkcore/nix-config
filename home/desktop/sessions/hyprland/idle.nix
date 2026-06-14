# idle.nix — Hyprland idle manager (hypridle).
#
# Policy:
#   - lock on sleep (before_sleep_cmd)
#   - idle-driven DPMS off, but ONLY on battery. On AC the screen
#     never blanks on a timer. Driven by the `on-battery` helper from
#     the laptop form-factor profile: `on-battery` exits 0 when on
#     battery, so `on-battery && <blank>` only fires unplugged.
#   - never idle-suspend: the laptop only sleeps on lid close (handled
#     by logind/Hyprland bindl, not here).
#
# DPMS targets eDP-1 explicitly rather than a bare `dpms off`. A bare
# blank would also turn off any external monitor that happens to be
# plugged in; eDP-1 is always the internal panel on this host.
{
  pkgs,
  on-battery,
  ...
}: let
  # 5 min idle on battery → blank eDP-1; restore on activity.
  dpmsOff = "${on-battery}/bin/on-battery && ${pkgs.hyprland}/bin/hyprctl dispatch dpms off eDP-1";
  dpmsOn = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on eDP-1";
in {
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        {
          timeout = 300;
          on-timeout = dpmsOff;
          on-resume = dpmsOn;
        }
      ];
    };
  };
}
