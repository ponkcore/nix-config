# ghostty.nix — terminal emulator (libghostty, native Wayland).
# Terminal colours are owned by Caelestia CLI runtime: the CLI
# generates OSC sequences (sequences.txt) and broadcasts them to
# open PTYs on `caelestia scheme set`. A fish shell hook
# (interactiveShellInit in fish.nix) applies sequences.txt to new
# interactive sessions, so new Ghostty windows adopt the active
# scheme at shell startup. Nix owns only structural settings:
# font, cursor style, window behaviour, scrollback, clipboard.
# `xdg-terminal-exec` package is added here so Terminal=true desktop
# entries (nvim.desktop etc.) launch correctly.
{pkgs, ...}: {
  # Ghostty is in nixpkgs but has no HM module yet — use home.packages + xdg.configFile
  home.packages = [
    pkgs.ghostty
    pkgs.xdg-terminal-exec # Terminal=true support for desktop entries (e.g. nvim)
  ];

  xdg.configFile."ghostty/config".text = ''
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
