# hosts/lecoo/hardware.nix — host-specific hardware quirks.
#
# Things that ONLY apply to this physical machine:
#   - RTL8852BE WiFi driver power-saving / ASPM workarounds
#   - Regulatory domain (RU)
#   - NVMe ACPI quirk for the YMTC PC41Q drive
#   - 8250 UART probe disable (no physical serial port on this laptop)
{lib, ...}: {
  # RTL8852BE: rtw89 enters low-power sleep, misses AP beacons, then
  # wpa_supplicant triggers a disconnect. Disable the driver's PS mode
  # and PCIe ASPM. cfg80211 regdom forces RU (was PA from firmware).
  boot.extraModprobeConfig = ''
    options rtw89_core disable_ps_mode=Y
    options rtw89_pci disable_aspm_l1=Y disable_aspm_l1ss=Y disable_clkreq=Y
    options cfg80211 ieee80211_regdom=RU
  '';

  # Host-specific kernel parameters layered on top of the universal +
  # AMD CPU + AMD GPU + laptop profiles. mkAfter pins these at the
  # tail of /proc/cmdline so a `cat /proc/cmdline` reads naturally:
  # universal quiet → hardware-class tunings → host-only quirks.
  boot.kernelParams = lib.mkAfter [
    # Skip NVMe ACPI power management — works around suspend bugs on
    # certain DRAM-less drives, including this YMTC PC41Q.
    "nvme_noacpi=1"

    # 8250 UART driver is built-in (CONFIG_SERIAL_8250=y), so a modprobe
    # blacklist has no effect. nr_uarts=0 tells the built-in driver to
    # register zero UARTs at boot — eliminates ttyS0..ttyS3 and the
    # ~4.3s serial probe in systemd-analyze blame.
    "8250.nr_uarts=0"
  ];

  # sp5100_tco — AMD southbridge watchdog, causes "shutdown" warnings
  # on this platform and provides no value (auto-cpufreq + lecoo-ec-daemon
  # handle thermal/power policy already).
  boot.blacklistedKernelModules = ["sp5100_tco"];
}
