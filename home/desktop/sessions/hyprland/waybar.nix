# waybar.nix — Hyprland-session waybar fragment.
#
# Provides configs for the slots that the universal theme/waybar
# layout reserves for an active Hyprland session:
#   - hyprland/workspaces  (Hyprland IPC workspaces module)
#   - custom/telegram      (drives the telegram-toggle script)
#   - custom/spotify       (drives the spotify-toggle script)
#   - custom/clash         (drives the clash-toggle script)
#   - custom/bluetooth     (drives the bluetooth-toggle script)
#
# Imported by home/desktop/sessions/hyprland/default.nix; never
# imported on hosts that do not run Hyprland.
{
  telegram-toggle,
  clash-toggle,
  spotify-toggle,
  bluetooth-toggle,
  ...
}: {
  programs.waybar.settings.mainBar = {
    "hyprland/workspaces" = {
      on-click = "activate";
      cursor = true;
      format = "{icon}";
      format-icons = {
        "1" = "1";
        "2" = "2";
        "3" = "3";
        "4" = "4";
        "5" = "5";
        "6" = "6";
        "7" = "7";
        "8" = "8";
        "9" = "9";
      };
      persistent-workspaces = {
        "1" = [];
        "2" = [];
        "3" = [];
        "4" = [];
        "5" = [];
        "6" = [];
        "7" = [];
        "8" = [];
        "9" = [];
      };
    };

    "custom/telegram" = {
      format = "<span weight='heavy'></span>";
      on-click = "${telegram-toggle}/bin/telegram-toggle";
      tooltip-format = "Telegram";
    };

    "custom/spotify" = {
      format = "<span weight='heavy'></span>";
      on-click = "${spotify-toggle}/bin/spotify-toggle";
      tooltip-format = "Spotify";
    };

    "custom/clash" = {
      format = "<span weight='heavy'></span>";
      on-click = "${clash-toggle}/bin/clash-toggle";
      tooltip-format = "Clash Verge";
    };

    "custom/bluetooth" = {
      format = "<span weight='heavy'></span>";
      on-click = "${bluetooth-toggle}/bin/bluetooth-toggle";
      tooltip-format = "Bluetooth";
    };
  };
}
