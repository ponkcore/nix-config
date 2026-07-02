# networking.nix — NetworkManager-based connectivity.
#
# Universal: NM works on laptops, desktops and VMs. The hostname is
# injected by lib/mkHost.nix from the host attribute name; we do NOT
# set it here.
#
# Hardware-specific WiFi quirks (rtw89 power saving, regulatory domain,
# ASPM workarounds) belong in the host's hardware.nix.
_: {
  networking.networkmanager = {
    enable = true;
    # WiFi powersave DISABLED. rtw89 (RTL8852BE) + 802.11 PSM causes
    # repeated deauthentications: the driver goes to sleep, misses
    # beacons, and the AP kicks the client (reason 3 = DEAUTH_LEAVING
    # locally_generated, reason 15 = 4WAY_HANDSHAKE_TIMEOUT on
    # reconnect). This worsens when the screen turns off (DPMS idle)
    # because the system enters a lower power state and PS deepens.
    # Disabling NM powersave stops the mac80211 PS flag from being set,
    # keeping the radio awake at the cost of ~0.4-0.8W.
    # The rtw89 module-level disable_ps_mode is NOT set (kernel 7.0.5+
    # beacon tracking fix), but NM powersave independently triggers PSM
    # negotiation with the AP — this is the layer that causes the issue.
    # Source: journalctl boot -7 analysis 2026-06-27 (8 deauth events
    # in 15h session, correlated with idle/DPMS periods).
    wifi.powersave = false;
    # Prevent NM from managing libvirt's NAT bridge — virbr0 is owned
    # by libvirtd (dnsmasq + iptables NAT). If NM touches it, network
    # conflicts and broken VM connectivity result.
    unmanaged = ["virbr0"];
  };

  # 26.05: networking.wireless.enable = false removed — the 26.05 NM
  # module sets networking.wireless.enable = mkDefault true internally
  # and handles wpa_supplicant correctly. Explicitly setting false
  # conflicts with the new module logic.

  # ModemManager — nothing on these hosts uses cellular modems.
  networking.modemmanager.enable = false;

  # TDLS key installation bug — fixed via kernel patch (boot.kernelPatches
  # in hosts/lecoo/default.nix). The D-Bus TdlsExternalControl dispatcher
  # was a workaround that did NOT work (wpa_supplicant still processed
  # incoming TDLS requests). Removed after kernel patch confirmed working:
  # 0 key-addition failures with TDLS peer active post-reboot.
  # Source: research 2026-06-28-rtw89-key-addition-failure.result.md
}
