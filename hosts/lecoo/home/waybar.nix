# hosts/lecoo/home/waybar.nix — Lecoo-only waybar fragment.
#
# Provides the custom/battery slot config that the universal theme/waybar
# layout reserves for the lecoo host. This is the merged
# system-battery + Lecoo EC charge-mode widget; it depends on
# pkgs.lecoo-ctrl (host-scoped overlay) and battery-lecoo / lecoo-toggle
# scripts (host-scoped HM module).
{
  battery-lecoo,
  lecoo-toggle,
  ultra-economy-status,
  ultra-economy-toggle,
  ...
}: {
  programs.waybar.settings.mainBar = {
    "custom/battery" = {
      exec = "${battery-lecoo}/bin/battery-lecoo";
      exec-on-event = true;
      interval = 5;
      return-type = "json";
      format = "{icon}";
      format-icons = {
        charging = ["󰢜" "󰂆" "󰂇" "󰂈" "󰢝" "󰂉" "󰢞" "󰂊" "󰂋" "󰂅"];
        discharging = ["󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹"];
        full = ["󰁹"];
      };
      on-click-right = "${lecoo-toggle}/bin/lecoo-toggle";
      tooltip = true;
    };

    "custom/ultra-economy" = {
      exec = "${ultra-economy-status}/bin/ultra-economy-status";
      return-type = "json";
      interval = "once";
      signal = 8;
      format = "{text}";
      on-click = "${ultra-economy-toggle}/bin/ultra-economy-toggle";
      tooltip = false;
    };
  };
}
