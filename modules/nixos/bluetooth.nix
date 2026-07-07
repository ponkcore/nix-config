# bluetooth.nix — Bluetooth stack.
#
# Universal: every host with a BT controller benefits. BlueZ provides
# the backend; UI and pairing-agent choices live at the user layer.
#
# powerOnBoot = true: BT mouse is in constant use. The user disables
# BT manually via desktop UI or `bluetoothctl power off` when they want
# to save battery — no automatic rfkill blocking.
#
# bt-bond-fix: BlueZ 5.80+ writes AddressType=public for BLE RPA
# devices whose identity address is public (e.g. VXE R1 Nearlink
# mouse). This disables IRK resolution on daemon restart → LTK not
# loaded → GATT auth fails → HoG cannot read Report Map → mouse not
# registered as HID. The service fixes bond files by changing
# AddressType=public → AddressType=static for LE-only devices with
# an IdentityResolvingKey, then restarts bluetoothd to reload.
#
# Upstream: unfixed in BlueZ 5.86 (latest). Issue #752 closed "not
# planned". A source-level patch exists (researches/2026-07-02-bluez-
# rpa-addresstype-bug.result.md) but applying it via nixpkgs overlay
# triggers a 223-derivation cascade rebuild (BlueZ is a low-level
# dependency). The workaround avoids any compilation.
# Remove this service when upstream merges the fix.
{
  config,
  pkgs,
  ...
}: {
  hardware.bluetooth.enable = true;
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

  # Fix AddressType=public → static for BLE RPA devices on every
  # bluetoothd restart. Runs as a oneshot after bluetooth.service.
  systemd.services.bt-bond-fix = {
    description = "Fix BlueZ bond AddressType for BLE RPA devices";
    after = ["bluetooth.service"];
    wants = ["bluetooth.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      BDADDR_DIR="/var/lib/bluetooth"
      sleep 2  # wait for bluetoothd to initialise adapter
      changed=0
      for adapter in "$BDADDR_DIR"/*/; do
        for dev in "$adapter"*/; do
          info="$dev/info"
          [ -f "$info" ] || continue
          # Only fix LE-only devices with IRK (RPA devices)
          if grep -q '^\[IdentityResolvingKey\]' "$info" 2>/dev/null && \
             grep -q '^AddressType=public' "$info" 2>/dev/null; then
            sed -i 's/^AddressType=public$/AddressType=static/' "$info"
            changed=$((changed + 1))
            echo "Fixed: $info"
          fi
        done
      done
      if [ "$changed" -gt 0 ]; then
        echo "Fixed $changed bond file(s), restarting bluetoothd"
        systemctl restart bluetooth.service
        sleep 2
      else
        echo "No bond files need fixing"
      fi
    '';
  };
}
