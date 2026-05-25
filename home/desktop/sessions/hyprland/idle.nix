# idle.nix — Hyprland idle manager (hypridle).
# Conditional timeouts depending on AC vs battery. On battery we let
# the box go to S3 to preserve charge. On AC we only blank the
# screens — suspend on AC is intentionally disabled because Hyprland
# 0.52.1 mis-recomputes floating-window coordinates and hyprlock
# scale on resume from suspend in this multi-monitor setup
# (eDP-1 @ scale 2, HDMI-A-1 @ scale 1), causing windows to fly
# off-screen by ~one layout-width. The on-battery helper is supplied
# by the laptop form-factor profile (modules/hardware/form-factor/
# laptop.nix) via _module.args so this session-level module never
# reaches into /sys directly.
{on-battery, ...}: {
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        # -- Battery: screen off at 15 min --
        {
          timeout = 900;
          on-timeout = "${on-battery}/bin/on-battery && hyprctl dispatch dpms off || true";
          on-resume = "hyprctl dispatch dpms on";
        }
        # -- AC: screen off at 60 min --
        {
          timeout = 3600;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
        # -- Battery: suspend at 30 min (15 min after screen off) --
        {
          timeout = 1800;
          on-timeout = "${on-battery}/bin/on-battery && systemctl suspend || true";
        }
        # NOTE: AC suspend listener intentionally absent — see header.
      ];
    };
  };
}
