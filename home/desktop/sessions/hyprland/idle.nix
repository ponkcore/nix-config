# idle.nix — Hyprland idle manager (hypridle).
# Conditional timeouts depending on AC vs battery: longer screen-off
# and suspend grace periods when plugged in. The on-battery helper is
# supplied by the laptop form-factor profile (modules/hardware/
# form-factor/laptop.nix) via _module.args so this session-level module
# never reaches into /sys directly.
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
        # -- Battery: suspend at 25 min (10 min after screen off) --
        {
          timeout = 1500;
          on-timeout = "${on-battery}/bin/on-battery && systemctl suspend || true";
        }
        # -- AC: suspend at 70 min (10 min after screen off) --
        {
          timeout = 4200;
          on-timeout = "systemctl suspend";
        }
      ];
    };
  };
}
