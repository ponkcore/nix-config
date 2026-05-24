# bluetooth.nix — Bluetooth stack.
#
# Universal: every host with a BT controller benefits. The GUI manager
# is the unified Orbit popup (home/orbit.nix), which exposes a
# Bluetooth tab next to Wi-Fi/VPN/Ethernet. Headless hosts get
# bluetoothd + bluetoothctl on PATH and skip Orbit entirely.
_: {
  hardware.bluetooth.enable = true;
}
