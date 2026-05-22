# theme/waybar/default.nix — compositor-agnostic waybar skeleton.
#
# Owns the visual contract: CSS, palette wiring, module slot order,
# and configs for modules that hold across any compositor and any host
# (clock, network, cpu, audio, brightness, power, separator, nix
# rebuild button).
#
# Slots that depend on a specific session live in
# home/desktop/sessions/<name>/waybar.nix:
#   - hyprland/workspaces  (Hyprland-only IPC source)
#   - custom/telegram      (uses hyprctl special workspaces)
#   - custom/clash         (uses hyprctl special workspaces)
#
# Slots that depend on host hardware live in hosts/<name>/home/waybar.nix:
#   - custom/battery       (Lecoo-aware: merges system battery with EC
#                           charge mode via the lecoo-ctrl daemon)
#
# Composition: this file declares the slot order; missing fragments are
# filtered out at activation time so a host that opts out of a slot
# does not need to redefine the layout.
{
  config,
  lib,
  pkgs,
  p,
  desktops ? [],
  hostname ? "",
  ...
}: let
  hasHyprland = builtins.elem "hyprland" desktops;
  isLecoo = hostname == "lecoo";

  # Module slot order — referenced by name in modules-{left,center,right}.
  # If the corresponding config fragment is not present (because no
  # session/host module supplied it) waybar simply ignores the entry.
  modulesLeft =
    [
      "custom/separator"
      "custom/nix"
      "clock"
      "custom/separator"
    ]
    ++ lib.optionals hasHyprland [
      "custom/telegram"
      "custom/spotify"
      "custom/clash"
      "custom/separator"
    ];

  modulesCenter = lib.optionals hasHyprland ["hyprland/workspaces"];

  # custom/battery is the lecoo-aware merged battery+EC widget; only the
  # lecoo host supplies its config (in hosts/lecoo/home/waybar.nix).
  # Other laptop hosts fall back to the standard built-in "battery"
  # module, which reads /sys/class/power_supply directly and needs no
  # config.
  modulesRight =
    [
      "custom/separator"
      "group/brightness"
      "group/volume"
      "custom/bluetooth"
      "network"
      "cpu"
    ]
    ++ lib.optionals isLecoo ["custom/battery"]
    ++ lib.optionals (!isLecoo) ["battery"]
    ++ [
      "custom/power"
      "custom/separator"
    ];
in {
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    style = ''
      @define-color bg ${p.bg};
      @define-color bg_mid ${p.bg_mid};
      @define-color fg ${p.fg};
      @define-color fg_bright ${p.fg_bright};
      @define-color fg_dim ${p.fg_dim};
      @define-color border ${p.border};
      @define-color border_inact ${p.border_inact};
      @define-color border_act ${p.border_act};
      @define-color hover_bg ${p.hover_bg};
      @define-color hover_fg ${p.hover_fg};
      @define-color accent ${p.accent_warm};
      @define-color red ${p.bright_red};
      @define-color warning ${p.bright_yellow};

      * {
        border-radius: 0;
        border: none;
        text-shadow: none;
        padding: 0;
        min-height: 0;
        font-family: 'CaskaydiaCove Nerd Font Propo';
        font-weight: normal;

      }

      #waybar {
        background-color: transparent;
      }

      #waybar > box {
        color: @fg;
        background-color: @bg_mid;
        margin: 0px 6px 3px 6px;
        padding: 0px;
        box-shadow: 0px 1px 2px rgba(0, 0, 0, 1);
        border-left: 1px solid @border;
        border-right: 1px solid @border;
        border-bottom: 1px solid @border;
        border-radius: 4px;
        font-weight: normal;
        font-size: 16px;
        transition-property: background-color;
        transition-duration: .5s;
        min-height: 36px;
      }

      .modules-left { margin-left: 4px; }
      .modules-right { margin-right: 4px; }

      #workspaces {
        padding: 0 0px;
        margin: 3px 12px;
        background-color: @bg;
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.4);
      }

      button {
        box-shadow: inset 0 -2px transparent;
        border: none;
        border-radius: 0;
        transition: 0.3s ease-in-out;
      }

      button:hover { background: inherit; }

      #workspaces button {
        all: initial;
        border: 1px solid @border_inact;
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.25);
        border-radius: 4px;
        padding: 0px;
        min-width: 30px;
        margin: 0 1px;
        opacity: 0.55;
        color: @fg;
        font-size: 18px;
        font-weight: bold;
      }

      #workspaces button.active {
        color: @fg;
        border: 1px solid @border_act;
        opacity: 1.0;
        font-size: 18px;
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.25);
      }

      #workspaces button.empty {
        opacity: 0.15;
        font-size: 18px;
        color: @fg;
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.25);
      }

      #workspaces button.empty.active {
        font-size: 18px;
        color: @fg;
        opacity: 1.0;
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.25);
      }

      #workspaces button.empty:hover,
      #workspaces button:hover {
        background: @hover_bg;
        color: @hover_fg;
        opacity: 1.0;
      }

      #tray, #clock, #cpu, #memory, #backlight,
      #network, #bluetooth, #pulseaudio, #idle_inhibitor,
      #custom-nix, #custom-telegram, #custom-spotify, #custom-clash, #custom-bluetooth, #custom-battery, #custom-power,
      #group-volume, #group-brightness {
        min-width: 13px;
        margin-top: 2px;
        padding-left: 4px;
        padding-right: 4px;
      }

      #custom-nix { font-size: 18px; }

      #custom-telegram {
        font-size: 18px;
        color: @fg;
      }

      #custom-spotify {
        font-size: 18px;
        color: @fg;
      }

      #custom-clash {
        font-size: 18px;
        color: @fg;
      }

      #custom-bluetooth {
        font-size: 18px;
        color: @fg;
      }

      #custom-battery { font-size: 18px; }

      #custom-power {
        font-size: 18px;
        color: @fg;
      }

      #custom-power:hover {
        color: @fg_bright;
      }

      #pulseaudio-slider slider {
        min-height: 6px;
        min-width: 6px;
        border-radius: 50%;
        background: transparent;
        border: none;
        box-shadow: none;
        -gtk-icon-source: none;
      }

      #pulseaudio-slider trough {
        min-height: 3px;
        min-width: 64px;
        background-color: @border;
        border-radius: 2px;
      }

      #pulseaudio-slider highlight {
        background-color: @fg_bright;
        border-radius: 2px;
      }

      #backlight-slider slider {
        min-height: 6px;
        min-width: 6px;
        border-radius: 50%;
        background: transparent;
        border: none;
        box-shadow: none;
        -gtk-icon-source: none;
      }

      #backlight-slider trough {
        min-height: 3px;
        min-width: 64px;
        background-color: @border;
        border-radius: 2px;
      }

      #backlight-slider highlight {
        background-color: @fg_bright;
        border-radius: 2px;
      }

      .drawer-child {
        padding-right: 6px;
      }

      menu {
        background-color: @bg_mid;
        color: @fg;
        border: 1px solid @border;
        border-radius: 4px;
        padding: 3px 0px;
        font-family: 'CaskaydiaCove Nerd Font Propo';
        font-size: 18px;
      }

      menuitem {
        padding: 3px 10px;
        color: @fg;
      }

      menuitem:hover {
        background-color: @hover_bg;
        color: @hover_fg;
      }




      tooltip {
        padding: 4px 4px;
        background: @bg;
        font-size: 18px;
        border-radius: 4px;
        border: 1px solid rgba(255, 255, 255, 0.25);
      }

      tooltip label { color: @fg; }

      .hidden { opacity: 0; }


      #custom-separator {
        opacity: 0.2;
        padding-top: 5px;
        padding-left: 4px;
        padding-right: 4px;
        color: @border_inact;
      }

    '';

    settings.mainBar = {
      exclusive = true;
      reload_style_on_change = true;
      position = "top";
      width = 496;
      spacing = 0;
      margin-top = 0;

      modules-left = modulesLeft;
      modules-center = modulesCenter;
      modules-right = modulesRight;

      "custom/separator" = {
        format = "|";
        tooltip = false;
      };

      "custom/nix" = {
        format = "<span weight='heavy'></span>";
        on-click = "ghostty --class=com.mitchellh.ghostty-rebuild -e fish -c 'sudo nixos-rebuild switch --show-trace &| nom; exec fish'";
        on-click-right = "ghostty --class=com.mitchellh.ghostty-term";
        tooltip-format = "NixOS Rebuild";
      };

      "custom/power" = {
        format = "<span weight='heavy'></span>";
        on-click = "wlogout";
        tooltip-format = "Power menu";
      };

      "cpu" = {
        interval = 10;
        format = "<span weight='heavy'></span>";
        on-click = "ghostty --class=com.mitchellh.ghostty-btop -e btop";
      };

      "clock" = {
        format = "{:%H:%M}";
        format-alt = "{:%H:%M - %d/%m/%Y}";
        tooltip-format = "<span>{calendar}</span>";
        calendar = {
          mode = "month";
          mode-mon-col = 3;
          on-click-right = "mode";
          format = {
            month = "<span color='${p.bright_yellow}'><b>{}</b></span>";
            weekdays = "<span color='${p.accent_warm}'><b>{}</b></span>";
            today = "<span color='${p.fg_bright}'><b>{}</b></span>";
          };
        };
      };

      "network" = {
        format-icons = ["󰤯" "󰤟" "󰤢" "󰤥" "󰤨"];
        format = "{icon}";
        format-wifi = "{icon}";
        format-ethernet = "󰈀";
        format-disconnected = "󰤮";
        tooltip-format-wifi = "{essid} ({frequency} GHz)\nDown: {bandwidthDownBytes}  Up: {bandwidthUpBytes}";
        tooltip-format-ethernet = "Down: {bandwidthDownBytes}  Up: {bandwidthUpBytes}";
        tooltip-format-disconnected = "Disconnected";
        interval = 3;
        spacing = 1;
        # Left click → adw-network panel (libadwaita NetworkManager UI).
        # Mirrors the bluetooth slot which launches adw-bluetooth the
        # same way. PATH is provided by Home Manager session env.
        on-click = "adwaita-network";
      };

      "group/volume" = {
        orientation = "horizontal";
        drawer = {
          transition-duration = 500;
          transition-left-to-right = true;
          children-class = "drawer-child";
          click-to-reveal = false;
        };
        modules = ["pulseaudio#output" "pulseaudio/slider"];
      };

      "pulseaudio#output" = {
        format = "{icon}";
        format-muted = "󰖁";
        format-icons = {
          headphone = "";
          default = ["󰕿" "󰖀" "󰕾"];
        };
        max-volume = 100;
        scroll-step = 2;
        smooth-scrolling-threshold = 1;
        on-click-right = "pamixer -t";
        tooltip-format = "{volume}%";
      };

      "pulseaudio/slider" = {
        min = 0;
        max = 100;
        orientation = "horizontal";
      };

      "group/brightness" = {
        orientation = "horizontal";
        drawer = {
          transition-duration = 500;
          transition-left-to-right = true;
          children-class = "drawer-child";
          click-to-reveal = false;
        };
        modules = ["backlight" "backlight/slider"];
      };

      "backlight" = {
        device = "amdgpu_bl1";
        format = "<span weight='heavy'>󰃟</span>";
        tooltip-format = "{percent}%";
      };

      "backlight/slider" = {
        min = 0;
        max = 100;
        orientation = "horizontal";
        device = "amdgpu_bl1";
      };
    };
  };
}
