# theme/default.nix — compositor-agnostic Wayland theming.
#
# Aggregator: selects the active theme, then exports the theme's
# palette `p`, color helpers `c`, wallpaper path, and the full theme
# attrset to all submodules via _module.args. Submodules are renderers:
# they consume `theme` to generate component-specific config (waybar
# layout, CSS, mako colors, rofi theme, ghostty palette).
#
# To add a theme: create theme/themes/<name>/ with palette.nix and
# default.nix (see theme/themes/gruvbox-dark/ for the template). Then
# add it to `themes` below and set `activeTheme`.
#
# To switch themes at runtime without rebuild (future): a rofi
# selector writes the theme name to a mutable state file; a script
# copies the theme's CSS into a writable active-theme.css and sends
# SIGUSR1 to waybar. The declarative structure here is the base.
#
# Helper scripts (notification toggle, lecoo charge mode, telegram
# toggle, etc.) live in theme/scripts.nix. Compositor-specific config
# (Hyprland keybinds, hyprlock, hypridle, hyprpaper) lives in
# home/desktop/sessions/<name>/.
#
# Imported from home/desktop/default.nix when desktops is non-empty.
# Headless/server hosts never see this file.
{pkgs, ...}: let
  # ── Theme registry ────────────────────────────────────────────────
  # Each theme is a Nix module that returns { palette, wallpaper,
  # waybar, mako, rofi, ghostty } attrsets. Add new themes here.
  themes = {
    gruvbox-dark = import ./themes/gruvbox-dark/default.nix {inherit pkgs;};
    matteogini = import ./themes/matteogini/default.nix {};
  };

  # Active theme — change this to switch. In future: driven by a
  # mutable state file so a rofi selector can switch without rebuild.
  activeThemeName = "gruvbox-dark";
  theme = themes.${activeThemeName};

  # Palette — extracted from the active theme for convenience.
  # Submodules that only need colors (mako, rofi, ghostty) use `p`
  # directly; modules that need structural data (waybar layout) use
  # `theme.waybar.*`.
  p = theme.palette;

  # Color helpers — convert palette tokens into the surface formats
  # different consumers expect (Hyprland literals, rofi rasi rgba,
  # GTK rgba). Single source of truth, replaces the three hand-rolled
  # converters previously inlined in session.nix, lock.nix and rofi.nix.
  c = import ../lib/color.nix;

  # Wallpaper paths. `wallpaper` remains the original full-resolution
  # asset for lock-screen use; `sessionWallpaper` is a pre-scaled copy
  # for the live Hyprland wallpaper daemon so hyprpaper does not keep a
  # large image resident just to paint a 2880x1800 panel.
  wallpaper = "${theme.wallpaper}";
  sessionWallpaper = "${sessionWallpaperAsset}";
  sessionWallpaperAsset = pkgs.runCommand "wallpaper-session.png" {nativeBuildInputs = [pkgs.imagemagick];} ''
    magick \
      ${theme.wallpaper} \
      -resize 2880x1800^ \
      -gravity center \
      -extent 2880x1800 \
      "$out"
  '';
in {
  # _module.args makes p, c, wallpaper, and the full theme attrset
  # available as function arguments to ALL submodules imported below.
  # Submodules can destructure what they need:
  #   { pkgs, p, c, theme, ... }: { ... }
  _module.args = {
    inherit p c wallpaper sessionWallpaper theme;
  };

  imports = [
    ./scripts.nix
    ./waybar
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
      # (mako, orbit, keepassxc, …).
      name = "Gruvbox-Dark";
      package = pkgs.gruvbox-gtk-theme;
    };
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
