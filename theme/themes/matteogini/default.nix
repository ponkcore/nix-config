# theme/themes/matteogini/default.nix — matteogini-inspired bar.
#
# Minimalist top bar adapted from github.com/matteogini/dotfiles.
# Ultra-compact: JetBrainsMono 9px bold, transparent background,
# accent-colored active elements, drawer groups for stats and tools.
# Designed to pair with quickshell control center (phase 2).
#
# Palette: Gruvbox dark medium (shared with gruvbox-dark theme).
_: {
  palette = import ../gruvbox-dark/palette.nix;
  wallpaper = ../../../assets/wallpaper.png;

  # This theme uses quickshell as its bar backend, not waybar.
  # The quickshell config lives in pkgs/quickshell-config/.
  bar = "quickshell";

  waybar = {
    position = "top";
    width = 0;
    spacing = 1;
    margins = {
      top = 0;
      bottom = 0;
      left = 0;
      right = 0;
    };
    borderRadius = 0;
    height = 24;

    extendLayout = false;

    modulesLeft = [
      "group/stats"
      "group/spotify"
    ];
    modulesCenter = [
      "hyprland/workspaces"
    ];
    modulesRight = [
      "custom/battery"
      "group/tools"
    ];

    workspaces = {
      disable-scroll = true;
      all-outputs = true;
      format = "{name}";
    };

    style = ''
      * {
          font-family: 'JetBrainsMono Nerd Font';
          font-size: 9px;
          font-weight: bold;
          transition: all 0.3s ease;
          min-height: 0;
          border: none;
      }

      window#waybar {
          color: @fg;
          background-color: @bg;
      }

      window#waybar.hidden {
          opacity: 0;
      }

      button {
          box-shadow: none;
          border: none;
          border-radius: 0;
      }

      button:hover {
          background: rgba(255, 255, 255, 0.1);
          box-shadow: inset 0 -2px @accent;
      }

      button:active {
          padding-top: 3px;
          padding-bottom: 1px;
          background-color: rgba(255, 255, 255, 0.15);
      }

      #workspaces button {
          padding: 0 5px;
          color: alpha(@fg, 0.4);
          transition: all 200ms ease-in-out;
      }

      #workspaces button.active {
          min-width: 30px;
          color: @accent;
      }

      #workspaces {
          transition: all 200ms ease-in-out;
      }

      #window,
      #workspaces {
          margin: 0 2px;
      }

      #mode {
          background-color: rgba(255, 255, 255, 0.2);
      }

      #custom-power,
      #custom-notes,
      #clock,
      #battery,
      #cpu,
      #memory,
      #disk,
      #temperature,
      #backlight,
      #network,
      #pulseaudio,
      #tray,
      #custom-gpu,
      #custom-power_draw,
      #custom-updates,
      #custom-arrow-left,
      #custom-arrow-right,
      #custom-spotify-prev,
      #custom-spotify-play,
      #custom-spotify-next,
      #custom-spotify-text,
      #custom-bluetooth,
      #custom-volume,
      #custom-brightness,
      #custom-cpu,
      #custom-battery,
      #custom-ultra-economy,
      #custom-power-draw,
      #custom-notification,
      #custom-language,
      #custom-telegram,
      #custom-spotify,
      #custom-throne,
      #custom-nix,
      #custom-empty,
      #custom-separator,
      #custom-tools,
      #custom-settings,
      #custom-system,
      #custom-waybarthemes,
      #custom-clipboard {
          padding: 0 8px;
          color: @fg;
          margin: 2px 2px;
      }

      #battery {
          color: alpha(@fg, 0.4);
      }

      #battery.charging {
          color: @accent;
      }

      #battery.warning {
          color: @fg;
          background-color: rgba(255, 255, 255, 0.2);
      }

      #battery.critical:not(.charging) {
          background-color: @accent;
          color: @bg;
          animation-name: blink;
          animation-duration: 0.5s;
          animation-timing-function: steps(12);
          animation-iteration-count: infinite;
          animation-direction: alternate;
      }

      @keyframes blink {
          to {
              background-color: @fg;
              color: @bg;
          }
      }

      #network.disconnected {
          background-color: alpha(@accent, 0.5);
          color: @bg;
      }

      #pulseaudio.muted {
          background-color: rgba(255, 255, 255, 0.1);
          color: alpha(@fg, 0.5);
      }

      #temperature.critical {
          background-color: @accent;
          color: @bg;
      }

      #idle_inhibitor.activated {
          background-color: @accent;
          color: @bg;
      }

      #custom-power {
          margin-right: 4px;
          background-color: transparent;
          color: @accent;
      }

      #scratchpad {
          background-color: rgba(255, 255, 255, 0.1);
      }

      menu {
          background: alpha(@bg, 0.8);
          color: @fg;
      }

      menuitem {
          color: @fg;
      }

      menuitem:hover {
          background: alpha(@accent, 0.3);
      }

      #custom-spotify-prev,
      #custom-spotify-play,
      #custom-spotify-next,
      #custom-spotify-text {
          padding: 0 4px;
          color: @fg;
          margin: 2px 0px;
      }

      #custom-spotify-play {
          color: @accent;
          padding: 0 6px;
      }

      #custom-spotify-text {
          padding-left: 6px;
          padding-right: 8px;
          color: alpha(@fg, 0.85);
      }

      #custom-throne:not(.running):not(.vpn-active-ac):not(.vpn-active-battery) {
          color: @border_inact;
      }

      @keyframes throne-shimmer {
          0%   { color: @warning; }
          50%  { color: @bright_magenta; }
          100% { color: @warning; }
      }

      #custom-throne.vpn-active-ac {
          animation: throne-shimmer 6s ease-in-out infinite;
      }

      #custom-throne.vpn-active-battery {
          color: @warning;
      }

      #custom-telegram:not(.running),
      #custom-spotify:not(.running) {
          color: @border_inact;
      }

      #custom-ultra-economy {
          color: @border_inact;
      }

      #custom-ultra-economy.on {
          color: @warning;
      }

      #custom-battery.low {
          color: @red;
      }
    '';
  };

  mako = {};
  rofi = {};
  ghostty = {};
}
