# adw-bluetooth.nix — GNOME-inspired Bluetooth device manager.
#
# Replaces blueman-manager from the system layer (see
# modules/nixos/bluetooth.nix). Pure GTK4 / libadwaita panel that talks
# to bluetoothd over D-Bus — no tray dependency, no system service to
# enable. The waybar custom/bluetooth slot launches and toggles it the
# same way Telegram, Spotify and Clash are wired.
#
# Available in nixpkgs 25.11 and unstable; the host's allowUnfree is
# irrelevant here (GPL-3.0).
{pkgs, ...}: {
  home.packages = [pkgs.adw-bluetooth];
}
