# theme/waybar/default.nix — compositor-agnostic waybar renderer.
#
# Reads structural parameters (position, margins, border-radius, module
# layout, extra CSS) from the active theme attrset (`theme.waybar.*`)
# and generates the waybar config + CSS from the palette (`p`).
#
# This is a RENDERER, not a config. To change the bar layout, create a
# new theme in theme/themes/<name>/default.nix and set it as active in
# theme/default.nix. Do not hardcode layout values here.
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
# Composition: the theme provides the base module layout; this renderer
# extends it with session/host-specific modules. If a module in the
# list has no definition (because no session/host supplied it) waybar
# silently skips it.
{
  lib,
  p,
  theme,
  cpu-mem,
  volume-status,
  brightness-status,
  notification-toggle,
  notification-status,
  update-check,
  theme-select,
  desktops ? [],
  hostname ? "",
  pkgs,
  ...
}: let
  hasHyprland = builtins.elem "hyprland" desktops;
  isLecoo = hostname == "lecoo";

  # Shorthand for the waybar section of the active theme.
  wb = theme.waybar;
  m = wb.margins;

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

  # ── Module layout ──────────────────────────────────────────────────
  # The theme provides the base slot order. The renderer extends it
  # with session-specific modules (Hyprland IPC app toggles) and
  # host-specific modules (lecoo battery, power-draw, ultra-economy).
  #
  # A theme can set `extendLayout = false` to disable auto-extension
  # and take full control of the module layout. This is used by
  # themes that define a complete layout (e.g. pill theme with
  # drawer groups).
  #
  # For modulesRight, host-specific modules are injected before
  # "custom/power" — the injection point is found by splitting the
  # theme's list at that element. This lets a theme freely rearrange
  # the right side as long as "custom/power" marks where host modules
  # go.

  extendLayout = wb.extendLayout or true;

  modulesLeft =
    wb.modulesLeft
    ++ lib.optionals (extendLayout && hasHyprland) [
      "custom/language"
      "custom/separator"
      "custom/telegram"
      "custom/spotify"
      "custom/throne"
      "custom/separator"
      "custom/bluetooth"
      "network"
      "custom/separator"
      "custom/brightness"
      "custom/volume"
      "custom/separator"
    ];

  modulesCenter = lib.optionals hasHyprland wb.modulesCenter;

  # Split theme's modulesRight at "custom/power" to inject host modules.
  # When extendLayout is false the theme manages its own full layout,
  # including host modules — skip injection entirely.
  modulesRight = let
    splitAt = pred: list: let
      go = acc: remaining:
        if remaining == []
        then {
          pre = acc;
          post = [];
        }
        else if pred (lib.head remaining)
        then {
          pre = acc;
          post = remaining;
        }
        else go (acc ++ [(lib.head remaining)]) (lib.tail remaining);
    in
      go [] list;
    split = splitAt (mod: mod == "custom/power") wb.modulesRight;
  in
    if extendLayout
    then
      split.pre
      ++ lib.optionals isLecoo [
        "custom/ultra-economy"
        "custom/separator"
        "custom/power-draw"
        "custom/separator"
        "custom/battery"
        "custom/separator"
      ]
      ++ lib.optionals (!isLecoo) ["battery"]
      ++ split.post
    else wb.modulesRight;
in {
  programs.waybar = {
    enable = true;
    systemd.enable = true;

    style = let
      # Color definitions shared by all themes — always emitted first
      # so CSS @define-color variables resolve in both base and custom
      # styles.
      colorDefs = ''
        @define-color bg_dark ${p.bg_dark};
        @define-color bg ${p.bg};
        @define-color bg_soft ${p.bg_soft};
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
        @define-color bright_orange ${p.bright_orange};
        @define-color bright_magenta ${p.bright_magenta};
      '';

      # If the theme provides a full CSS string, use it instead of the
      # base style. This lets a theme define a completely different
      # visual language (e.g. pill bar with minimal styling) without
      # fighting the base CSS specificity.
      baseStyle = ''
          * {
          border-radius: 0;
          border: none;
          text-shadow: none;
          padding: 0;
          min-height: 0;
          font-family: 'DepartureMono Nerd Font Propo';
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
             solid bg_dark clipped to padding-box (interior fill), gradient
             clipped to border-box (border ring).  border: transparent
             lets the gradient show through the 2px border area. */
          background:
            linear-gradient(@bg_dark, @bg_dark) padding-box,
            linear-gradient(45deg, rgba(250, 189, 47, 0.933), rgba(211, 134, 155, 0.933)) border-box;
          margin: ${toString m.top}px ${toString m.right}px ${toString m.bottom}px ${toString m.left}px;
          padding: 0px;
          border: 2px solid transparent;
          border-radius: ${toString wb.borderRadius}px;
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
          background-color: @bg_soft;
          border-radius: 4px;
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
        #custom-nix, #custom-telegram, #custom-spotify, #custom-throne, #custom-bluetooth, #custom-cpu, #custom-battery, #custom-ultra-economy, #custom-power, #custom-power-draw,
        #custom-volume, #custom-brightness,
        #group-volume, #group-brightness {
          min-width: 13px;
          margin-top: 2px;
          padding-left: 4px;
          padding-right: 4px;
        }

        /* All icon modules use CommitMono for consistent glyph rendering.
           Text modules (clock, workspaces, language, ECO, CPU, battery
           values) inherit DepartureMono from the global `*` selector.
           Volume and brightness use Pango markup for the icon (CommitMono)
           so the value text stays DepartureMono. */
        #network, #bluetooth {
          font-family: 'CommitMono Nerd Font Propo';
        }

        #custom-nix { font-size: 18px; font-family: 'CommitMono Nerd Font Propo'; }

        #custom-language {
          font-size: 16px;
          font-weight: normal;
          color: @fg_bright;
        }

        #custom-telegram  { font-size: 18px; color: @fg; font-family: 'CommitMono Nerd Font Propo'; }
        #custom-spotify   { font-size: 18px; color: @fg; font-family: 'CommitMono Nerd Font Propo'; }
        #custom-throne    { font-size: 18px; color: @fg; font-family: 'CommitMono Nerd Font Propo'; }

        /* App-toggle: when not running, dim to inactive workspace
           button color. When running — full @fg color.
           vpn-active-* classes imply running, so they're excluded
           from the dim rule.
           No glow / pulse. */
        #custom-telegram:not(.running),
        #custom-spotify:not(.running),
        #custom-throne:not(.running):not(.vpn-active-ac):not(.vpn-active-battery) {
          color: @border_inact;
        }

        /* Throne VPN-active state — TUN interface is up (sing-box
           running). Visual depends on power state (class emitted by
           throne-status script):
             .vpn-active-ac       → animated shimmer yellow ↔ magenta
             .vpn-active-battery  → static bright_yellow */
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

        #custom-bluetooth {
          font-size: 18px;
          color: @fg;
          font-family: 'CommitMono Nerd Font Propo';
        }

        #custom-cpu { font-size: 16px; }

        #custom-battery { font-size: 16px; }

        /* Battery low warning — exec script emits `"class":"low"`
           when discharging below 20 %; waybar renders that as a CSS
           class on the element, so this selector kicks in. */
        #custom-battery.low { color: @red; }

        #custom-ultra-economy {
          font-size: 16px;
          font-weight: normal;
          color: @border_inact;
        }

        #custom-ultra-economy.on {
          color: @warning;
        }

        /* Power-draw: normal @fg color in all states. */

        #custom-power {
          font-size: 18px;
          color: @fg;
          font-family: 'CommitMono Nerd Font Propo';
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
          font-family: 'DepartureMono Nerd Font Propo';
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
          font-family: 'DepartureMono Nerd Font Propo';
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

        ${wb.extraStyle}
      '';

      # Full style overrides baseStyle entirely when provided by theme.
      fullStyle = wb.style or null;
    in
      if fullStyle != null
      then "${colorDefs}\n${fullStyle}"
      else "${colorDefs}\n${baseStyle}";

    settings.mainBar = {
      exclusive = true;
      reload_style_on_change = true;
      position = wb.position;
      width = wb.width;
      height = wb.height or 0;
      spacing = wb.spacing;
      margin-top = m.top;
      margin-bottom = m.bottom;
      margin-left = m.left;
      margin-right = m.right;

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
        on-click = "wlogout --buttons-per-row 4 --margin-left 60 --margin-right 60 --column-spacing 6";
        tooltip = false;
      };

      # Custom CPU+RAM widget — built-in `cpu` exposes per-core
      # data only inside `format`, not `tooltip-format`. We use the
      # cpu-mem script to emit a JSON tooltip with avg CPU + RAM.
      "custom/cpu" = {
        format = "{text}";
        exec = "${cpu-mem}/bin/cpu-mem";
        return-type = "json";
        interval = 5;
        tooltip = false;
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

      "custom/volume" = {
        exec = "${volume-status}/bin/volume-status";
        return-type = "json";
        interval = 1;
        format = "{text}";
        on-click = "pamixer -t";
        on-scroll-up = "pamixer -i 1";
        on-scroll-down = "pamixer -d 1";
        tooltip = false;
      };

      # Builtin pulseaudio module kept for reference — replaced by
      # custom/volume above for padded 2-digit display + font control.
      # To restore: replace custom/volume in modules-right with
      # group/volume and uncomment the group + pulseaudio configs below.
      # "group/volume" = {
      #   orientation = "horizontal";
      #   drawer = {
      #     transition-duration = 500;
      #     transition-left-to-right = true;
      #     children-class = "drawer-child";
      #     click-to-reveal = false;
      #   };
      #   modules = ["pulseaudio#output" "pulseaudio/slider"];
      # };
      #
      # "pulseaudio#output" = {
      #   format = "{icon} {volume}%";
      #   format-muted = "󰖁";
      #   format-icons = {
      #     headphone = "";
      #     default = ["󰕿" "󰖀" "󰕾"];
      #   };
      #   max-volume = 99;
      #   scroll-step = 2;
      #   smooth-scrolling-threshold = 1;
      #   on-click-right = "pamixer -t";
      #   tooltip = false;
      # };
      #
      # "pulseaudio/slider" = {
      #   min = 0;
      #   max = 100;
      #   orientation = "horizontal";
      # };

      "custom/brightness" = {
        exec = "${brightness-status}/bin/brightness-status";
        return-type = "json";
        interval = 1;
        format = "{text}";
        on-scroll-up = "${pkgs.brightnessctl}/bin/brightnessctl -d amdgpu_bl1 set +1%";
        on-scroll-down = "${pkgs.brightnessctl}/bin/brightnessctl -d amdgpu_bl1 set 1%-";
        tooltip = false;
      };

      # Builtin backlight module kept for reference — replaced by
      # custom/brightness above for padded 2-digit display + font control.
      # "group/brightness" = {
      #   orientation = "horizontal";
      #   drawer = {
      #     transition-duration = 500;
      #     transition-left-to-right = true;
      #     children-class = "drawer-child";
      #     click-to-reveal = false;
      #   };
      #   modules = ["backlight" "backlight/slider"];
      # };
      #
      # "backlight" = {
      #   device = "amdgpu_bl1";
      #   format = "<span weight='heavy'>󰃟</span> {percent}%";
      #   tooltip = false;
      # };
      #
      # "backlight/slider" = {
      #   min = 0;
      #   max = 100;
      #   orientation = "horizontal";
      #   device = "amdgpu_bl1";
      # };

      "custom/language" = {
        exec = "${hyprland-language}/bin/hyprland-language";
        return-type = "json";
        tooltip = false;
      };

      # ── Built-in modules (used by pill theme) ───────────────────
      # These are here so the pill theme can reference them in its
      # module layout without duplicating definitions. The default
      # gruvbox-dark theme doesn't use them — it uses custom/*
      # equivalents. Both sets coexist; waybar ignores undefined
      # modules in the layout list.

      "pulseaudio" = {
        format = "{icon}";
        format-bluetooth = "󰂰";
        format-muted = "󰖁";
        format-icons = {
          headphones = "󰋋";
          bluetooth = "󰥰";
          handsfree = "󰋌";
          headset = "󰋎";
          phone = "󰏲";
          portable = "󰓃";
          car = "󰄋";
          default = ["󰕿" "󰖀" "󰕾"];
        };
        justify = "center";
        on-click = "pamixer -t";
        on-click-right = "pwvucontrol";
        tooltip-format = "{volume}%";
      };

      "bluetooth" = {
        format-on = "󰂯";
        format-off = "";
        format-disabled = "󰂲";
        format-connected = "󰂴";
        format-connected-battery = "{device_battery_percentage}% 󰂴";
        tooltip-format = "{controller_alias}\t{controller_address}\n\n{num_connections} connected";
        tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{num_connections} connected\n\n{device_enumerate}";
        tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
        tooltip-format-enumerate-connected-battery = "{device_alias}\t{device_address}\t{device_battery_percentage}%";
        on-click = "blueman-manager";
      };

      "battery" = {
        interval = 1;
        states = {
          good = 95;
          warning = 30;
          critical = 20;
        };
        format = "{icon} ";
        format-charging = "{capacity}% 󰂄 ";
        format-plugged = "{capacity}% 󰂄";
        format-alt = "{time} {icon}";
        format-icons = ["󰁻" "󰁼" "󰁾" "󰂀" "󰂂" "󰁹"];
      };

      "memory" = {
        format = "󰍛 {used}GB";
        interval = 10;
        on-click = "ghostty --class=com.mitchellh.ghostty-btop -e btop";
      };

      "disk" = {
        format = "󰋊 {percentage_used}%";
        path = "/";
        interval = 30;
      };

      "cpu" = {
        format = "󰓅 {usage}%";
        interval = 5;
      };

      "keyboard-state" = {
        numlock = false;
        capslock = true;
        format = "{name} {icon}";
        format-icons = {
          locked = "󰌾";
          unlocked = "󰌿";
        };
      };

      "tray" = {
        icon-size = 16;
        spacing = 10;
      };

      # ── Drawer groups ────────────────────────────────────────────
      # A single group/tools definition — themes pick which modules
      # go inside via their layout. The default here is the matteogini
      # layout; pill theme used its own which is now removed.

      "group/tools" = {
        orientation = "inherit";
        drawer = {
          transition-duration = 300;
          transition-right-to-left = false;
        };
        modules = [
          "custom/arrow-left"
          "pulseaudio"
          "pulseaudio#microphone"
          "bluetooth"
          "tray"
          "clock"
        ];
      };

      "group/settings" = {
        orientation = "inherit";
        drawer = {
          transition-duration = 300;
          children-class = "not-memory";
          transition-left-to-right = true;
        };
        modules = ["custom/settings" "custom/waybarthemes"];
      };

      "group/hardware" = {
        orientation = "inherit";
        drawer = {
          transition-duration = 300;
          children-class = "not-memory";
          transition-left-to-right = false;
        };
        modules = ["custom/system" "disk" "cpu" "memory"];
      };

      # ── Drawer handle modules ───────────────────────────────────

      "custom/tools" = {
        format = "󰽘";
        tooltip = false;
      };

      "custom/settings" = {
        format = "󰒓";
        tooltip = false;
      };

      "custom/system" = {
        format = "󰇄";
        tooltip = false;
      };

      # ── Custom modules ───────────────────────────────────────────

      "custom/clipboard" = {
        format = "󰅇";
        on-click = "cliphist list | ${pkgs.rofi}/bin/rofi -dmenu -i | cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy";
        tooltip-format = "Clipboard";
      };

      "custom/waybarthemes" = {
        format = "󰏘";
        on-click = "${theme-select}/bin/theme-select";
        tooltip-format = "Switch theme";
      };

      "custom/empty" = {
        format = "";
      };

      "custom/notification" = {
        exec = "${notification-status}/bin/notification-status";
        return-type = "json";
        interval = 1;
        signal = 8;
        format = "{text}";
        on-click = "${notification-toggle}/bin/notification-toggle";
        tooltip = false;
      };

      # ── Matteogini-specific modules ──────────────────────────────

      "group/stats" = {
        orientation = "inherit";
        drawer = {
          transition-duration = 300;
          transition-left-to-right = false;
        };
        modules = [
          "custom/arrow-right"
          "custom/power-draw"
          "temperature"
          "custom/updates"
          "custom/notes"
        ];
      };

      "group/spotify" = {
        orientation = "horizontal";
        modules = [
          "custom/spotify-prev"
          "custom/spotify-play"
          "custom/spotify-next"
          "custom/spotify-text"
        ];
      };

      "custom/arrow-left" = {
        format = " ";
        tooltip = false;
      };

      "custom/arrow-right" = {
        format = " ";
        tooltip = false;
      };

      "custom/updates" = {
        format = "󰮯 {} ";
        exec = "${update-check}/bin/update-check";
        tooltip = false;
      };

      "custom/notes" = {
        format = "󰢉";
        tooltip = "Configs";
        on-click = "${pkgs.ghostty}/bin/ghostty --class=com.mitchellh.ghostty-config -e fish -c 'cd /etc/nixos && nvim'";
      };

      "temperature" = {
        thermal-zone = "x86_pkg_temp";
        critical-threshold = 80;
        format = " {temperatureC}° ";
        interval = 10;
      };

      "pulseaudio#microphone" = {
        format = "{format_source}";
        format-source = "󰍎 ";
        format-source-muted = "󰍱 ";
        on-click = "pamixer --default-source -t";
        on-click-right = "pwvucontrol";
        tooltip = false;
      };

      "custom/spotify-prev" = {
        format = "{}";
        exec = "echo '󰒮'";
        exec-if = "pgrep spotify || pgrep spotify-client";
        interval = 2;
        on-click = "${pkgs.playerctl}/bin/playerctl --player=spotify previous";
        tooltip = false;
      };

      "custom/spotify-play" = {
        format = "{}";
        exec = "if [ \"$(${pkgs.playerctl}/bin/playerctl --player=spotify status 2>/dev/null)\" = \"Playing\" ]; then echo '󰏤'; else echo '󰐊'; fi";
        exec-if = "pgrep spotify || pgrep spotify-client";
        interval = 1;
        on-click = "${pkgs.playerctl}/bin/playerctl --player=spotify play-pause";
        tooltip = false;
      };

      "custom/spotify-next" = {
        format = "{}";
        exec = "echo '󰒭'";
        exec-if = "pgrep spotify || pgrep spotify-client";
        interval = 2;
        on-click = "${pkgs.playerctl}/bin/playerctl --player=spotify next";
        tooltip = false;
      };

      "custom/spotify-text" = {
        format = " {}";
        max-length = 35;
        exec = "${pkgs.playerctl}/bin/playerctl --player=spotify metadata --format '{{title}} - {{artist}}' 2>/dev/null";
        exec-if = "pgrep spotify || pgrep spotify-client";
        interval = 2;
        tooltip = false;
      };
    };
  };
}
