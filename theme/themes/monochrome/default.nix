# theme/themes/monochrome/default.nix — active single-theme shell.
#
# Current Quickshell-based top bar + control center theme. The visual
# direction will evolve toward monochrome, but the palette remains a
# dedicated local source so the theme can evolve independently of the
# removed Waybar-era layout.
_: {
  palette = import ./palette.nix;
  wallpaper = ../../../assets/wallpaper.png;

  # This theme uses quickshell as its bar backend, not waybar.
  # The quickshell config lives in pkgs/quickshell-config/.
  bar = "quickshell";

  mako = {};
  rofi = {};
  ghostty = {};
}
