# networking.nix — NetworkManager-based connectivity.
#
# Universal: NM works on laptops, desktops and VMs. The hostname is
# injected by lib/mkHost.nix from the host attribute name; we do NOT
# set it here.
#
# Hardware-specific WiFi quirks (rtw89 power saving, regulatory domain,
# ASPM workarounds) belong in the host's hardware.nix.
{pkgs, ...}: {
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
  };

  # 26.05: networking.wireless.enable = false removed — the 26.05 NM
  # module sets networking.wireless.enable = mkDefault true internally
  # and handles wpa_supplicant correctly. Explicitly setting false
  # conflicts with the new module logic.

  # ModemManager — nothing on these hosts uses cellular modems.
  networking.modemmanager.enable = false;

  # TDLS (Tunneled Direct Link Setup) — disable for rtw89.
  # The RTL8852BE driver fails to install TDLS peer keys (TPK),
  # producing `nl80211: kernel reports: key addition failed` and
  # `TDLS: Failed to set TPK to the driver`. After the failure,
  # WiFi appears "connected" but traffic stops flowing — user must
  # toggle WiFi off/on. wpa_supplicant repeatedly tries TDLS with
  # peers on the same BSS (e.g., Syncthing devices), triggering
  # the bug every few minutes. 55 failures in 14h observed.
  # NetworkManager controls wpa_supplicant via D-Bus (not config
  # files), so the dispatcher script uses dbus-send to set the
  # TdlsExternalControl property on the interface, which prevents
  # wpa_supplicant from initiating TDLS setup.
  # Source: journalctl 2026-06-28 — root cause analysis.
  networking.networkmanager.dispatcherScripts = [
    {
      source = pkgs.writeShellScript "nm-disable-tdls" ''
        IFACE="$1"
        ACTION="$2"
        if [ "$ACTION" = "up" ] && [ -d "/sys/class/net/$IFACE/wireless" ]; then
          # Get the wpa_supplicant D-Bus interface path for this ifname
          IFPATH=$(${pkgs.dbus}/bin/dbus-send --system --print-reply \
            --dest=fi.w1.wpa_supplicant1 \
            /fi/w1/wpa_supplicant1 \
            fi.w1.wpa_supplicant1.GetInterface \
            "string:$IFACE" 2>/dev/null \
            | ${pkgs.gnugrep}/bin/grep -oP 'object path "\K[^"]+')
          if [ -n "$IFPATH" ]; then
            ${pkgs.dbus}/bin/dbus-send --system --print-reply \
              --dest=fi.w1.wpa_supplicant1 \
              "$IFPATH" \
              org.freedesktop.DBus.Properties.Set \
              "string:fi.w1.wpa_supplicant1.Interface" \
              "string:TdlsExternalControl" \
              "variant:string:1" >/dev/null 2>&1 || true
          fi
        fi
      '';
    }
  ];
}
