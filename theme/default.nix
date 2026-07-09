# theme/default.nix — compositor-agnostic Wayland theming.
#
# Single active theme export. The structure stays extensible: future
# themes still live under theme/themes/<name>/ and can be wired here,
# but the current system intentionally supports only one active theme.
#
# Aggregator: exports the theme's palette `p`, color helpers `c`,
# wallpaper path, and the full theme attrset to all submodules via
# _module.args. Submodules consume `theme` to generate component-
# specific config (rofi theme, ghostty palette, etc.).
#
# Helper scripts (notification toggle, lecoo charge mode, etc.) live
# in theme/scripts.nix. Compositor-specific config (Hyprland keybinds,
# hyprlock, hypridle, Caelestia shell) lives in
# home/desktop/sessions/<name>/.
#
# Imported from home/desktop/default.nix when desktops is non-empty.
# Headless/server hosts never see this file.
{
  config,
  pkgs,
  ...
}: let
  theme = import ./themes/monochrome/default.nix {};

  # Palette — extracted from the active theme for convenience.
  # Submodules that only need colors (rofi, ghostty) use `p`
  # directly.
  p = theme.palette;

  # Color helpers — convert palette tokens into the surface formats
  # different consumers expect (Hyprland literals, rofi rasi rgba,
  # GTK rgba). Single source of truth, replaces the three hand-rolled
  # converters previously inlined in session.nix, lock.nix and rofi.nix.
  c = import ../lib/color.nix;

  # Wallpaper path — original full-resolution asset, used by hyprlock.
  # Live wallpaper is owned by Caelestia shell (caelestia wallpaper -f).
  wallpaper = "${theme.wallpaper}";
in {
  # _module.args makes p, c, wallpaper, and the full theme attrset
  # available as function arguments to ALL submodules imported below.
  # Submodules can destructure what they need:
  #   { pkgs, p, c, theme, ... }: { ... }
  _module.args = {
    inherit p c wallpaper theme;
  };

  imports = [
    ./scripts.nix
    ./ghostty.nix
    ./mako.nix
    ./rofi.nix
  ];

  # ── Cursor (Wayland-wide, session-level) ──────────────────────────────
  # home.pointerCursor sets XCURSOR_THEME/SIZE for the entire Wayland session,
  # installs theme to ~/.local/share/icons, and configures GTK/X11 fallback.
  # gtk.cursorTheme below is kept for GTK-specific overrides.
  home.pointerCursor = {
    name = "Capitaine Cursors (Gruvbox)";
    package = pkgs.capitaine-cursors-themed;
    size = 24;
    gtk.enable = true;
  };

  # ── dconf (GTK dark preference) ───────────────────────────────────────
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
    "org/gnome/nautilus/window-state" = {
      maximized = false;
      initial-size = "(890, 550)";
    };
  };

  # ── GTK theme ─────────────────────────────────────────────────────────
  gtk = {
    enable = true;
    theme = {
      # gruvbox-gtk-theme ships proper gtk-4.0/ assets; the older
      # gruvbox-dark-gtk only carries gtk-2.0/3.0 and produces a
      # "Failed to import gtk.css" warning on every gtk4 launch
      # (mako, keepassxc, …).
      name = "Gruvbox-Dark";
      package = pkgs.gruvbox-gtk-theme;
    };
    gtk4.theme = config.gtk.theme;
    cursorTheme = {
      name = "Capitaine Cursors (Gruvbox)";
      package = pkgs.capitaine-cursors-themed;
      size = 24;
    };
    iconTheme = {
      name = "oomox-gruvbox-dark";
      package = pkgs.gruvbox-dark-icons-gtk;
    };
  };
}
