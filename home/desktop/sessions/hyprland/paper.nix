# paper.nix — Wayland wallpaper daemon (Hyprland session, hyprpaper).
# Runtime wallpaper path comes from _module.args (theme/default.nix).
# It is pre-scaled to the internal panel size at HM activation so
# hyprpaper does not keep the original 6000x4000 image resident.
#
# hyprpaper 0.8.0 was a complete rewrite into hyprtoolkit — the old
# preload/wallpaper flat-list syntax was removed. The new block syntax
# uses a `wallpaper { monitor, path, fit_mode }` section per output.
# monitor = "" means all monitors. No preload needed — the path in the
# block is loaded directly.
#
# importantPrefixes includes "monitor" because hyprpaper 0.8.x treats
# `wallpaper` as a special category — the key field (`monitor`) must
# be the first value in the block. The toHyprconf generator sorts
# fields alphabetically (fit_mode < monitor < path), which puts
# fit_mode first and triggers a config parse error. Forcing monitor
# into importantPrefixes makes it render before other fields.
# Source: research 2026-06-27-migration-problems §6
{sessionWallpaper, ...}: {
  services.hyprpaper = {
    enable = true;
    importantPrefixes = ["$" "monitor"];
    settings = {
      splash = false;
      wallpaper = [
        {
          monitor = "";
          path = "${sessionWallpaper}";
          fit_mode = "fill";
        }
      ];
    };
  };
}
