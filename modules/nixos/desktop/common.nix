# desktop/common.nix — Wayland desktop layer, compositor-agnostic.
#
# Imported by desktop/default.nix whenever a host activates ANY desktop
# session. Owns everything that holds across compositors: portals,
# polkit, common Wayland tooling, system-wide proxy app. Does NOT set
# XDG_CURRENT_DESKTOP or compositor-specific portals — those live in
# sessions/<name>.nix so they only activate for the chosen session.
#
# Adding a new session must NOT require edits here. If a candidate
# package or option only makes sense for one compositor, it belongs
# in that compositor's session file, not here.
{pkgs, ...}: {
  # Polkit — required by polkit-gnome-authentication-agent regardless
  # of compositor. The agent itself is launched per-session.
  security.polkit.enable = true;

  # UPower — power/battery D-Bus service. Required by Caelestia shell
  # for IdleMonitors (inhibitWhenCharging) and BatteryMonitor.
  services.upower.enable = true;

  # XDG portals. The gtk portal (universal fallback for GTK and Electron
  # apps) is NOT listed here on purpose: nixpkgs already contributes it
  # via programs/wayland/wayland-session.nix (enableGtkPortal defaults to
  # true, and hyprland.nix imports that module), so listing it again
  # produced a duplicate in xdg.portal.extraPortals — which then landed
  # twice in services.dbus.packages and emitted
  # "Ignoring duplicate name 'org.freedesktop.impl.portal.desktop.gtk'"
  # at every login.
  #
  # Compositor-specific portals still belong in sessions/<name>.nix
  # (hyprland.nix sets programs.hyprland.portalPackage, which the NixOS
  # module turns into an extraPortals entry).
  #
  # Safety for a future compositor that imports none of the above:
  # nixpkgs asserts extraPortals != [], so evaluation fails loudly with a
  # message naming the option rather than silently booting without any
  # portal implementation. No edit here is needed to get that guarantee.
  xdg.portal.enable = true;

  # Portal user-services log to stdout/stderr by default; on session
  # bootstrap (between greeter exit and compositor screen-take-over)
  # those streams briefly inherit the VT and dump verbose interface-
  # registration chatter on screen. Routing them to the journal keeps
  # the handoff visually clean and the diagnostics still grep'able via
  # `journalctl --user -u xdg-desktop-portal*`.
  systemd.user.services.xdg-desktop-portal.serviceConfig = {
    StandardOutput = "journal";
    StandardError = "journal";
  };
  systemd.user.services.xdg-desktop-portal-gtk.serviceConfig = {
    StandardOutput = "journal";
    StandardError = "journal";
  };

  # System-wide Wayland tooling. None of these are compositor-specific;
  # they are used identically by Hyprland, niri, GNOME, Sway, etc.
  # User-level desktop apps (Caelestia shell, rofi, etc.) live
  # in HM because their configs are managed there. hyprlock/
  # hypridle/hyprpaper are also in HM but disabled — Caelestia owns
  # notifications, lock, idle, and wallpaper.
  environment.systemPackages = with pkgs; [
    wl-clipboard
    brightnessctl
    grim
    slurp
    swappy
    polkit_gnome
    papirus-icon-theme
    adwaita-icon-theme
    # nftables CLI — mihomo creates native nftables rules for TUN
    # transparent proxy. Without the nft binary in PATH, these rules
    # are invisible to diagnostics, leading to false conclusions
    # about TUN state.
    nftables
  ];

  # Proxy stack — Clash Verge Rev (mihomo) is the only proxy on
  # lecoo (enabled host-scoped in hosts/lecoo/default.nix via
  # modules/nixos/clash-verge.nix).
  #
  # Clash Verge Rev: service mode supervises the IPC layer; the GUI
  # starts `verge-mihomo` (the core). Restarting the service requires
  # the GUI to re-activate the core — an accepted trade-off for better
  # GUI UX. The TUN stack must be `system` for CloakBrowser transparent
  # routing to work. See modules/nixos/clash-verge.nix for details.
}
