# home/desktop/default.nix — Home Manager desktop dispatcher.
#
# Mirrors modules/nixos/desktop/default.nix on the user side: imports
# the compositor-agnostic theme bundle, then imports the session-
# specific HM modules for each entry in the host's `desktops` list.
#
# Contract:
#   - ../../theme is imported whenever desktops is non-empty. It
#     provides the Nix-side palette (rofi rasi theme), wallpaper path,
#     helper scripts, and structural config (Ghostty font/padding,
#     cursor theme) via _module.args. Live color state for Hyprland,
#     Ghostty, and GTK is owned by Caelestia CLI at runtime.
#   - sessions/<name>/ is imported when "<name>" appears in desktops.
#   - Adding a new session = drop a folder under sessions/ and add
#     the corresponding lib.mkIf line below. Existing sessions stay
#     untouched.
#
# `desktops` flows in via extraSpecialArgs from lib/mkHost.nix.
# Hosts that opt out of the desktop layer (servers, headless VMs)
# simply pass desktops = [] (or omit it) and this whole tree
# evaluates to nothing.
{
  lib,
  desktops ? [],
  ...
}: let
  has = name: builtins.elem name desktops;
in {
  imports =
    lib.optionals (desktops != []) [
      ../../theme
    ]
    ++ lib.optionals (has "hyprland") [./sessions/hyprland]
    # Future sessions plug in here. The folders do not exist yet,
    # but the dispatcher already knows their names. Adding niri or
    # GNOME later means creating ./sessions/<name>/default.nix and
    # uncommenting the matching line.
    # ++ lib.optionals (has "niri")     [ ./sessions/niri  ]
    # ++ lib.optionals (has "gnome")    [ ./sessions/gnome ]
    ;
}
