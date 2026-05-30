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
  #     during the brief window between cage exit and Hyprland's DRM
  #     take-over no longer reaches the panel.
  #   - The shutdown unmount diagnostics. systemd-shutdown (PID 1, after
  #     journald is gone) writes via kmsg + /dev/console; with vtcon1
  #     unbound those writes go nowhere visible.
  #
  # What still works:
  #   - Plymouth: paints via DRM directly, not through vtcon — unaffected.
  #   - Hyprland: Wayland → DRM, no VT dependency — unaffected.
  #   - greetd + cage: Wayland kiosk — unaffected.
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
  #   1. plymouth-quit → greeter compositor handoff (cage's `-s` flag
  #      issues VT_ACTIVATE; the kernel re-binds fbcon to whatever
  #      framebuffer is primary).
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

  # Disable services that polled or waited unnecessarily on shutdown.
  systemd.services.systemd-udev-settle.enable = false;
  systemd.services.NetworkManager-wait-online.enable = false;
}
