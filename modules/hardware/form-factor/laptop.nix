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
#   - lid-monitor user service: sole owner of display blanking. Polls
#     /proc/acpi/button/lid/LID0/state five times a second AND checks an
#     idle-flag file ($XDG_RUNTIME_DIR/hyprland-idle) set by hypridle.
#     Blanks when lid closed OR idle flag exists; restores only when
#     both are clear. This unified ownership eliminates the race where
#     hypridle's on-resume re-enables a closed panel on mouse activity.
#     Polling is the only reliable lid channel on firmware that does
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

  # Lid-state + idle-flag polling loop. Reads /proc/acpi/button/lid/
  # LID0/state every 200 ms and checks $XDG_RUNTIME_DIR/hyprland-idle
  # (set by hypridle after 5 min inactivity on battery, cleared on any
  # input activity). Blanks when lid closed OR idle flag exists; restores
  # only when both are clear. This makes lid-monitor the single owner of
  # display blanking state — hypridle never calls hyprctl directly,
  # eliminating the race where on-resume re-enables a closed panel.
  #
  # Hooks (onClose/onOpen) fire on lid-edge transitions only, never on
  # idle-flag changes. Initial lid state read primes `prev_lid` so hooks
  # don't fire on service startup. The `blanked` flag prevents redundant
  # DPMS/backlight commands on every poll iteration.
  #
  # Three blanking strategies, selected by `hardware.laptop.lidMonitor.blanking`:
  #
  #   "dpms" (default): hyprctl dispatch dpms off/on. Full DRM modeset
  #     on re-enable (amdgpu DC stream teardown + link training = 2-3s
  #     lag). Hyprland warps cursor to default on single-output
  #     re-enable. Lowest power (panel + link powered down).
  #
  #   "backlight": brightnessctl set 0 / restore. No DRM modeset, no
  #     eDP link retrain, no cursor plane teardown. Instant on/off,
  #     cursor stays put. Cost: panel stays powered (~0.5-1W higher
  #     than DPMS off). May not fully black the panel (residual glow).
  #     Research: 2026-06-18-wayland-lid-dpms-real-behavior, §3-4.
  #
  #   "disable": hyprctl keyword monitor eDP-1 disable. Compositor
  #     removes output from layout, full modeset on re-enable. Cursor
  #     and windows may shift. Kept as a specialisation fallback.
  #
  # Why polling rather than acpi_listen/inotify:
  #   - acpid: depends on firmware firing Notify(LID, 0x80). Emdoor
  #     N155A does NOT fire it on every transition. Lost events = stuck.
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
    IDLE_FLAG="''${XDG_RUNTIME_DIR:-/tmp}/hyprland-idle"

    if [ ! -r "$LID" ]; then
      echo "lid-monitor: $LID unreadable, exiting" >&2
      exit 1
    fi

    # Prime previous lid state so hooks don't fire on startup.
    read -r _ prev_lid < "$LID"
    blanked=false

    while sleep 0.2; do
      read -r _ lid < "$LID" || continue

      # Idle flag is set by hypridle after 5 min inactivity on battery,
      # cleared on any input activity. lid-monitor is the sole owner of
      # DPMS/backlight state — hypridle never calls hyprctl directly.
      idle=no
      [ -f "$IDLE_FLAG" ] && idle=yes

      # Blank if lid closed OR idle. Restore only when both are clear.
      want_blank=false
      [ "$lid" = "closed" ] && want_blank=true
      [ "$idle" = "yes" ] && want_blank=true

      # Fire lid-edge hooks only on actual lid state transitions.
      if [ "$lid" != "$prev_lid" ]; then
        case "$lid" in
          closed) "$CLOSE_HOOK" || true ;;
          open) "$OPEN_HOOK" || true ;;
        esac
      fi

      # Apply blanking state transitions.
      if [ "$want_blank" = true ] && [ "$blanked" = false ]; then
        case "$BLANKING" in
          disable)
            "$HYPRCTL" keyword monitor "eDP-1, disable" || true
            ;;
          backlight)
            "$BRIGHTNESSCTL" -d amdgpu_bl1 -s get > "$STATE_FILE" 2>/dev/null || true
            "$BRIGHTNESSCTL" -d amdgpu_bl1 set 0 2>/dev/null || true
            ;;
          dpms)
            "$HYPRCTL" dispatch dpms off eDP-1 || true
            ;;
        esac
        blanked=true
      elif [ "$want_blank" = false ] && [ "$blanked" = true ]; then
        case "$BLANKING" in
          disable)
            "$HYPRCTL" keyword monitor "eDP-1, 2880x1800@120, 0x0, 1.8" || true
            ;;
          backlight)
            if [ -r "$STATE_FILE" ]; then
              "$BRIGHTNESSCTL" -d amdgpu_bl1 -r 2>/dev/null || true
              rm -f "$STATE_FILE"
            else
              "$BRIGHTNESSCTL" -d amdgpu_bl1 set 50% 2>/dev/null || true
            fi
            ;;
          dpms)
            "$HYPRCTL" dispatch dpms on eDP-1 || true
            # Force cursor plane re-commit after DPMS-on. Hyprland
            # 0.52.1 does not re-commit the hardware cursor plane on
            # DPMS-on — the cursor becomes invisible until moved.
            # movecursor to current position triggers onCursorMoved
            # → moveCursor backend call, re-committing the plane.
            # With no_hardware_cursors=true (software cursor) this
            # is belt-and-suspenders; without it, it's the primary
            # fix. 0.1 s sleep lets commitDPMSState finish first.
            # Source: research 2026-06-26-system-pain-points-deep-research §1.4
            ${pkgs.coreutils}/bin/sleep 0.1
            POS="$("$HYPRCTL" cursorpos 2>/dev/null | tr ',' ' ')"
            [ -n "$POS" ] && "$HYPRCTL" dispatch movecursor $POS 2>/dev/null || true
            ;;
        esac
        blanked=false
      fi

      prev_lid="$lid"
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
    boot.kernelParams = [
      "button.lid_init_state=ignore"
      # pcie_aspm=force: the kernel __setup parser only accepts "off"
      # and "force" — "powersave" is silently ignored (source:
      # drivers/pci/pcie/aspm.c, kernel 6.18). `force` overrides the
      # FADT NO_ASPM flag that BIOS sets on Phoenix platforms, enabling
      # ASPM L1 on devices that support it. A systemd oneshot also
      # writes "powersave" to the policy sysfs at boot as belt-and-
      # suspenders. rtw89 WiFi ASPM stays disabled via modprobe.
      # Source: research 2026-06-27-battery-unsolved-deep-research §2
      "pcie_aspm=force"
    ];

    # Write ASPM policy to powersave at boot. The kernel param `force`
    # overrides the FADT NO_ASPM flag, but the policy sysfs still
    # shows [default]. This oneshot sets it to powersave explicitly.
    # Confirmed working via runtime `echo powersave > .../policy`.
    systemd.services.aspm-powersave = {
      description = "Set PCIe ASPM policy to powersave";
      after = ["systemd-udevd.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.bash}/bin/bash -c 'echo powersave > /sys/module/pcie_aspm/parameters/policy 2>/dev/null || true'";
      };
    };

    systemd.user.services.lid-monitor = {
      description = "Poll lid state + idle flag, sole owner of display blanking";
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

    # ── Post-PPD EPP override on battery ───────────────────────────────
    # PPD power-saver sets EPP=power (0xFF) — parks cores at ~1.4 GHz,
    # slow ramp, causes cold-start lag. This service runs 2 s after
    # PPD settles on battery unplug and overrides EPP to balance_power
    # (0xBF): faster ramp-up while keeping platform_profile=low-power
    # (~15W TDP) for battery life. Trade-off: slightly higher idle
    # power vs power-saver, but no more 1.4 GHz core parking.
    # SKIPPED when eco mode is active — eco mode wants EPP=power (0xFF)
    # for maximum efficiency. The eco toggle writes a state file that
    # this service checks before overriding.
    # Source: research 2026-06-25-amd-phoenix-power-ec-deep-research §1b
    # Source: research 2026-06-27-battery-unsolved-deep-research §4
    systemd.services.battery-epp-override = {
      description = "Override EPP to balance_power on battery (post-PPD)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "battery-epp-override" ''
          # Skip if eco mode is active — eco wants EPP=power (0xFF).
          for runtime in /run/user/*/ultra-economy; do
            if [ -r "$runtime/state" ] && [ "$(cat "$runtime/state" 2>/dev/null)" = "on" ]; then
              exit 0
            fi
          done
          sleep 2
          for cpu in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
            echo balance_power > "$cpu" 2>/dev/null || true
          done
        '';
      };
    };

    # ── GPU DPM force low on battery ────────────────────────────────────
    # Force the Radeon 780M iGPU to its lowest power state on battery
    # to reduce GPU idle power draw (~1.6W → lower). Restored to auto
    # on AC. power_dpm_force_performance_level is available on iGPU
    # (unlike pp_power_profile_mode which requires manual level).
    # Risk: on high-refresh external displays this can cause bandwidth
    # artefacts — but we no longer use external displays. eDP-1 at
    # 2880×1800@120 is within the low DPM bandwidth budget.
    # Source: research 2026-06-26-system-pain-points-deep-research §4.4
    # GPU is at card1 on this hardware (amdgpu loads after a virtual
    # card0 is not created). Hosts/lecoo/ec.nix syncPowerProfile also
    # uses card1 — keep in sync.
    systemd.services.battery-gpu-dpm = {
      description = "Force GPU DPM low on battery";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "battery-gpu-dpm" ''
          sleep 3
          echo low > /sys/class/drm/card1/device/power_dpm_force_performance_level 2>/dev/null || true
        '';
      };
    };

    systemd.services.ac-gpu-dpm-restore = {
      description = "Restore GPU DPM auto on AC";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "ac-gpu-dpm-restore" ''
          echo auto > /sys/class/drm/card1/device/power_dpm_force_performance_level 2>/dev/null || true
        '';
      };
    };

    # ── udev: USB / NVMe / wakeup / PPD auto-switch ─────────────────────
    services.udev.extraRules = ''
      # USB autosuspend — 2s idle timeout for non-HID devices.
      # HID devices (mouse, keyboard, trackpad) are re-excluded below
      # with power/control=on, so the 2s timeout doesn't affect them.
      # 30s was leaving USB controllers powered too long on battery.
      ACTION=="add", SUBSYSTEM=="usb", TEST=="power/autosuspend", ATTR{power/autosuspend}="2"
      ACTION=="add", SUBSYSTEM=="usb", TEST=="power/control", ATTR{power/control}="auto"

      # HID input devices (mouse, keyboard, trackpad) must NEVER autosuspend.
      # ID_USB_INTERFACES=:0301* matches any USB device with HID boot interface (class 03).
      # Autosuspend on HID causes lag/disconnect when waking from sleep.
      ACTION=="add", SUBSYSTEM=="usb", ENV{ID_USB_INTERFACES}==":0301*", TEST=="power/control", ATTR{power/control}="on"

      # NVMe runtime PM — allow the NVMe controller PCI device to enter
      # D3 (DEVSLP) when idle. APST is already enabled (confirmed via
      # nvme get-feature 0x0c), so the drive transitions to PS3 (25 mW)
      # / PS4 (4 mW) on its own. Runtime PM adds PCI D3 on top, saving
      # an additional 0.3-0.8 W. Safe with nvme_noacpi=1 (that only
      # disables ACPI PM, not runtime PM). Matches PCI class 0x010802
      # (NVM controller) — the power/control sysfs is on the PCI device,
      # not the nvme class device.
      ACTION=="add", SUBSYSTEM=="pci", ATTR{class}=="0x010802", TEST=="power/control", ATTR{power/control}="auto"

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
      # laptop sitting idle. Battery defaults to `power-saver` for
      # maximum battery life (EPP=power 0xFF, platform_profile=low-power
      # ~15W TDP). The cold-start lag this causes is accepted in favour
      # of runtime. If responsiveness becomes a priority, `balanced` on
      # battery removes the double throttle — see research
      # 2026-06-25-amd-phoenix-power-ec-deep-research.result.md §1a/1d.
      SUBSYSTEM=="power_supply", KERNEL=="ADP1", ATTR{online}=="1", \
        RUN+="${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced", \
        RUN+="${pkgs.systemd}/bin/systemctl start ac-gpu-dpm-restore.service"
      SUBSYSTEM=="power_supply", KERNEL=="ADP1", ATTR{online}=="0", \
        RUN+="${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver", \
        RUN+="${pkgs.systemd}/bin/systemctl start battery-epp-override.service", \
        RUN+="${pkgs.systemd}/bin/systemctl start battery-gpu-dpm.service"
    '';
  };
}
