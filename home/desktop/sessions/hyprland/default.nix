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
    ./quickshell.nix
  ];

  # UWSM env — block graphical-session.target until
  # HYPRLAND_INSTANCE_SIGNATURE is in the systemd activation
  # environment. Without this, waybar (and other graphical-session
  # units) can start before the signature is propagated; Waybar's
  # IPC thread reads getenv("HYPRLAND_INSTANCE_SIGNATURE"), gets
  # nullptr, and exits permanently — workspace indicators freeze.
  # UWSM_WAIT_VARNAMES makes wayland-session-waitenv.service block
  # until the variable appears. UWSM_FINALIZE_VARNAMES tells
  # `uwsm finalize` to export it explicitly.
  # Source: research 2026-06-26-waybar-ipc-freeze-deep-research §4.1
  xdg.configFile."uwsm/env-hyprland".text = ''
    export UWSM_WAIT_VARNAMES="''${UWSM_WAIT_VARNAMES} HYPRLAND_INSTANCE_SIGNATURE"
    export UWSM_FINALIZE_VARNAMES="''${UWSM_FINALIZE_VARNAMES} HYPRLAND_INSTANCE_SIGNATURE"
  '';
}
