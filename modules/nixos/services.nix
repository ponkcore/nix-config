# services.nix — miscellaneous always-on services.
#
# Holds the small handful of system services that don't justify their
# own file: dconf (GTK runtime settings store), GNOME keyring (Secret
# Service / D-Bus secret stash for apps that integrate with it), and
# the modemmanager opt-out (no cellular modems on these hosts).
#
# Audio, Bluetooth, containers, and firmware/storage health each live
# in their own focused module.
_: {
  # dconf — needed for some GTK settings under Hyprland
  programs.dconf.enable = true;

  # GNOME keyring — Secret Service backend for apps (browsers, network-manager)
  services.gnome.gnome-keyring.enable = true;

  # No cellular modem on this hardware family — keep ModemManager off.
  networking.modemmanager.enable = false;
}
