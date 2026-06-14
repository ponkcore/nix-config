# form-factor/laptop.nix — laptop-specific tuning profile.
#
# Opt-in for any host that's a laptop (or 2-in-1 / convertible).
# NOT opt-in for desktops and VMs — they have different needs:
#   - desktops don't have a battery, lid, or USB autosuspend pressure
#   - VMs shouldn't touch power policy (host hypervisor handles it)
#
# What this profile does:
#   - power-profiles-daemon: single source of truth for power state,
#     bridges to /sys/firmware/acpi/platform_profile (read by amd_pmf
#     on this hardware) and /sys/devices/system/cpu/cpu*/cpufreq/
#     energy_performance_preference. Replaces auto-cpufreq's battery↔AC
#     binary with the firmware-defined three-state ladder
#     (power-saver / balanced / performance).
#   - logind: ignore lid switch (lid-monitor handles DPMS on its own).
#   - acpi.lid_init_state=open: works around Emdoor N155A firmware that
#     caches a stale "closed" state from cold boot. Without this the
#     kernel logs "The lid device is not compliant to SW_LID" and the
#     /proc/acpi/button/lid/LID0/state file is stuck at "closed".
#   - lid-monitor user service: polls /proc/acpi/button/lid/LID0/state
#     once a second to drive Hyprland DPMS. Polling is the only reliable
#     channel on firmware that does not reliably fire ACPI Notify(LID).
#   - udev rules: USB autosuspend, NVMe scheduler tuning,
#     XHCI/I2C wakeup disable to prevent spurious wake-from-suspend.
#   - exposes the `on-battery` helper script to consumers (e.g. hypridle)
#     via _module.args so they don't reach for /sys directly.
{pkgs, ...}: let
  # Lid-state polling loop. Reads /proc/acpi/button/lid/LID0/state every
  # second and drives Hyprland DPMS on edge transitions only. Initial
  # state read primes `prev` so we never fire DPMS on service startup.
  #
  # Why polling rather than acpi_listen/inotify:
  #   - acpid: depends on firmware firing Notify(LID, 0x80). Emdoor N155A
  #     does NOT fire it on every transition. Lost events = stuck DPMS.
  #   - inotify: /proc is synthesised — inotify never triggers on it.
  #   - polling: ~1 ms CPU per minute, guaranteed to catch every state.
  lidMonitorScript = pkgs.writeShellScript "lid-monitor" ''
    LID=/proc/acpi/button/lid/LID0/state
    HYPRCTL=${pkgs.hyprland}/bin/hyprctl

    if [ ! -r "$LID" ]; then
      echo "lid-monitor: $LID unreadable, exiting" >&2
      exit 1
    fi

    # Prime previous state so the first iteration does not fire DPMS.
    read -r _ prev < "$LID"

    while sleep 1; do
      read -r _ state < "$LID" || continue
      if [ "$state" != "$prev" ]; then
        # Target eDP-1 explicitly — bare `dpms off` blanks every
        # output, which would also kill any external HDMI/DP screen
        # the user is actively working on with the lid closed.
        case "$state" in
          closed) "$HYPRCTL" dispatch dpms off eDP-1 || true ;;
          open)   "$HYPRCTL" dispatch dpms on  eDP-1 || true ;;
        esac
        prev="$state"
      fi
    done
  '';

  # `on-battery` — exit 0 when running on battery, exit 1 otherwise.
  # Belongs to the laptop hardware profile because the very concept of
  # an AC adapter file under /sys/class/power_supply only exists on
  # laptop-class hardware. Session-level modules (hypridle and friends)
  # consume this via _module.args so they never reach for /sys directly
  # and stay portable to compositors and form factors alike.
  on-battery = pkgs.writeShellScriptBin "on-battery" ''
    [ "$(cat /sys/class/power_supply/ADP1/online 2>/dev/null)" = "1" ] && exit 1
    exit 0
  '';
in {
  # Make the helper available to system-level NixOS modules via
  # _module.args, and to every Home Manager user via sharedModules
  # (Home Manager has its own module-args system, isolated from the
  # system one). Both channels exist so any consumer — system unit,
  # session HM module — can declare `{ on-battery, ... }:` and get
  # the script without re-deriving it.
  _module.args = {inherit on-battery;};

  home-manager.sharedModules = [
    {_module.args = {inherit on-battery;};}
  ];

  # Make the helper available on PATH too, for ad-hoc shell scripts and
  # interactive use.
  environment.systemPackages = [on-battery];

  # ── Power policy: power-profiles-daemon ─────────────────────────────
  # PPD is the upstream-blessed bridge between userspace power requests
  # ("performance / balanced / power-saver") and platform mechanisms.
  # On AMD systems with amd_pmf loaded (this hardware: AMDI0102:00) it
  # writes through to /sys/firmware/acpi/platform_profile so firmware,
  # kernel, and OS share one ladder. EPP is set per-CPU automatically.
  # auto-cpufreq is intentionally NOT enabled — the two daemons fight
  # over EPP and produce non-deterministic behaviour.
  #
  # Auto-switch on AC plug/unplug is driven by the udev rules below
  # (PPD itself is purely event-reactive — it does not poll battery
  # state). Host-specific EC daemons may extend the same AC-edge rules
  # with firmware-level TDP/fan profile changes; this generic laptop
  # profile deliberately handles only the OS-level PPD side.
  services.power-profiles-daemon.enable = true;

  # ── Lid handling: defer to the lid-monitor user service ─────────────
  # logind ignores the lid switch entirely so it does not race with us
  # on resume; the lid-monitor user service below polls /proc/acpi and
  # drives Hyprland DPMS off/on. Decoupling logind from lid events also
  # keeps the kernel from suspending the laptop when we just want the
  # screen off.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
  };

  # acpi.lid_init_state=open: Emdoor N155A firmware reports the lid as
  # closed on cold boot regardless of physical state, and never fires
  # Notify(LID, 0x80) on subsequent transitions. The kernel emits
  # "ACPI: button: The lid device is not compliant to SW_LID." in dmesg
  # to flag this. Forcing the initial state to "open" stops the kernel
  # from caching the bogus closed state and lets /proc/acpi/button/lid/
  # LID0/state track the real lid position once the polling loop starts.
  boot.kernelParams = ["acpi.lid_init_state=open"];

  systemd.user.services.lid-monitor = {
    description = "Poll /proc/acpi lid state and drive Hyprland DPMS";
    after = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    wantedBy = ["graphical-session.target"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${lidMonitorScript}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # ── udev: USB / NVMe / wakeup / PPD auto-switch ─────────────────────
  services.udev.extraRules = ''
    # USB autosuspend — 30s idle timeout. 2s was too aggressive and caused
    # HID disconnects on slow wireless dongles.
    ACTION=="add", SUBSYSTEM=="usb", TEST=="power/autosuspend", ATTR{power/autosuspend}="30"
    ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="auto"

    # HID input devices (mouse, keyboard, trackpad) must NEVER autosuspend.
    # ID_USB_INTERFACES=:0301* matches any USB device with HID boot interface (class 03).
    # Autosuspend on HID causes lag/disconnect when waking from sleep.
    ACTION=="add", SUBSYSTEM=="usb", ENV{ID_USB_INTERFACES}==":0301*", TEST=="power/control", ATTR{power/control}="on"

    # NVMe I/O scheduler — "none" is the recommendation for multi-queue NVMe,
    # especially DRAM-less drives. mq-deadline adds latency without throughput.
    ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"

    # Disable USB wakeup on XHCI to prevent instant-wake from suspend caused
    # by spurious IRQs from wireless dongles. Input still wakes screen via
    # Hyprland in userspace.
    ACTION=="add", SUBSYSTEM=="pci", DRIVER=="xhci_hcd", TEST=="power/wakeup", ATTR{power/wakeup}="disabled"

    # Disable I2C touchpad wakeup from suspend (false IRQs on s2idle entry).
    ACTION=="add", KERNEL=="PNP0C50:00", SUBSYSTEM=="i2c", TEST=="power/wakeup", ATTR{power/wakeup}="disabled"

    # ── PPD auto-switch on AC plug/unplug ──────────────────────────────
    # power-profiles-daemon does not watch power-supply state itself.
    # These rules drive `powerprofilesctl set <p>` from the AC adapter
    # online/offline edge so the system snaps to the right profile the
    # instant the cable goes in or out. AC defaults to `balanced` rather
    # than `performance`: performance remains available manually, while
    # balanced avoids needless EPP=performance fan/heat on a plugged-in
    # laptop sitting idle.
    SUBSYSTEM=="power_supply", KERNEL=="ADP1", ATTR{online}=="1", \
      RUN+="${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced"
    SUBSYSTEM=="power_supply", KERNEL=="ADP1", ATTR{online}=="0", \
      RUN+="${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver"
  '';
}
