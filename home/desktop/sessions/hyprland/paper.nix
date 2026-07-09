# paper.nix — Wallpaper ownership (Hyprland session).
#
# hyprpaper is disabled. Caelestia shell owns the wallpaper runtime
# flow via its Background module + CLI (caelestia wallpaper -f <path>).
# Wallpaper state lives in ~/.local/state/caelestia/wallpaper/path.txt.
_: {
  services.hyprpaper = {
    enable = false;
  };
}
