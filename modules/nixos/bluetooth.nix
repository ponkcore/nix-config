# bluetooth.nix — Bluetooth stack.
#
# Universal: every host with a BT controller benefits. The GUI manager
# (adw-bluetooth) is opted in per-user via home/adw-bluetooth.nix
# because it is a desktop-only concern; headless hosts with bluetoothd
# and bluetoothctl available is enough.
_: {
  hardware.bluetooth.enable = true;
}
