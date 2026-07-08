# yazi.nix — TUI file manager (Rust, fast).
# Palette via _module.args.p. Fish integration provides yy command
# that cd's into yazi's last directory on quit.
{p, ...}: {
  programs.yazi = {
    enable = true;
    enableFishIntegration = true;
    shellWrapperName = "yy";
    settings = {
      manager = {
        show_hidden = true;
        sort_by = "alphabetical";
        sort_reverse = false;
        sort_dir_first = true;
      };
    };
    theme = {
      manager = {
        cwd = {fg = p.accent_warm;};
        hovered = {
          fg = p.bg;
          bg = p.hover_bg;
        };
        tab_active = {
          fg = p.fg_bright;
          bg = p.hover_bg;
        };
        tab_inactive = {fg = p.fg_dim;};
        border_symbol = "│";
        border_style = {fg = p.border;};
      };
      status = {
        separator_open = "";
        separator_close = "";
        separator_style = {
          fg = p.border;
          bg = p.border;
        };
        mode_normal = {
          fg = p.hover_fg;
          bg = p.hover_bg;
          bold = true;
        };
        mode_select = {
          fg = p.hover_fg;
          bg = p.bright_blue;
          bold = true;
        };
        mode_unset = {
          fg = p.hover_fg;
          bg = p.bright_magenta;
          bold = true;
        };
        progress_label = {inherit (p) fg;};
        progress_normal = {
          fg = p.bright_green;
          inherit (p) bg;
        };
        progress_error = {
          fg = p.bright_red;
          inherit (p) bg;
        };
      };
      input = {
        border = {fg = p.accent_warm;};
        title = {fg = p.accent_warm;};
        value = {inherit (p) fg;};
      };
      select = {
        border = {fg = p.accent_warm;};
        active = {fg = p.bright_yellow;};
      };
      completion = {
        border = {fg = p.accent_warm;};
        active = {fg = p.bright_yellow;};
      };
      tasks = {
        border = {fg = p.accent_warm;};
        title = {fg = p.accent_warm;};
        hovered = {
          fg = p.hover_fg;
          bg = p.hover_bg;
        };
      };
      file = {
        selected = {fg = p.bright_yellow;};
      };
    };
  };
}
