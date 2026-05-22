# adw-network.nix — GNOME-inspired NetworkManager frontend.
#
# Pure GTK4 / libadwaita panel that talks to NetworkManager over D-Bus.
# Replaces nm-applet / nm-connection-editor for graphical Wi-Fi /
# hotspot / profile management. Mirror of the adw-bluetooth pattern.
#
# Pulled from our local pkgs overlay (see pkgs/adw-network) — the
# upstream is not in nixpkgs as of Feb 2026.
{pkgs, ...}: {
  home.packages = [pkgs.adw-network];
}
