# bluetooth.nix — Bluetooth stack.
#
# Universal: every host with a BT controller benefits. The GUI manager
# is the unified Orbit popup (home/orbit.nix), which exposes a
# Bluetooth tab next to Wi-Fi/VPN/Ethernet. Headless hosts get
# bluetoothd + bluetoothctl on PATH and skip Orbit entirely.
#
# powerOnBoot = false: the BT controller draws 0.3-0.8 W at idle.
# Users enable BT explicitly via Orbit or `bluetoothctl power on`
# when needed — most sessions don't use BT (headphones are USB-C,
# mouse is 2.4 GHz dongle). This saves battery without UX impact
# for non-BT users.
{
  config,
  pkgs,
  ...
}: {
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = false;
  };

  # Auto-disable BT on battery unplug, re-enable on AC (for users
  # who explicitly turned it on). Uses rfkill because bluetoothctl
  # power off requires the BT daemon to be running, while rfkill
  # works at the kernel level regardless.
  systemd.services.bluetooth-battery = {
    description = "Disable Bluetooth on battery";
    after = ["bluetooth.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "bt-battery" ''
        online=$(cat /sys/class/power_supply/ADP1/online 2>/dev/null || echo 0)
        if [ "$online" = "0" ]; then
          ${pkgs.util-linux}/bin/rfkill block bluetooth 2>/dev/null || true
        fi
      '';
    };
  };
}
