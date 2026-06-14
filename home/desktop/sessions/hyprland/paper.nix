# paper.nix — Wayland wallpaper daemon (Hyprland session, hyprpaper).
# Runtime wallpaper path comes from _module.args (theme/default.nix).
# It is pre-scaled to the internal panel size at HM activation so
# hyprpaper does not keep the original 6000x4000 image resident.
{sessionWallpaper, ...}: {
  services.hyprpaper = {
    enable = true;
    settings = {
      preload = ["${sessionWallpaper}"];
      wallpaper = [",${sessionWallpaper}"];
      splash = false;
    };
  };
}
