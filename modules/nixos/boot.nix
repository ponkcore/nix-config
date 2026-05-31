# boot.nix — bootloader, kernel boot output, Plymouth splash, initrd policy.
#
# Universal: any x86_64 system with EFI runs this as-is. Hardware-specific
# kernel parameters (amd_pstate, iommu, NVMe quirks, the 8250 disable, etc.)
# live in modules/hardware/ and are opted in per host.
{
  lib,
  pkgs,
  ...
}: {
  # Bootloader — systemd-boot with no menu (auto-boot default entry).
  # configurationLimit caps the boot menu so old generations don't pile up
  # in /boot. nix.gc.options separately deletes the underlying store paths.
  boot.loader = {
    systemd-boot = {
      enable = true;
      editor = false;
      configurationLimit = 7;
    };
    efi.canTouchEfiVariables = true;
    timeout = 0;
  };

  # Quiet boot — shave every visible message between firmware and Plymouth.
  # consoleLogLevel = 0 silences ALL kernel output except KERN_EMERG.
  # initrd.systemd.enable is required for rd.systemd.show_status=false to
  # actually take effect (older sysv-style initrd ignores it).
  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;
  boot.initrd.systemd.enable = true;

  # Universal quiet-boot kernel parameters — apply on any hardware.
  # Hardware-specific params (amd_pstate, NVMe ACPI quirks, etc.) live in
  # modules/hardware/ profiles. Pinned at the front of /proc/cmdline so
  # the universal "shape the boot output" intent is read first when
  # debugging cmdline regressions.
  boot.kernelParams = lib.mkBefore [
    "quiet"
    "udev.log_level=3"
    "rd.systemd.show_status=false"
    "rd.udev.log_level=3"
    "systemd.show_status=false"
    "plymouth.ignore-serial-consoles"
    "vt.global_cursor_default=0"
    "fbcon=nodefer"
    "logo.nologo"
    # Plymouth single-output policy — splash on the internal eDP
    # panel only.
    #
    # Background: Plymouth has no per-connector gating in upstream.
    # ply-device-manager.c picks one DRM card and renders one head
    # per connected connector on it; there is no allow-list /
    # deny-list / device= knob (verified against Plymouth 24.004.60
    # source — those tokens are forum mythology, not upstream API).
    # Multi-connector behaviour must therefore be gated *below*
    # Plymouth, in the kernel DRM layer.
    #
    # `video=HDMI-A-1:d` tells the DRM core to force HDMI-A-1 to
    # `disconnected` before any driver / userspace probe runs.
    # amdgpu sees the connector as off, Plymouth never enumerates
    # a head for it, the splash renders at native 2880x1800 on
    # eDP-1 only with HDMI dark.
    #
    # Notably absent: `plymouth.use-simpledrm` (was set previously
    # to anchor the splash to the firmware framebuffer; root-cause
    # research showed simpledrm is the *cause* of the upper-left
    # corner sub-native render, not the cure — UEFI GOP exposes a
    # ~1024x768 cloned framebuffer to both panels). Removing it
    # makes Plymouth wait up to DeviceTimeout=8s for amdgpu, which
    # by then has done EDID negotiation and produced a clean
    # native-resolution head per connector.
    #
    # Trade-off accepted: HDMI-A-1 stays force-disabled at the
    # kernel level until something writes `on` to
    # /sys/class/drm/card*-HDMI-A-1/status — Hyprland's `monitor
    # =HDMI-A-1, ...` directive does this implicitly when it
    # claims the connector at session start, so the user-session
    # behaviour does not change. If a future change drops the
    # explicit `monitor=HDMI-A-1` line, this kernel param will
    # also need to be revisited (or replaced with `video=HDMI-A-1
    # :e` to leave the connector hot-pluggable).
    #
    # Research backing:
    # researches/2026-05-30-plymouth-single-output-multimonitor
    # .result.md (talos-brain). Source primary references:
    # ply-device-manager.c, drm renderer plugin.c, kernel
    # fb/modedb.html.
    "video=HDMI-A-1:d"
  ];

  # Plymouth boot splash — abstract_ring theme from adi1090x collection.
  # NOT disabling plymouth-quit: the script theme segfaults on keyboard
  # input past multi-user.target. Plymouth's built-in shutdown services
  # (plymouth-poweroff, plymouth-reboot) handle the shutdown splash.
  boot.plymouth = {
    enable = true;
    theme = "abstract_ring";
    themePackages = [pkgs.adi1090x-plymouth-themes];
  };

  # ── Silent VT after Plymouth quits ────────────────────────────────────
  # The exhibition-grade silent-boot mute. After Plymouth finishes the
  # boot splash, we sever the kernel-console ↔ framebuffer link by writing
  # 0 to /sys/class/vtconsole/vtcon1/bind (vtcon1 is the framebuffer
  # console; vtcon0 is the dummy fallback that stays bound).
  #
  # Effect on the visible regressions:
  #   - The post-greeter handoff. xdg-desktop-portal-hyprland's verbose
  #     interface registration log goes to journald (the user-units route
  #     stdout/stderr there), but anything that DOES escape to /dev/console
  #     during the brief window between sway-kiosk exit and Hyprland's
  #     DRM take-over no longer reaches the panel.
  #   - The shutdown unmount diagnostics. systemd-shutdown (PID 1, after
  #     journald is gone) writes via kmsg + /dev/console; with vtcon1
  #     unbound those writes go nowhere visible.
  #
  # What still works:
  #   - Plymouth: paints via DRM directly, not through vtcon — unaffected.
  #   - Hyprland: Wayland → DRM, no VT dependency — unaffected.
  #   - greetd + sway-kiosk + nwg-hello: Wayland greeter — unaffected.
  #   - journald: every message remains addressable via journalctl.
  #   - KERN_EMERG / kernel panics: bypass console_loglevel and the vtcon
  #     binding via emergency_write_handler; still reach the panel.
  #
  # What's traded:
  #   - Ctrl+Alt+F1..F6 TTY switching shows a blank panel until vtcon1 is
  #     re-bound (`sudo sh -c 'echo 1 > /sys/class/vtconsole/vtcon1/bind'`).
  #     On a single-user laptop running a Wayland session this is an
  #     acceptable trade for completely silent boot/shutdown.
  #
  # Ordered BEFORE plymouth-quit so the fbcon→VT transport is already
  # severed by the time Plymouth releases the splash. The previous
  # "after plymouth-quit-wait + multi-user.target" form left a ~220 ms
  # window between Plymouth handoff and unbind during which the kernel
  # console flushed any queued text frames to the panel — visible as a
  # log flash before the greeter appeared. Plymouth paints exclusively
  # via DRM, not vtcon (see plymouthd source / theme renderer), so
  # detaching fbcon mid-splash does not affect the splash itself.
  #
  # ConditionKernelCommandLine guards keep the unbind from running on
  # explicit rescue / emergency boots, preserving a usable diagnostic
  # console in those modes. Runtime `systemctl rescue` is unaffected
  # because the unit has already run and remains active (oneshot +
  # RemainAfterExit); a re-isolated rescue.target does not retrigger it.
  systemd.services.silent-vt = {
    description = "Detach kernel console from framebuffer for silent boot";
    after = ["plymouth-start.service"];
    before = ["plymouth-quit.service"];
    wantedBy = ["plymouth-quit.service"];
    unitConfig = {
      ConditionPathExists = "/sys/class/vtconsole/vtcon1/bind";
      ConditionKernelCommandLine = [
        "!systemd.unit=rescue.target"
        "!systemd.unit=emergency.target"
      ];
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'echo 0 > /sys/class/vtconsole/vtcon1/bind'";
      StandardOutput = "null";
      StandardError = "null";
    };
  };

  # silent-vt-keep — closes the second log-flash window observed on
  # 2026-05-30. After silent-vt unbinds vtcon1, two later events re-bind
  # fbcon to amdgpudrmfb and flash queued console output to the panel:
  #
  #   1. plymouth-quit → greeter compositor handoff (sway opens its
  #      DRM backend on the active VT; the kernel re-binds fbcon to
  #      whatever framebuffer is primary).
  #   2. greeter compositor exit → user Hyprland startup (libseat
  #      session take-over via logind triggers the same path).
  #
  # Each re-bind flushes any pending /dev/console writes that systemd /
  # systemd-logind / D-Bus accumulated since the last unbind. Visible
  # as a brief log flash before the greeter or before the desktop.
  #
  # The keeper polls /sys/class/vtconsole/vtcon1/bind twice per second
  # for 120 seconds (covers both handoffs with plenty of margin) and
  # writes 0 whenever the kernel re-binds it. Cost: ~240 read syscalls
  # over the boot. After 120 s the keeper exits — by then the system
  # is in steady state and no more compositor handoffs occur until
  # logout/shutdown.
  #
  # On rescue / emergency boots the unit does not run (same condition
  # as silent-vt) so a usable console is preserved.
  systemd.services.silent-vt-keep = {
    description = "Keep VT framebuffer console unbound during compositor handoffs";
    after = ["plymouth-quit.service"];
    wantedBy = ["plymouth-quit.service"];
    unitConfig = {
      ConditionPathExists = "/sys/class/vtconsole/vtcon1/bind";
      ConditionKernelCommandLine = [
        "!systemd.unit=rescue.target"
        "!systemd.unit=emergency.target"
      ];
    };
    serviceConfig = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "silent-vt-keep" ''
        for _ in $(seq 1 240); do
          if [ -e /sys/class/vtconsole/vtcon1/bind ] \
             && [ "$(cat /sys/class/vtconsole/vtcon1/bind)" = "1" ]; then
            echo 0 > /sys/class/vtconsole/vtcon1/bind
          fi
          sleep 0.5
        done
      '';
      Restart = "no";
      StandardOutput = "null";
      StandardError = "null";
      Nice = 10;
    };
  };

  # Suppress console output during shutdown. systemd-shutdown's internal
  # bump_sysctl_printk_log_level overrides boot.consoleLogLevel, so we
  # zero printk one-shot right before shutdown.target activates. Defence-
  # in-depth on top of the silent-vt unbind: covers the panic-grade path
  # too, since panics ignore vtcon bindings via emergency_write.
  systemd.services.shutdown-silence = {
    description = "Silence Console Before Shutdown";
    before = ["shutdown.target"];
    requiredBy = ["shutdown.target"];
    unitConfig = {
      DefaultDependencies = false;
      ConditionPathExists = "/proc/sys/kernel/printk";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'echo 0 0 0 0 > /proc/sys/kernel/printk'";
      StandardOutput = "null";
      StandardError = "null";
    };
  };

  # Re-enable HDMI-A-1 after Plymouth has finished.
  #
  # `video=HDMI-A-1:d` (set in boot.kernelParams above) tells the
  # kernel DRM core to force the HDMI connector into the OFF state
  # at boot — that is what gives us the single-output Plymouth
  # splash on eDP-1. The force is sticky: writing `on` to
  # /sys/class/drm/.../status flips the status field but does NOT
  # trigger a connector probe, so wlroots/Hyprland never see a
  # hotplug event and never bring the panel up. Empirically:
  # `cat status` reports `connected`, `hyprctl monitors` reports
  # only eDP-1.
  #
  # The reliable wake-up is amdgpu's `trigger_hotplug` debugfs
  # entry, which fires drm_helper_hpd_irq_event(). That routes
  # through wlroots' libdisplay-info path and Hyprland claims the
  # connector via its `monitor=HDMI-A-1, ...` directive.
  #
  # Ordered after plymouth-quit so the splash is already torn
  # down before we touch DRM. Idempotent — `trigger_hotplug` is
  # a write-1 trigger, repeats are harmless. Failure path: if
  # the debugfs entry is absent (kernel built without
  # CONFIG_DEBUG_FS, or amdgpu not the active driver), the
  # ConditionPathExists short-circuits and the unit completes
  # without action.
  # Re-arm the HDMI connector force-off before shutdown / reboot
  # so the Plymouth shutdown splash is single-output (eDP only),
  # mirroring the boot policy. Without this, by shutdown time
  # hdmi-rearm has already cleared the force flag, both connectors
  # are live, and the shutdown splash renders mirrored on both —
  # which both looks wrong and slows the shutdown sequence
  # (per-connector teardown, DPMS waits, etc; observed ~10 s
  # extra wait vs the single-output case).
  #
  # Symmetric with hdmi-rearm: writes `off` to status, then
  # triggers a hotplug so the kernel actually applies the force.
  # Ordered before shutdown.target so it lands while userspace is
  # still alive, before plymouth-shutdown takes over the screen.
  systemd.services.hdmi-disarm = {
    description = "Re-disable HDMI-A-1 before shutdown to single-output the shutdown splash";
    before = ["shutdown.target" "reboot.target" "halt.target"];
    requiredBy = ["shutdown.target" "reboot.target" "halt.target"];
    unitConfig = {
      DefaultDependencies = false;
      ConditionPathExists = "/sys/kernel/debug/dri/0000:6e:00.0/HDMI-A-1/trigger_hotplug";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = [
        "${pkgs.bash}/bin/bash -c 'for f in /sys/class/drm/card*-HDMI-A-1/status; do echo off > \"$f\"; done'"
        "${pkgs.bash}/bin/bash -c 'echo 1 > /sys/kernel/debug/dri/0000:6e:00.0/HDMI-A-1/trigger_hotplug'"
      ];
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Re-arming sequence — the order matters:
  #   1. write `detect` to /sys/class/drm/card*-HDMI-A-1/status — this
  #      lifts the force=DRM_FORCE_OFF flag set by `video=HDMI-A-1:d`
  #      on the kernel command line and returns the connector to
  #      auto-detect (EDID + HPD). Without this step the connector
  #      stays force-disabled across an entire boot, no matter how
  #      many hotplugs we trigger.
  #
  #      DO NOT write `on` here — that is DRM_FORCE_ON, which forces
  #      the connector to report `connected` even with no cable
  #      attached. Hyprland then creates a phantom 1920x1080 monitor
  #      from the `monitor=HDMI-A-1, ...` line, workspaces silently
  #      pin to it, waybar shows you switching workspaces that you
  #      cannot see. `detect` is the correct DRM verb — it lets the
  #      kernel probe the cable each time `trigger_hotplug` fires.
  #   2. write `1` to debugfs trigger_hotplug — this fires
  #      drm_helper_hpd_irq_event() which routes through wlroots
  #      and lets Hyprland claim the connector via its `monitor=
  #      HDMI-A-1, ...` directive.
  # Verified empirically (2026-05-30): trigger_hotplug alone is a
  # no-op while force is still set. With `detect` the unplugged
  # case reports `disconnected` and Hyprland skips the connector
  # cleanly; the plugged case probes EDID and brings the panel up.
  systemd.services.hdmi-rearm = {
    description = "Re-arm HDMI-A-1 connector after Plymouth quit";
    after = ["plymouth-quit.service"];
    wantedBy = ["multi-user.target"];
    unitConfig = {
      ConditionPathExists = "/sys/kernel/debug/dri/0000:6e:00.0/HDMI-A-1/trigger_hotplug";
    };
    serviceConfig = {
      Type = "oneshot";
      # RemainAfterExit pins the unit in `active (exited)` after
      # ExecStart returns, so a `nixos-rebuild switch` does NOT
      # re-trigger the hotplug write. Without this flag the unit
      # is `inactive (dead)` and every switch re-runs both
      # ExecStart commands — visible as a brief HDMI black flash.
      # Boot still re-runs the unit cleanly (state is fresh each
      # boot), shutdown is handled by the separate hdmi-disarm.
      RemainAfterExit = true;
      # Globbed paths — survive amdgpu enumerating as card0 vs card1
      # across kernel upgrades. The PCI address (0000:6e:00.0) is
      # stable for this host (Phoenix iGPU on Lenovo Lecoo Pro 14).
      ExecStart = [
        "${pkgs.bash}/bin/bash -c 'for f in /sys/class/drm/card*-HDMI-A-1/status; do echo detect > \"$f\"; done'"
        "${pkgs.bash}/bin/bash -c 'echo 1 > /sys/kernel/debug/dri/0000:6e:00.0/HDMI-A-1/trigger_hotplug'"
      ];
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Disable services that polled or waited unnecessarily on shutdown.
  systemd.services.systemd-udev-settle.enable = false;
  systemd.services.NetworkManager-wait-online.enable = false;
}
