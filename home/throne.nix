# throne.nix — Xray/sing-box GUI proxy manager.
#
# Throne is provided system-wide via `programs.throne.enable` in
# modules/nixos/desktop/common.nix; that's the only correct way to
# enable it on NixOS because TUN-mode capabilities require
# security.wrappers (system-only).
#
# What this module does:
#
# 1. Ships a small wrapper script `throne-launch` that launches the
#    upstream `Throne` binary under native Wayland and with both the
#    user's qt-6 profile and the unstable qtwayland-6.11.0 plugin
#    tree prepended to QT_PLUGIN_PATH.
#
#    Why the QT_PLUGIN_PATH dance:
#    The Throne binary in nixpkgs is wrapped with `makeCWrapper` to
#    point QT_PLUGIN_PATH at qtbase/qtsvg/qtdeclarative/qttools
#    store-paths only — so `libkvantum.so` and `libqt6ct.so` from
#    `/etc/profiles/per-user/<u>/lib/qt-6/plugins` are invisible to
#    Throne, and the in-app Theme picker silently no-ops on the
#    "Kvantum" choice. Pre-pending the user's plugin path via
#    env-var lets Qt's plugin loader discover both, so the picker
#    actually applies Kvantum (which then routes through
#    ~/.config/Kvantum/kvantum.kvconfig to the Gruvbox-Dark-Brown
#    theme).
#
#    Why also prepend qtwayland's plugin tree:
#    Throne is built against qtbase (from 26.05, same version as
#    system Qt). The upstream wrapper does not include qtwayland in
#    its plugin path. Without an ABI-matched qtwayland's auxiliary
#    plugins (decoration client, graphics-integration-server) Qt
#    cannot stand up a full Wayland session reliably under Hyprland.
#    So we prepend qtwayland explicitly via pkgs.qt6Packages.qtwayland
#    (standard 26.05 qtwayland, same ABI as Throne).
#
#    Why `-platform wayland` argv instead of QT_QPA_PLATFORM env:
#    Setting `QT_QPA_PLATFORM=wayland;xcb` does not stick on Throne
#    even when both plugins are visible — `QT_DEBUG_PLUGINS=1` shows
#    Qt scanning libqxcb.so and libqwayland.so, then loading xcb
#    without trying wayland at all. Other Qt6 apps in this profile
#    (AyuGram, KeePassXC, Spotify) honour the env-var fallback chain
#    fine; Throne 1.1.2 specifically does not. Passing the platform
#    via the standard `-platform` Qt argument is parsed by the
#    QGuiApplication constructor before app code can interfere, and
#    works reliably. There is no xcb fallback, but on this box every
#    session is Wayland anyway. On the mixed-DPI setup (eDP-1 scale
#    2, HDMI-A-1 scale 1), getting Throne onto native Wayland was
#    necessary to fix XWayland's "right-click menu rendered at the
#    global X scale (=2) regardless of monitor" bug — context menus
#    on HDMI-A-1 came out larger than the Throne window itself.
#
# 2. Overrides the .desktop entry to launch through this wrapper,
#    so Hyprland's app launcher picks up the themed version.
{
  pkgs,
  config,
  ...
}: let
  throne-launch = pkgs.writeShellScriptBin "throne-launch" ''
    export QT_PLUGIN_PATH="${config.home.profileDirectory}/lib/qt-6/plugins:${pkgs.qt6Packages.qtwayland}/lib/qt-6/plugins''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
    exec Throne -platform wayland "$@"
  '';
in {
  home.packages = [throne-launch];

  xdg.desktopEntries.throne = {
    name = "Throne";
    genericName = "Proxy Configuration Manager";
    comment = "Qt-based Xray/sing-box proxy GUI";
    icon = "Throne";
    exec = "throne-launch";
    terminal = false;
    categories = ["Network"];
    startupNotify = true;
  };
}
