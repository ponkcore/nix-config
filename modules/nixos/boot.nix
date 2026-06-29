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
  # consoleLogLevel = 3 allows KERN_ERR on the console (hardware errors,
  # NVMe failures, GPU hangs) while keeping boot visually silent with
  # Plymouth + quiet. loglevel=0 suppressed all diagnostics — loglevel=3
  # is the community-standard compromise for production laptops.
  # Source: research 2026-06-29-nixos-laptop-comparative-audit §W-10
  boot.consoleLogLevel = 3;
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
    # fbcon=defer is intentionally NOT set — the kernel already has
    # CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER=y, which prevents
    # fbcon from binding until the first console write. With quiet +
    # loglevel=0 no writes occur during boot, so fbcon stays dormant
    # the entire time. Previously `fbcon=nodefer` was set here, which
    # DISABLED deferred takeover and caused fbcon to bind immediately
    # on every framebuffer registration (UEFI GOP at ~0.9s, amdgpudrmfb
    # at ~3.6s) — visible as console text flashing before/around
    # Plymouth and during the greeter→Hyprland handoff.
    "logo.nologo"
    # Notably absent: `plymouth.use-simpledrm` (was set previously
    # to anchor the splash to the firmware framebuffer; root-cause
    # research showed simpledrm is the *cause* of the upper-left
    # corner sub-native render, not the cure — UEFI GOP exposes a
    # ~1024x768 cloned framebuffer to both panels). Removing it
    # makes Plymouth wait up to DeviceTimeout=8s for amdgpu, which
    # by then has done EDID negotiation and produced a clean
    # native-resolution head per connector.
    #
    # No `video=HDMI-A-1:d` connector gating: this host is used as a
    # single-panel laptop (eDP-1 only). With no external connector
    # live at boot, Plymouth enumerates a single head on eDP-1
    # naturally. The HDMI connector is left fully hot-pluggable — if
    # an external monitor is ever plugged in, it works through the
    # generic `, preferred, auto, 1` fallback in session.nix with no
    # rearm dance. The only cosmetic cost of dropping the gate is
    # that booting *with* a monitor already attached would mirror the
    # splash across both panels; acceptable since boot-time docking
    # is not a workflow here.
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

  # ── Silent VT (removed on kernel 6.18) ──────────────────────────────
  # The silent-vt and silent-vt-keep services that unbound vtcon1
  # (the framebuffer console) were removed after the kernel 6.18
  # upgrade. With CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER=y +
  # quiet + loglevel=0, the kernel never creates vtcon1 at all —
  # fbcon stays dormant for the entire boot. Both services were
  # skipped every boot (ConditionPathExists unmet) and were dead
  # code. Research: 2026-06-26-silent-boot-greeter-alternatives.

  # Suppress console output during shutdown. systemd-shutdown's internal
  # bump_sysctl_printk_log_level overrides boot.consoleLogLevel, so we
  # zero printk one-shot right before shutdown.target activates. Covers
  # the panic-grade path too, since panics ignore console_loglevel via
  # emergency_write.
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
