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
#   - logind: ignore lid switch (lid-monitor handles blanking on its own).
#   - button.lid_init_state=ignore: do not trust the firmware's initial
#     _LID value. Emdoor N155A firmware is not SW_LID-compliant and the
#     kernel's button driver has no polling path for missing Notify(LID).
#   - lid-monitor user service: polls /proc/acpi/button/lid/LID0/state
#     five times a second and drives Hyprland DPMS for the internal
#     panel. Polling is the only reliable channel on firmware that does
#     not fire ACPI Notify(LID).
#   - udev rules: USB autosuspend, NVMe scheduler tuning,
#     XHCI/I2C wakeup disable to prevent spurious wake-from-suspend.
#   - exposes the `on-battery` helper script to consumers (e.g. hypridle)
#     via _module.args so they don't reach for /sys directly.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.laptop.lidMonitor;

  closeHook = pkgs.writeShellScript "lid-monitor-close-hook" (lib.concatStringsSep "\n" cfg.onClose);
  openHook = pkgs.writeShellScript "lid-monitor-open-hook" (lib.concatStringsSep "\n" cfg.onOpen);

  # Lid-state polling loop. Reads /proc/acpi/button/lid/LID0/state every
  # 200 ms and blanks/unblanks the internal panel on edge transitions
  # only. Initial state read primes `prev` so we never fire actions on
  # service startup.
  #
  # Two blanking strategies, selected by `hardware.laptop.lidMonitor.blanking`:
  #
  #   "backlight" (default): brightnessctl set 0 / restore. No DRM
  #     modeset, no eDP link retrain, no cursor plane teardown. Instant
  #     on/off, cursor stays put. Cost: panel stays powered (~0.5-1W
  #     higher than DPMS off). This is what GNOME/KDE do for lid-close
  #     "Screen Blank" — backlight-only, bypassing DRM entirely.
  #     Research: 2026-06-18-wayland-lid-dpms-real-behavior, §3-4.
  #
  #   "dpms": hyprctl dispatch dpms off/on. Full DRM modeset on re-enable
  #     (amdgpu DC stream teardown + link training = 2-3s lag). Hyprland
  #     warps cursor to default on single-output re-enable. Kept as a
  #     specialisation for fallback if backlight proves unsuitable.
  #
  # Why polling rather than acpi_listen/inotify:
  #   - acpid: depends on firmware firing Notify(LID, 0x80). Emdoor N155A
  #     does NOT fire it on every transition. Lost events = stuck DPMS.
  #   - inotify: /proc is synthesised — inotify never triggers on it.
  #   - polling: cheap at 5 Hz, guaranteed to catch every state.
  lidMonitorScript = pkgs.writeShellScript "lid-monitor" ''
    LID=/proc/acpi/button/lid/LID0/state
    HYPRCTL=${pkgs.hyprland}/bin/hyprctl
    BRIGHTNESSCTL=${pkgs.brightnessctl}/bin/brightnessctl
    CLOSE_HOOK=${closeHook}
    OPEN_HOOK=${openHook}
    BLANKING="${cfg.blanking}"
    STATE_FILE="''${XDG_RUNTIME_DIR:-/tmp}/lid-state"

    if [ ! -r "$LID" ]; then
      echo "lid-monitor: $LID unreadable, exiting" >&2
      exit 1
    fi

    # Prime previous state so the first iteration does not fire actions.
    read -r _ prev < "$LID"

    while sleep 0.2; do
      read -r _ state < "$LID" || continue
      if [ "$state" != "$prev" ]; then
        case "$state" in
          closed)
            case "$BLANKING" in
              disable)
                # Compositor removes eDP-1 from layout. Workspaces
                # stay in memory; on single-output there's nowhere to
                # evacuate, so they return on re-enable.
                "$HYPRCTL" keyword monitor "eDP-1, disable" || true
                ;;
              backlight)
                # Save current brightness, then dim to 0. No DRM modeset.
                "$BRIGHTNESSCTL" -d amdgpu_bl1 -s get > "$STATE_FILE" 2>/dev/null || true
                "$BRIGHTNESSCTL" -d amdgpu_bl1 set 0 2>/dev/null || true
                ;;
              dpms)
                # DPMS mode: save cursor, then dpms off.
                "$HYPRCTL" cursorpos 2>/dev/null | tr ',' ' ' > "$STATE_FILE" || true
                "$HYPRCTL" dispatch dpms off eDP-1 || true
                ;;
            esac
            "$CLOSE_HOOK" || true
            ;;
          open)
            "$OPEN_HOOK" || true
            case "$BLANKING" in
              disable)
                # Re-enable eDP-1 with its native mode + scale.
                "$HYPRCTL" keyword monitor "eDP-1, 2880x1800@120, 0x0, 1.8" || true
                ;;
              backlight)
                # Restore saved brightness. Instant — no modeset, no lag.
                if [ -r "$STATE_FILE" ]; then
                  "$BRIGHTNESSCTL" -d amdgpu_bl1 -r 2>/dev/null || true
                  rm -f "$STATE_FILE"
                else
                  "$BRIGHTNESSCTL" -d amdgpu_bl1 set 50% 2>/dev/null || true
                fi
                ;;
              dpms)
                # DPMS mode: dpms on, then restore cursor after modeset settles.
                "$HYPRCTL" dispatch dpms on eDP-1 || true
                if [ -r "$STATE_FILE" ]; then
                  pos=$(cat "$STATE_FILE")
                  if [ -n "$pos" ]; then
                    sleep 3 && "$HYPRCTL" dispatch movecursor $pos >/dev/null 2>&1 || true &
                  fi
                  rm -f "$STATE_FILE"
                fi
                ;;
            esac
            ;;
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
  options.hardware.laptop.lidMonitor = {
    blanking = lib.mkOption {
      type = lib.types.enum ["disable" "dpms" "backlight"];
      default = "dpms";
      description = ''
        How to blank the internal panel on lid close.
        - "disable": hyprctl keyword monitor eDP-1 disable. Compositor
          removes output from layout, full modeset on re-enable. Cursor
          and windows may shift.
        - "dpms": hyprctl dpms off/on. Full modeset, 2-3s lag on
          re-enable, cursor jumps. Lower power.
        - "backlight": brightnessctl set 0 / restore. No DRM modeset,
          instant, cursor preserved. Panel stays powered. May not
          fully black the panel.
      '';
    };

    onClose = lib.mkOption {
      type = lib.types.listOf lib.types.lines;
      default = [];
      description = "Shell snippets run by lid-monitor when the lid closes.";
    };

    onOpen = lib.mkOption {
      type = lib.types.listOf lib.types.lines;
      default = [];
      description = "Shell snippets run by lid-monitor when the lid opens.";
    };
  };

  config = {
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

    # button.lid_init_state=ignore: do not emit a bogus initial SW_LID state
    # from the firmware's cached _LID value. The button driver still depends
    # on Notify(LID, 0x80), which this firmware does not reliably send, so
    # the user service below remains the source of truth via direct _LID
    # evaluation through /proc/acpi/button/lid/LID0/state.
    boot.kernelParams = ["button.lid_init_state=ignore"];

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
  };
}
