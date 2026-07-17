# rofi.nix — clipboard picker and fallback drun launcher (Wayland-aware fork).
#
# Structural config is Nix-owned (window layout, keybindings, modi).
# Colour palette is generated at runtime by `caelestia-rofi-sync` from
# Caelestia's scheme.json — no Nix-side colour interpolation.
#
# Primary launcher is Caelestia shell (SUPER+R); rofi is used for
# clipboard history (SUPER+C -> cliphist list | rofi -dmenu).
{pkgs, ...}: {
  # caelestia-rofi-sync — reads Caelestia scheme.json and generates
  # ~/.local/share/rofi/themes/palette.rasi with matching colours.
  # Called at login (HM activation) and on every scheme change
  # (via Caelestia postHook in cli.json).
  home.packages = [
    (pkgs.writeShellScriptBin "caelestia-rofi-sync" ''
            set -eu

            SCHEME="$HOME/.local/state/caelestia/scheme.json"
            OUT="$HOME/.local/share/rofi/themes/palette.rasi"

            [ -f "$SCHEME" ] || exit 0

            JQ="${pkgs.jq}/bin/jq"

            # hex (RRGGBB, with or without #) -> rasi rgba(R, G, B, 100%)
            hex2rasi() {
                local hex="''${1#\#}"
                local r=$((16#''${hex:0:2}))
                local g=$((16#''${hex:2:2}))
                local b=$((16#''${hex:4:2}))
                echo "rgba($r, $g, $b, 100%)"
            }

            base=$($JQ -r '.colours.base' "$SCHEME")
            text=$($JQ -r '.colours.text' "$SCHEME")
            subtext1=$($JQ -r '.colours.subtext1' "$SCHEME")
            subtext0=$($JQ -r '.colours.subtext0' "$SCHEME")
            primary=$($JQ -r '.colours.primary' "$SCHEME")
            red=$($JQ -r '.colours.red' "$SCHEME")
            surface2=$($JQ -r '.colours.surface2' "$SCHEME")

            bg=$(hex2rasi "$base")
            fg=$(hex2rasi "$text")
            fg_dim=$(hex2rasi "$subtext1")
            fg_bright=$(hex2rasi "$text")
            accent=$(hex2rasi "$primary")
            border_clr=$(hex2rasi "$subtext0")
            urgent=$(hex2rasi "$red")
            selected=$(hex2rasi "$surface2")

            mkdir -p "$(dirname "$OUT")"
            rm -f "$OUT"
            cat > "$OUT" <<RASI
      * {
          bg:       $bg;
          fg:       $fg;
          fg-dim:   $fg_dim;
          fg-bright:$fg_bright;
          accent:   $accent;
          border-clr:$border_clr;
          urgent:   $urgent;
          selected: $selected;

          background-color: @bg;
          foreground: @fg;
          border-color: @border-clr;
          spacing: 0;
          padding: 0;
      }

      window {
          width: 680px;
          padding: 12px;
          border-radius: 5px;
          background-color: @bg;
          border: 2px solid;
          border-color: @border-clr;
      }

      mainbox {
          padding: 0px;
      }

      inputbar {
          padding: 8px 12px;
          margin: 0px 0px 8px 0px;
          border-radius: 5px;
          border: 2px solid;
          border-color: @border-clr;
          background-color: @bg;
          children: [prompt, entry];
      }

      prompt {
          enabled: true;
          padding: 0px 8px 0px 0px;
          background-color: transparent;
          text-color: @accent;
      }

      entry {
          padding: 0px;
          background-color: transparent;
          text-color: @fg;
          cursor: text;
          placeholder: "Search...";
          placeholder-color: @fg-dim;
      }

      listview {
          padding: 0px;
          border-radius: 0px;
          background-color: transparent;
          dynamic: true;
          scrollbar: true;
          spacing: 2px;
      }

      scrollbar {
          enabled: true;
          width: 4px;
          padding: 0;
          background-color: @bg;
          handle-color: @selected;
          handle-width: 4px;
          border-radius: 5px;
      }

      element {
          padding: 8px 12px;
          border-radius: 5px;
          background-color: transparent;
          text-color: @fg;
          cursor: pointer;
          spacing: 8px;
      }

      element-icon {
          size: 1em;
          vertical-align: 0.5;
          text-color: inherit;
      }

      element-text {
          background-color: transparent;
          text-color: inherit;
          vertical-align: 0.5;
      }

      element selected {
          background-color: @selected;
          text-color: @fg-bright;
          border: 0px;
          border-radius: 5px;
      }

      element selected.active {
          background-color: @urgent;
          text-color: @bg;
      }

      element urgent {
          text-color: @urgent;
      }

      message {
          padding: 8px 12px;
          margin: 4px 0px 0px 0px;
          background-color: transparent;
      }

      error-message {
          padding: 8px 12px;
          margin: 4px 0px 0px 0px;
          background-color: @bg;
          border-radius: 5px;
      }

      textbox {
          background-color: transparent;
          text-color: @fg-dim;
      }

      message-text, error-message-text {
          background-color: transparent;
          text-color: @fg-dim;
      }
      RASI
    '')
  ];

  programs.rofi = {
    enable = true;
    theme = "palette";
    terminal = "ghostty";
    extraConfig = {
      modi = "drun";
      show-icons = true;
      icon-theme = "Papirus";
      matching = "fuzzy";
      sort = true;
      sorting-method = "fzf";
      steal-focus = true;
    };
  };
}
