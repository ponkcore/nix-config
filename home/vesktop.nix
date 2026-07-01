# vesktop.nix — Discord-compatible Wayland client.
#
# Vesktop is the preferred Discord client on this Hyprland host: it
# wraps Discord with Vencord, uses Electron's Wayland/Ozone path via
# the global session env, and supports PipeWire screenshare audio via
# venmic. Plugin toggles remain mutable user state; declarative state
# can be added later once the desired Vencord setup is known.
{pkgs, ...}: {
  home.packages = [pkgs.vesktop];
}
