# hosts/lecoo/hardware.nix — host-specific hardware quirks.
#
# Things that ONLY apply to this physical machine:
#   - RTL8852BE WiFi driver ASPM workaround (PS mode fixed in kernel 7.0.5)
#   - Regulatory domain (RU)
#   - NVMe ACPI quirk for the YMTC PC41Q drive
#   - 8250 UART probe disable (no physical serial port on this laptop)
{lib, ...}: {
  # RTL8852BE: rtw89 PCIe ASPM L1 sub-states cause PCIe errors on this
  # chip — keep them disabled. PS mode was disabled due to a beacon
  # miss bug, but the fix landed in kernel 6.20+ (beacon tracking
  # series) and is present in kernel 7.0.5 (linuxPackages_latest).
  # PS is now enabled by default — confirmed stable with 2-min ping
  # test, 0% packet loss, no disconnects.
  # cfg80211 regdom forces RU (was PA from firmware).
  boot.extraModprobeConfig = ''
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

  # sp5100_tco — AMD southbridge hardware watchdog timer.
  # Previously blacklisted for "shutdown warnings" but now re-enabled
  # as the primary DMCUB crash recovery mechanism. When systemd pings
  # /dev/watchdog every 15s (RuntimeWatchdogSec=30s), a total system
  # freeze (e.g., amdgpu DMCUB firmware crash → flip_done timeout →
  # hard lockup) stops the pings, and the hardware watchdog triggers
  # an automatic system reset after 30s — no manual reboot required.
  # The "shutdown warnings" were cosmetic (spurious events during
  # normal shutdown when systemd closes the watchdog device); they
  # do not affect runtime operation.
  boot.kernelModules = ["sp5100_tco"];
}
