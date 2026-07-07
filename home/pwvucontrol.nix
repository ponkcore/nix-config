# pwvucontrol.nix — Pipewire volume control panel.
#
# GTK4 / libadwaita native PipeWire mixer (no PulseAudio compat shim
# unlike pavucontrol). Toggled through the same special-workspace
# hide/show contract used by the other popup-style panels.
{pkgs, ...}: {
  home.packages = [pkgs.pwvucontrol];
}
