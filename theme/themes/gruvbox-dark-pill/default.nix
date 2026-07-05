# theme/themes/gruvox-dark-pill/default.nix — Gruvbox dark pill bar.
#
# Bottom-positioned pill-shape bar inspired by the ML4W/select
# dotfiles waybar spec. Same Gruvbox dark palette, different layout:
# bottom position, rounded pill shape, semi-transparent background,
# drawer groups, icon workspaces.
#
# Palette is shared with gruvbox-dark — only the structural overrides
# differ. This demonstrates the two-axis model: palette × layout.
_: {
  palette = import ../gruvbox-dark/palette.nix;
  wallpaper = ../../../assets/wallpaper.png;

  waybar = {
    position = "bottom";
    width = 0; # auto-width (0 = full width)
    spacing = 0;
    margins = {
      top = 0;
      bottom = 4;
      left = 6;
      right = 6;
    };
    borderRadius = 99; # pill

    # ── Module layout ────────────────────────────────────────────
    # Adapted from the ML4W spec. Session-specific modules (workspaces,
    # window, app toggles) and host-specific modules (battery) are
    # injected by the renderer / session / host layers.
    #
    # "custom/power" marks the injection point for host-specific right
    # modules (battery, power-draw, ultra-economy on lecoo).
    modulesLeft = [
      "custom/power"
      "hyprland/workspaces"
      "pulseaudio"
      "group/tools"
      "group/settings"
      "keyboard-state"
      "group/hardware"
      "custom/empty"
    ];
    modulesCenter = [
      "hyprland/window"
    ];
    modulesRight = [
      "custom/notification"
      "custom/language"
      "memory"
      "bluetooth"
      # Host modules (custom/battery etc.) injected here by renderer.
      "network"
      "clock"
      "tray"
    ];

    # ── Workspaces format ────────────────────────────────────────
    # Icon-based workspaces (Nerd Font glyphs) instead of numbers.
    # Active workspace = filled circle, default = empty circle.
    # Window-rewrite maps application classes to icons.
    workspaces = {
      format = "{icon}";
      format-icons = {
        active = "󰝥";
        default = "󰝦";
      };
      window-rewrite = {
        firefox = "󰈹";
        Ghostty = "󰞷";
        Slack = "󰒱";
        thunderbird = "󰇮";
        Spotify = "󰓇";
      };
      persistent-workspaces = {
        "1" = [];
        "2" = [];
        "3" = [];
        "4" = [];
        "5" = [];
        "6" = [];
      };
      show-special = false;
    };

    # ── Extra CSS ────────────────────────────────────────────────
    # Pill-shape: semi-transparent background, full rounding.
    # Overrides the base #waybar > box styling from the renderer.
    extraStyle = ''
      #waybar > box {
        background: rgba(29, 32, 33, 0.5);
        border: none;
        border-radius: 99px;
        box-shadow: 0px 2px 4px rgba(0, 0, 0, 0.4);
        margin: 0px 6px 4px 6px;
      }

      /* Drawer groups — pill-shaped child modules */
      .modules-left, .modules-right {
        margin: 0;
      }

      #workspaces {
        margin: 0 4px;
        padding: 0 4px;
        background-color: transparent;
        border-radius: 99px;
        box-shadow: none;
      }

      #workspaces button {
        border-radius: 50%;
        min-width: 20px;
        min-height: 20px;
        margin: 0 2px;
        border: none;
      }

      /* Pulseaudio — pill icon */
      #pulseaudio {
        border-radius: 99px;
        padding: 0 8px;
      }

      /* Tray — pill spacing */
      #tray {
        border-radius: 99px;
        padding: 0 4px;
      }

      /* Clock — pill */
      #clock {
        border-radius: 99px;
        padding: 0 8px;
      }

      /* Memory — pill */
      #memory {
        border-radius: 99px;
        padding: 0 8px;
      }

      /* Bluetooth — pill */
      #bluetooth {
        border-radius: 99px;
        padding: 0 8px;
      }

      /* Network — pill */
      #network {
        border-radius: 99px;
        padding: 0 8px;
      }

      /* Window title — pill */
      #window {
        border-radius: 99px;
        padding: 0 12px;
      }

      /* Drawer children — pill */
      .drawer-child {
        border-radius: 99px;
        padding: 0 6px;
      }

      /* Custom modules — pill */
      #custom-power,
      #custom-notification,
      #custom-language,
      #custom-clipboard,
      #custom-waybarthemes,
      #custom-tools,
      #custom-settings,
      #custom-system,
      #custom-empty,
      #custom-bluetooth,
      #custom-volume,
      #custom-brightness,
      #custom-cpu,
      #custom-battery,
      #custom-ultra-economy,
      #custom-power-draw,
      #custom-nix,
      #custom-separator {
        border-radius: 99px;
      }

      /* Keyboard state — pill */
      #keyboard-state {
        border-radius: 99px;
        padding: 0 4px;
      }

      #keyboard-state label {
        border-radius: 99px;
        padding: 0 4px;
      }
    '';
  };

  mako = {};
  rofi = {};
  ghostty = {};
}
