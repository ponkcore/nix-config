# bluetooth.nix — Bluetooth stack.
#
# Universal: every host with a BT controller benefits. BlueZ provides
# the backend. The ownership split is:
#   BlueZ backend   — this module (system service + blueman-mechanism)
#   Bluetooth UI    — Caelestia shell (Quickshell.Bluetooth, user session)
#   Pairing agent   — blueman-applet (HM, user session)
# See home/blueman-applet.nix for the agent rationale.
#
# powerOnBoot = true: BT mouse is in constant use. The user disables
# BT manually via desktop UI or `bluetoothctl power off` when they want
# to save battery — no automatic rfkill blocking.
#
# RPA AddressType fix: BlueZ 5.80+ writes AddressType=public for BLE
# RPA devices whose identity address is public (e.g. VXE R1 Nearlink
# mouse). This disables IRK resolution on daemon restart → LTK not
# loaded → GATT auth fails → HoG cannot read Report Map → mouse not
# registered as HID.
#
# The fix is a 4-line source patch to device_update_addr in
# src/device.c, applied here via hardware.bluetooth.package (scoped
# to the bluetooth service only — no global overlay, no 223-derivation
# cascade). Previously a bt-bond-fix systemd service sed'd bond files
# and restarted bluetoothd at boot, causing nscd/nss cascade restarts;
# that workaround is now removed.
#
# Upstream: unfixed in BlueZ 5.86. Issue #752 closed "not planned".
# See researches/2026-07-02-bluez-rpa-addresstype-bug.result.md.
# Remove this patch when upstream merges the fix.
{
  config,
  pkgs,
  ...
}: {
  hardware.bluetooth = {
    enable = true;
    # Scoped patched BlueZ — only the bluetooth service uses this
    # package, avoiding a global overlay and the 223-derivation
    # cascade rebuild that a pkgs.bluez overlay would trigger.
    package = pkgs.bluez.overrideAttrs (old: {
      patches =
        (old.patches or [])
        ++ [
          ../../hosts/lecoo/patches/bluez-rpa-addrtype.patch
        ];
    });
  };

  services.blueman.enable = true;

  # Experimental enables improved BLE/HoG handling.
  # FastConnectable reduces reconnection latency for paired devices.
  hardware.bluetooth.settings = {
    General = {
      Experimental = true;
      FastConnectable = true;
      ControllerMode = "dual";
    };
    Policy = {
      AutoEnable = true;
    };
  };
}
