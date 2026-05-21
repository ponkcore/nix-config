# paper.nix — Wayland wallpaper daemon (Hyprland session, hyprpaper).
# Wallpaper path comes from _module.args (theme/default.nix) which
# imports assets/wallpaper.jpg.
{
  config,
  pkgs,
  wallpaper,
  ...
}: {
  services.hyprpaper = {
    enable = true;
    settings = {
      preload = ["${wallpaper}"];
      wallpaper = [",${wallpaper}"];
      splash = false;
    };
  };
}
