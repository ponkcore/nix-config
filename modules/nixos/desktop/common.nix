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
{
  lib,
  pkgs,
  inputs,
  ...
}: {
  # TEMPORARY WORKAROUND — Throne binary rename + wrapper key.
  # 26.05 migration: Throne wrapper workarounds removed. The 26.05
  # throne module creates security.wrappers."ThroneCore" (CamelCase)
  # pointing at share/throne/ThroneCore — correct key, correct binary.
  # Throne 1.0.13 ships with the ThroneCore binary, so the wrapper
  # source exists and TUN mode works out of the box.

  # Polkit — required by polkit-gnome-authentication-agent regardless
  # of compositor. The agent itself is launched per-session.
  security.polkit.enable = true;

  # UPower — power/battery D-Bus service. Required by Caelestia shell
  # for IdleMonitors (inhibitWhenCharging) and BatteryMonitor.
  services.upower.enable = true;

  # XDG portals — gtk portal is the universal fallback used by GTK and
  # Electron apps. Compositor-specific portals (xdg-desktop-portal-hyprland,
  # xdg-desktop-portal-gnome) extend this list from sessions/<name>.nix.
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
    ];
  };

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
  # User-level desktop apps (mako, rofi, wlogout, Caelestia shell, etc.) live in HM
  # because their configs are managed there.
  environment.systemPackages = with pkgs; [
    wl-clipboard
    brightnessctl
    grim
    slurp
    swappy
    polkit_gnome
    papirus-icon-theme
    adwaita-icon-theme
    # nftables CLI — sing-box creates native nftables rules (table inet
    # sing-box) for TUN transparent proxy. Without the nft binary in
    # PATH, these rules are invisible to diagnostics, leading to false
    # conclusions about TUN state.
    nftables
  ];

  # Throne (ex-Nekoray) — Qt6 sing-box GUI for the Xray protocol
  # matrix (VLESS/Reality/VMess/Trojan/Hysteria/AnyTLS). Replaced
  # clash-verge as the system proxy manager — Throne speaks more
  # protocols out of the box and does not need a separate hardened
  # systemd helper (its sing-box core runs as a child of the GUI
  # under a security.wrappers binary).
  #
  # The TUN mode of Throne shells out to a `Core` binary that needs
  # CAP_NET_ADMIN and CAP_NET_RAW; the setcap branch of
  # `programs.throne` wraps it via security.wrappers (no SUID),
  # matching the safer default. The polkit rule shipped by the
  # NixOS module also auto-allows resolved DNS overrides for child
  # processes carrying those caps, so DNS works without prompting.
  #
  # Throne 1.0.13 + matching qt6 plugins are pulled from
  # nixos-unstable (see pkgs/default.nix) — the 25.11 channel
  # ships 1.0.8 with a regressed v1 NixOS patch that breaks TUN.
  programs.throne = {
    enable = true;
    tunMode.enable = true; # setcap-based TUN; no sudo required at runtime
  };
}
