# pwvucontrol.nix — Pipewire volume control panel.
#
# GTK4 / libadwaita native PipeWire mixer (no PulseAudio compat shim
# unlike pavucontrol). Driven by the waybar volume icon — first click
# launches, subsequent clicks toggle the special-workspace hide/show
# contract used by the other tray-style panels.
{pkgs, ...}: {
  home.packages = [pkgs.pwvucontrol];
}
