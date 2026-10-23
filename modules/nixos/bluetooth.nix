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
# RPA AddressType patch: BlueZ 5.80+ writes AddressType=public for BLE
# RPA devices whose identity address is public. A 4-line source patch to
# device_update_addr in src/device.c forces BDADDR_LE_RANDOM when an IRK
# is present. Previously a bt-bond-fix systemd service sed'd bond files
# and restarted bluetoothd at boot, causing nscd/nss cascade restarts;
# that workaround is now removed.
#
# NOTE — this patch is NOT the reason the VXE R1 Nearlink mouse fails to
# work. That claim was recorded here and disproven by measurement on
# 2026-10-04: the controller reports the mouse's address as Public
# (0x00) over the air (so there is nothing to resolve), the link encrypts
# successfully (HCI Encryption Change → Enabled with AES-CCM), and a
# fresh bond created while the patch was active still stores
# AddressType=public. The actual cause is the HoG Report Map race below.
# Kept for the keyboard (LB Hi75C, genuinely static-random, RPA).
#
# HoG Report Map race: this is the real "mouse connects but does not
# control" bug. Two defects in BlueZ, both still present in 5.87 and in
# git master as of 2026-10-04 (hog.c and hog-lib.c are byte-identical
# there for the patched regions):
#
#   1. hog_accept() only calls bt_gatt_client_set_security(MEDIUM) for
#      UNBONDED devices. A bonded HOGP device therefore races the kernel
#      LE encryption procedure: if the Report Map read (0x2a4b) goes out
#      before the link is encrypted, the device answers ATT 0x05
#      "Attribute requires authentication before read/write".
#   2. report_map_read_cb() leaves hog->report_map_id set on failure, and
#      nothing ever resets it (bt_hog_detach() does not, hog_accept()
#      does not recreate dev->hog). read_report_map() skips the read
#      while that id is non-zero, so one lost race permanently leaves the
#      device without a uHID instance — no /sys/bus/hid/devices/0005:*
#      entry, while the mouse keeps sending HID reports into the void.
#   3. (2026-10-23) Fix 1 narrows but does not close the race. On the
#      cached-DB attach path (GATT cache restored from disk, no Report
#      Map VALUE in it — true for this mouse) the read queue drains in
#      milliseconds while kernel LE encryption is still in flight, so
#      the first connect after a reboot can still lose it: measured once
#      in ~25 attaches (boot 2026-10-23 10:59:25, ATT 0x05 "Attribute
#      requires authentication", mouse dead while Connected: yes). The
#      attach-level self-heal from fix 2 needs a reconnect to fire, and
#      nothing re-triggers one while the link stays up. The patch now
#      also retries the read IN-CONNECTION: on failure it resets
#      report_map_id and schedules a 1 s retry via
#      g_timeout_add_seconds — bounded at 5 retries per attach, reset in
#      bt_hog_attach, cancelled in bt_hog_detach (no use-after-free),
#      deferred while the GATT queue is non-empty so the "Report Map is
#      read last" invariant from remove_gatt_req() holds.
#
# All three fixes are in bluez-hog-report-map-race.patch.
#
# Upstream: Issue #752 (AddressType) closed "not planned".
# See researches/2026-07-02-bluez-rpa-addresstype-bug.result.md.
# Remove either patch when upstream merges the corresponding fix.
{pkgs, ...}: {
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
          ../../hosts/lecoo/patches/bluez-hog-report-map-race.patch
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
