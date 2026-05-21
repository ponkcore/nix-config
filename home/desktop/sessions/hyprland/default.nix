# home/desktop/sessions/hyprland/default.nix — Hyprland user environment.
#
# Activated when "hyprland" is in the host's `desktops` list. Imports
# the pieces that make up a Hyprland session for the user:
#   - session config (keybinds, rules, animations)
#   - lock screen, idle manager, wallpaper daemon
#   - session-only helper scripts (telegram-toggle, clash-toggle)
#   - the Hyprland-only waybar fragment that consumes those scripts
# Compositor-agnostic theming (waybar skeleton, mako, rofi, ghostty,
# palette) lives in ../../../theme.
{...}: {
  imports = [
    ./session.nix
    ./lock.nix
    ./idle.nix
    ./paper.nix
    ./scripts.nix
    ./waybar.nix
  ];
}
