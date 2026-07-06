# theme/themes/matteogini/default.nix — matteogini-inspired bar.
#
# Minimalist top bar adapted from github.com/matteogini/dotfiles.
# Ultra-compact: JetBrainsMono 9px bold, transparent background,
# accent-colored active elements, drawer groups for stats and tools.
# Designed to pair with quickshell control center (phase 2).
#
# Palette: Gruvbox dark medium (shared with gruvbox-dark theme).
_: {
  palette = import ../gruvbox-dark/palette.nix;
  wallpaper = ../../../assets/wallpaper.png;

  # This theme uses quickshell as its bar backend, not waybar.
  # The quickshell config lives in pkgs/quickshell-config/.
  bar = "quickshell";

  mako = {};
  rofi = {};
  ghostty = {};
}
