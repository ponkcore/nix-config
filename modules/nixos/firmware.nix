# firmware.nix — firmware updates + storage health monitoring.
#
# Universal: fwupd queries LVFS for vendor-released firmware (BIOS, EC,
# Thunderbolt controllers, NVMe drives). smartd watches disk SMART
# counters and walls a notification on threshold breach.
_: {
  services.fwupd.enable = true;

  # Override the upstream cadence. The fwupd package ships a timer with
  # `OnCalendar=*-*-* *:00:00` (every hour). On a laptop that is wasteful
  # — LVFS metadata changes on the order of weeks, not minutes. Twice a
  # day at 03:00 / 15:00 with Persistent=true catches releases without
  # waking the host every hour.
  #
  # systemd MERGES multiple `OnCalendar=` lines across the base unit and
  # any drop-in overrides. To replace rather than append we emit an
  # empty `OnCalendar=` line first (which clears the upstream value)
  # and then ours. The list form of timerConfig.OnCalendar in the
  # systemd NixOS module emits each element as its own line, so the
  # empty string at index 0 produces the required reset directive.
  systemd.timers.fwupd-refresh.timerConfig = {
    OnCalendar = ["" "*-*-* 03,15:00:00"];
    Persistent = true;
    AccuracySec = "1h";
    RandomizedDelaySec = "30min";
  };

  # SMART monitoring — watches NVMe / SATA health, walls a message on errors.
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications.wall.enable = true;
  };
}
