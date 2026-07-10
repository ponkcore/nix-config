# home/desktop/sessions/hyprland/default.nix — Hyprland user environment.
#
# Activated when "hyprland" is in the host's `desktops` list. Imports
# the pieces that make up a Hyprland session for the user:
#   - session config (keybinds, rules, animations)
#   - lock/idle/wallpaper modules (DISABLED — Caelestia owns these;
#     configs retained as reference/fallback)
#   - session-only helper scripts (window/app toggles)
#   - Caelestia shell service (forked from caelestia-dots/shell)
# Compositor-agnostic theming (rofi rasi, Ghostty structural config,
# cursor theme) lives in ../../../theme. Live color state for Hyprland,
# Ghostty, and GTK is owned by Caelestia CLI at runtime.
# Notification, lock, idle, and wallpaper ownership is Caelestia shell.
{...}: {
  imports = [
    ./session.nix
    ./lock.nix
    ./idle.nix
    ./paper.nix
    ./scripts.nix
    ./caelestia.nix
  ];

  # UWSM env — block graphical-session.target until
  # HYPRLAND_INSTANCE_SIGNATURE is in the systemd activation
  # environment. Without this, graphical-session user units can start
  # before the signature is propagated.
  xdg.configFile."uwsm/env-hyprland".text = ''
    export UWSM_WAIT_VARNAMES="''${UWSM_WAIT_VARNAMES} HYPRLAND_INSTANCE_SIGNATURE"
    export UWSM_FINALIZE_VARNAMES="''${UWSM_FINALIZE_VARNAMES} HYPRLAND_INSTANCE_SIGNATURE"
  '';
}
