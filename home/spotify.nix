# spotify.nix — Spotify desktop client.
#
# Vanilla nixpkgs build (license: Spotify, allowed globally via
# nixpkgs.config.allowUnfree in modules/nixos/nix.nix). Runs on
# XWayland — there is no native Wayland branch upstream.
#
# Tray-style hide/show toggle and window rules live next to the
# Hyprland session. The desktop shell does not rely on a legacy tray-based
# we use the same special-workspace pattern as Telegram and Clash;
# Spotify's own system-tray icon is therefore not needed.
{pkgs, ...}: {
  home.packages = [pkgs.spotify];
}
