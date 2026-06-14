# theme/default.nix — compositor-agnostic Wayland theming.
#
# Aggregator: exports the gruvbox palette `p`, the wallpaper path, and
# the color helpers `c` to all submodules via _module.args, then
# imports the user-level UI bits that work under ANY Wayland compositor
# — waybar, mako, rofi, ghostty, and the script library.
#
# Helper scripts (notification toggle, lecoo charge mode, telegram
# toggle, etc.) live in theme/scripts.nix to keep this file focused
# on visual concerns. Compositor-specific config (Hyprland keybinds,
# hyprlock, hypridle, hyprpaper; future niri/swaylock/swayidle/swaybg;
# future GNOME dconf) lives in home/desktop/sessions/<name>/ and is
# imported by home/desktop/default.nix based on the active session set.
#
# Imported from home/desktop/default.nix when desktops is non-empty.
# Headless/server hosts never see this file.
{pkgs, ...}: let
  # Palette derived from Gruvbox warm tones: amber, parchment, burnt umber.
  p = import ../lib/palette.nix;

  # Color helpers — convert palette tokens into the surface formats
  # different consumers expect (Hyprland literals, rofi rasi rgba,
  # GTK rgba). Single source of truth, replaces the three hand-rolled
  # converters previously inlined in session.nix, lock.nix and rofi.nix.
  c = import ../lib/color.nix;

  # Wallpaper paths. `wallpaper` remains the original full-resolution
  # asset for lock-screen use; `sessionWallpaper` is a pre-scaled copy
  # for the live Hyprland wallpaper daemon so hyprpaper does not keep a
  # 6000x4000 image resident just to paint a 2880x1800 panel.
  wallpaper = "${../assets/wallpaper.jpg}";
  sessionWallpaper = "${sessionWallpaperAsset}";
  sessionWallpaperAsset = pkgs.runCommand "wallpaper-session.jpg" {nativeBuildInputs = [pkgs.imagemagick];} ''
    magick \
      ${../assets/wallpaper.jpg} \
      -resize 2880x1800^ \
      -gravity center \
      -extent 2880x1800 \
      "$out"
  '';
in {
  # _module.args makes p, c, and wallpaper paths available as function
  # arguments to ALL submodules imported below (e.g.,
  # `{ pkgs, p, c, wallpaper, ... }:`). The script bin args are wired up
  # in scripts.nix.
  _module.args = {
    inherit p c wallpaper sessionWallpaper;
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
