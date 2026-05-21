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
    # NetworkManager-level powersave: enables 802.11 PSM negotiation with the
    # AP. Safe to enable globally because per-driver workarounds for chipsets
    # that misbehave under PSM (e.g. RTL8852BE → disable_ps_mode=Y in
    # hosts/lecoo/hardware.nix) take precedence at the module-options layer.
    # Saves ~0.4-0.8 W on idle wifi when AP supports DTIM properly.
    wifi.powersave = true;
  };

  # NetworkManager does NOT bundle its own WPA implementation — it always
  # talks to a system-wide wpa_supplicant via D-Bus (fi.w1.wpa_supplicant1).
  # That unit ships inside the wpa_supplicant package and is auto-activated
  # by NM the moment it connects to a WPA network.
  #
  # `networking.wireless.enable = true` is the legacy "use wpa_supplicant
  # as the primary network manager" mode and conflicts with NM. Keep false.
  networking.wireless.enable = false;

  # ModemManager — nothing on these hosts uses cellular modems.
  networking.modemmanager.enable = false;
}
