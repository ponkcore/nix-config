# theme/themes/monochrome/default.nix — active single-theme shell.
#
# Palette and wallpaper assets for the current Caelestia shell.
# Caelestia owns the bar, control center, launcher, and wallpaper
# runtime. The palette remains a dedicated local source so the theme
# can evolve independently of the shell fork.
_: {
  palette = import ./palette.nix;
  wallpaper = ../../../assets/wallpaper.png;

  rofi = {};
  ghostty = {};
}
