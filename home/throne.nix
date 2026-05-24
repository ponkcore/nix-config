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
#    upstream `Throne` binary under native Wayland and with the
#    user's qt-6 profile prepended to QT_PLUGIN_PATH.
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
# 2. Overrides the .desktop entry to launch through this wrapper,
#    so Hyprland's app launcher picks up the themed version.
{
  pkgs,
  config,
  ...
}: let
  throne-launch = pkgs.writeShellScriptBin "throne-launch" ''
    export QT_QPA_PLATFORM="wayland;xcb"
    export QT_PLUGIN_PATH="${config.home.profileDirectory}/lib/qt-6/plugins''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
    exec Throne "$@"
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
