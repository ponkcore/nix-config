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
#   - custom/throne        (uses hyprctl special workspaces)
#
# Slots that depend on host hardware live in hosts/<name>/home/waybar.nix:
#   - custom/battery       (Lecoo-aware: merges system battery with EC
#                           charge mode via the lecoo-ctrl daemon)
#
# Composition: this file declares the slot order; missing fragments are
# filtered out at activation time so a host that opts out of a slot
# does not need to redefine the layout.
{
  lib,
  p,
  cpu-mem,
  desktops ? [],
  hostname ? "",
  pkgs,
  ...
}: let
  hasHyprland = builtins.elem "hyprland" desktops;
  isLecoo = hostname == "lecoo";

  # Waybar's native `hyprland/language` renders `...` on the current
  # Hyprland/Waybar pair, despite `hyprctl devices -j` exposing the
  # active keymap correctly. Use the Hyprland event socket directly:
  # print once at startup, then re-emit on `activelayout` events. No
  # polling in the steady state.
  hyprland-language = pkgs.writeShellScriptBin "hyprland-language" ''
    keyboard="at-translated-set-2-keyboard"

    emit() {
      keymap="$(${pkgs.hyprland}/bin/hyprctl devices -j \
        | ${pkgs.jq}/bin/jq -r --arg keyboard "$keyboard" \
            '[.keyboards[] | select(.name == $keyboard) | .active_keymap][0] // ""')"

      case "$keymap" in
        *Russian*) text="RU"; class="ru" ;;
        *English*|*US*) text="EN"; class="en" ;;
        *) text="??"; class="unknown" ;;
      esac

      ${pkgs.jq}/bin/jq -cn \
        --arg text "$text" \
        --arg tooltip "$keymap" \
        --arg class "$class" \
        '{text: $text, tooltip: $tooltip, class: $class}'
    }

    emit

    sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
    if [ -S "$sock" ]; then
      ${pkgs.socat}/bin/socat -u UNIX-CONNECT:"$sock" - \
        | while IFS= read -r event; do
            case "$event" in
              activelayout*) emit ;;
            esac
          done
    else
      # Fallback for unusual launches where the Hyprland event socket is
      # absent from the environment; still bounded and low-cost.
      while true; do
        ${pkgs.coreutils}/bin/sleep 1
        emit
      done
    fi
  '';

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
      "custom/throne"
      "custom/keepassxc"
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
    ]
    ++ lib.optionals hasHyprland ["custom/language"]
    ++ [
      "group/brightness"
      "group/volume"
      "custom/bluetooth"
      "network"
      "custom/cpu"
    ]
    ++ lib.optionals isLecoo [
      "custom/battery"
      "custom/ultra-economy"
    ]
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
        /* Gradient border matching Hyprland general.col.active_border:
           bright_yellow (#fabd2f) -> bright_magenta (#d3869b) at 45deg,
           2px wide, alpha ee (0.933).  Layered background technique:
           solid bg_mid clipped to padding-box (interior fill), gradient
           clipped to border-box (border ring).  border: transparent
           lets the gradient show through the 2px border area. */
        background:
          linear-gradient(@bg_mid, @bg_mid) padding-box,
          linear-gradient(45deg, rgba(250, 189, 47, 0.933), rgba(211, 134, 155, 0.933)) border-box;
        margin: 0px 6px 3px 6px;
        padding: 0px;
        border: 2px solid transparent;
        border-radius: 4px;
        box-shadow: 0px 1px 2px rgba(0, 0, 0, 1);
        font-weight: normal;
        font-size: 16px;
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

      /* `.active` = visible on any monitor (waybar's per-monitor
         pinning lights up two buttons at once on a dual-output
         setup). `.focused` = the workspace the user's pointer/
         keyboard focus is on right now. The visible style is
         shared by both, but the focused button gets the brighter
         border so the user can tell which screen they are on at a
         glance. */
      #workspaces button.active,
      #workspaces button.focused,
      #workspaces button.visible {
        color: @fg;
        border: 1px solid @border_act;
        opacity: 1.0;
        font-size: 18px;
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.25);
      }

      #workspaces button.focused {
        border: 1px solid @fg_bright;
      }

      #workspaces button.empty {
        opacity: 0.15;
        font-size: 18px;
        color: @fg;
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.25);
      }

      #workspaces button.empty.active,
      #workspaces button.empty.focused,
      #workspaces button.empty.visible {
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
      #custom-language, #network, #bluetooth, #pulseaudio, #idle_inhibitor,
      #custom-nix, #custom-telegram, #custom-spotify, #custom-throne, #custom-keepassxc, #custom-bluetooth, #custom-cpu, #custom-battery, #custom-ultra-economy, #custom-power,
      #group-volume, #group-brightness {
        min-width: 13px;
        margin-top: 2px;
        padding-left: 4px;
        padding-right: 4px;
      }

      #custom-nix { font-size: 18px; }

      #custom-language {
        font-size: 13px;
        font-weight: 700;
        color: @fg_bright;
      }

      #custom-telegram  { font-size: 18px; color: @fg; }
      #custom-spotify   { font-size: 18px; color: @fg; }
      #custom-throne    { font-size: 18px; color: @fg; }
      #custom-keepassxc { font-size: 18px; color: @fg; }

      /* App-toggle running indicator — exec script (app-status,
         home/desktop/sessions/hyprland/scripts.nix) emits
         `"class":"running"` when a Hyprland window of the matching
         class exists. The glow pulses between 1 px and 4 px blur
         radius — stays well inside the module's 4 px horizontal
         padding so it never gets clipped. Glyph colour stays at
         @fg; the animated shadow does the visual work. */
      /* Animate the shadow's alpha channel, not its blur radius —
         keeps the glyph itself rasterised without any halo when
         the pulse is at its low point. fbf1c7 = @fg_bright. */
      @keyframes app-glow-pulse {
        0%   { text-shadow: 0 0 3px rgba(251, 241, 199, 0); }
        50%  { text-shadow: 0 0 3px rgba(251, 241, 199, 1); }
        100% { text-shadow: 0 0 3px rgba(251, 241, 199, 0); }
      }

      #custom-telegram.running,
      #custom-spotify.running,
      #custom-throne.running,
      #custom-keepassxc.running {
        animation: app-glow-pulse 2s ease-in-out infinite;
      }

      #custom-bluetooth {
        font-size: 18px;
        color: @fg;
      }

      #custom-cpu { font-size: 18px; }

      #custom-battery { font-size: 18px; }

      /* Battery low warning — exec script emits `"class":"low"`
         when discharging below 20 %; waybar renders that as a CSS
         class on the element, so this selector kicks in. */
      #custom-battery.low { color: @red; }

      #custom-ultra-economy {
        font-size: 18px;
        color: @fg;
      }

      #custom-ultra-economy.on {
        color: @bright_green;
        text-shadow: 0 0 4px @bright_green;
      }

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

      #pulseaudio-slider highlight,
      scale#pulseaudio-slider trough highlight,
      scale#pulseaudio-slider highlight progress {
        background-color: @accent;
        background-image: none;
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

      #backlight-slider highlight,
      scale#backlight-slider trough highlight,
      scale#backlight-slider highlight progress {
        background-color: @accent;
        background-image: none;
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

      /* Tooltip popups — secondary surface lighter than the bar to
         read as "auxiliary card on top of the bar". Hyprland does
         not give popup-windows transparency to the compositor, so
         CSS alpha just composites against an opaque base — values
         below 1.0 visibly darken/lighten but never let through
         what is below.
         No corner radius: any rounding cuts into the opaque popup
         window and the compositor's dark default fill leaks through
         in the cut corners as 1-2 px black points. Square corners
         are the only artefact-free option. */
      tooltip {
        background: rgba(120, 113, 108, 0.55);
        border-radius: 0;
        border: 2px solid rgba(255, 255, 255, 0.45);
        padding: 0;
      }

      tooltip label {
        background: transparent;
        color: @fg_bright;
        padding: 6px 10px;
        /* Same family as the bar itself for tonal consistency.
           Bold + 12 px reads as "footnote-tier" auxiliary text
           against the bar's 16-18 px. */
        font-family: 'CaskaydiaCove Nerd Font Propo';
        font-size: 12px;
        font-weight: 700;
      }

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
        tooltip = false;
      };

      "custom/power" = {
        format = "<span weight='heavy'></span>";
        on-click = "wlogout --buttons-per-row 2";
        tooltip = false;
      };

      # Custom CPU+RAM widget — built-in `cpu` exposes per-core
      # data only inside `format`, not `tooltip-format`. We use the
      # cpu-mem script to emit a JSON tooltip with avg CPU + RAM.
      "custom/cpu" = {
        format = "<span weight='heavy'>󰑹</span>";
        exec = "${cpu-mem}/bin/cpu-mem";
        return-type = "json";
        interval = 5;
        on-click = "ghostty --class=com.mitchellh.ghostty-btop -e btop";
      };

      "clock" = {
        format = "{:%H:%M}";
        format-alt = "{:%H:%M - %d/%m/%Y}";
        tooltip = false;
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

        tooltip-format-wifi = "{essid}";
        tooltip-format-ethernet = "Ethernet";
        tooltip-format-disconnected = "Disconnected";
        interval = 3;
        spacing = 1;
        # on-click is set by the active session fragment so the click
        # behaviour can hook into compositor IPC. The Hyprland fragment
        # wires it to network-toggle (special-workspace hide/show
        # mirror of custom/bluetooth). Sessions that do not override it
        # leave the slot click-through.
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
        tooltip = false;
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
        tooltip = false;
      };

      "backlight/slider" = {
        min = 0;
        max = 100;
        orientation = "horizontal";
        device = "amdgpu_bl1";
      };

      "custom/language" = {
        exec = "${hyprland-language}/bin/hyprland-language";
        return-type = "json";
        tooltip = false;
      };
    };
  };
}
