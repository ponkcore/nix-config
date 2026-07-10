# blueman-applet.nix — BlueZ pairing-agent session service.
#
# Ownership split (stable, permanent):
#   BlueZ backend        — NixOS (modules/nixos/bluetooth.nix)
#   Bluetooth UI         — Caelestia shell (Quickshell.Bluetooth)
#   Pairing agent        — blueman-applet (this module)
#
# Quickshell.Bluetooth wraps org.bluez.Adapter1 and org.bluez.Device1
# (adapter toggle, device list, connect/disconnect, pair, forget) but
# does NOT implement org.bluez.Agent1. The shell's pair() calls
# org.bluez.Device1.Pair, which requires a registered agent for
# authentication callbacks (PIN, passkey, confirmation). Without an
# agent, pairing fails for any device requiring authentication.
#
# blueman-applet's AuthAgent plugin provides org.bluez.Agent1 at
# /org/bluez/agent/blueman on the system bus with KeyboardDisplay
# capability and default-agent status. It handles all 8 agent methods
# (RequestPinCode, DisplayPinCode, RequestPasskey, DisplayPasskey,
# RequestConfirmation, RequestAuthorization, AuthorizeService, Cancel)
# via GTK dialogs and notifications.
#
# This is NOT a temporary workaround. It is the stable ownership model:
# Caelestia owns the UI, blueman-applet owns the agent substrate.
# Removing blueman-applet without a replacement agent will break all
# Bluetooth pairing.
#
# Side effect: blueman-tray (started by the applet) provides a
# StatusNotifierItem that appears in the Caelestia bar — a minor
# cosmetic duplicate of the shell's own Bluetooth status icon.
# blueman-manager remains available as a manual debug/admin tool.
_: {
  services.blueman-applet.enable = true;
}
