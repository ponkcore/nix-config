# blueman-applet.nix — BlueZ pairing-agent session service.
#
# Quickshell owns the visible Bluetooth UI. blueman-applet is kept as a
# background pairing-agent provider because Quickshell 0.3.x does not
# yet register org.bluez.Agent1 natively.
#
# This module intentionally enables only the applet service path; it
# does not make blueman-manager the primary UI. The manager remains
# available as a manual debug/admin tool.
_: {
  services.blueman-applet.enable = true;
}
