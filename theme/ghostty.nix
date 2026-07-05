# ghostty.nix — terminal emulator (libghostty, native Wayland).
# Palette via _module.args.p — Gruvbox dark medium 16-color terminal mapping.
# `xdg-terminal-exec` package is added here so Terminal=true desktop
# entries (nvim.desktop etc.) launch correctly.
{
  pkgs,
  p,
  theme, # reserved for future per-theme structural overrides
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
    font-size = 10.8

    # Cursor — Ghostty uses "bar" not "beam"
    cursor-style = bar
    cursor-style-blink = false

    # Always start new windows in $HOME, not inherited CWD
    working-directory = home

    # Force a single shared GTK process per app-id (= per `--class`).
    # Each new `ghostty` launch routes through DBus to the matching
    # live process and opens a new GTK window inside it (~100 ms),
    # instead of a full GTK4+OpenGL cold boot per launch (~2.5 s).
    # The default `detect` was unreliable in this session and kept
    # producing cold starts. Hyprland popup rules match per app-id,
    # which is preserved across DBus-routed window opens.
    gtk-single-instance = true

    # Keep the GTK process alive even after every window of that
    # app-id is closed, so the next launch routes through DBus
    # (~100 ms) instead of cold-starting GTK4+OpenGL+fontconfig
    # (~2.5 s). Combined with `gtk-single-instance = true` and a
    # warm-up exec-once in Hyprland, this gives instant terminals
    # from the very first Super+Return after login. Memory cost:
    # ~80 MiB per kept-alive class (floating + popups).
    quit-after-last-window-closed = false

    # Window
    window-padding-x = 4
    window-padding-y = 4
    window-padding-balance = true
    background-opacity = 0.75
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
