# ghostty.nix — terminal emulator (libghostty, native Wayland).
# Palette via _module.args.p — gruvbox-warm 16-color terminal mapping.
# `xdg-terminal-exec` package is added here so Terminal=true desktop
# entries (nvim.desktop etc.) launch correctly.
{
  pkgs,
  p,
  ...
}: {
  # Ghostty is in nixpkgs but has no HM module yet — use home.packages + xdg.configFile
  home.packages = [
    pkgs.ghostty
    pkgs.xdg-terminal-exec # Terminal=true support for desktop entries (e.g. nvim)
  ];

  xdg.configFile."ghostty/config".text = ''
    # Color palette (index-per-line format required by Ghostty)
    # Standard 16-color mapping: 0-7 base, 8-15 bright
    palette = 0=${p.bg}
    palette = 1=${p.red}
    palette = 2=${p.green}
    palette = 3=${p.yellow}
    palette = 4=${p.blue}
    palette = 5=${p.magenta}
    palette = 6=${p.cyan}
    palette = 7=${p.fg}
    palette = 8=${p.gray}
    palette = 9=${p.bright_red}
    palette = 10=${p.bright_green}
    palette = 11=${p.bright_yellow}
    palette = 12=${p.bright_blue}
    palette = 13=${p.bright_magenta}
    palette = 14=${p.bright_cyan}
    palette = 15=${p.fg_bright}

    background = ${p.bg}
    foreground = ${p.fg}
    cursor-color = ${p.fg_bright}
    cursor-text = ${p.bg}
    selection-background = ${p.accent_warm}
    selection-foreground = ${p.bg}

    # Font
    font-family = JetBrainsMono Nerd Font
    font-size = 12

    # Cursor — Ghostty uses "bar" not "beam"
    cursor-style = bar
    cursor-style-blink = false

    # Always start new windows in $HOME, not inherited CWD
    working-directory = home

    # Window
    window-padding-x = 4
    window-padding-y = 4
    window-padding-balance = true
    background-opacity = 0.95
    window-decoration = false

    # Scroll
    scrollback-limit = 10000

    # Confirm close — Ghostty uses confirm-close-surface, not confirm-close
    confirm-close-surface = false

    # Clipboard — W3C physical key codes (key_c, key_v) match by keycode,
    # not keysym, so they work on any keyboard layout (Russian included)
    keybind = ctrl+shift+key_c=copy_to_clipboard
    keybind = ctrl+shift+key_v=paste_from_clipboard
  '';
}
