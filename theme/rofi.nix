# rofi.nix — application launcher / menu (Wayland-aware fork).
# Palette interpolated from _module.args.p directly into the .rasi
# theme so colour changes propagate without editing two places.
# Bound to SUPER+D in home/desktop/sessions/hyprland/session.nix.
{
  p,
  c,
  theme, # reserved for future per-theme structural overrides
  ...
}: {
  # Rofi — palette theme file (colors interpolated from theme palette)
  xdg.dataFile."rofi/themes/palette.rasi".text = ''
    * {
        bg:       ${c.rasiRGBA p.bg};
        fg:       ${c.rasiRGBA p.fg};
        fg-dim:   ${c.rasiRGBA p.fg_dim};
        fg-bright:${c.rasiRGBA p.fg_bright};
        accent:   ${c.rasiRGBA p.accent_warm};
        border-clr:${c.rasiRGBA p.accent_warm};
        urgent:   ${c.rasiRGBA p.bright_red};
        selected: ${c.rasiRGBA p.gray};

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
  '';

  # Rofi — config
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
