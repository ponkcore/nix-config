# home/desktop/sessions/hyprland/default.nix — Hyprland user environment.
#
# Activated when "hyprland" is in the host's `desktops` list. Imports
# the pieces that make up a Hyprland session for the user:
#   - session config (keybinds, rules, animations)
#   - lock screen, idle manager, wallpaper ownership
#   - session-only helper scripts (window/app toggles)
#   - Caelestia shell service (forked from caelestia-dots/shell)
# Compositor-agnostic theming (mako, rofi, ghostty, palette) lives in
# ../../../theme.
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
