# quickshell.nix — Quickshell shell (bar + control center + popups).
#
# Replaces waybar with a QtQuick-based shell adapted from
# matteogini/dotfiles. Provides:
#   - Notch-style top bar (transparent, content-driven width)
#   - Control center (sliders: volume, brightness, battery limit)
#   - App launcher, clipboard manager, theme switcher
#   - WiFi/Bluetooth menus
#   - Power menu (lock/logout/suspend/reboot/shutdown)
#   - OSD overlays (volume/brightness)
#   - Timer/Pomodoro
#
# IPC: qsIpc.* functions callable via hyprctl dispatch exec.
#
# Quickshell 0.3.0 from nixpkgs 26.05.
{
  pkgs,
  config,
  lib,
  theme,
  ...
}: let
  quickshellConfig = pkgs.callPackage ../../../../pkgs/quickshell-config {};

  # Quickshell wrapper: ensures Hyprland env is available before
  # starting, same pattern as waybar-with-hyprland-env.
  quickshell-launcher = pkgs.writeShellScript "quickshell-launcher" ''
    set -u

    HYPRCTL="${pkgs.hyprland}/bin/hyprctl"
    JQ="${pkgs.jq}/bin/jq"

    # Wait for Hyprland instance to be ready (same logic as waybar).
    for _ in $(${pkgs.coreutils}/bin/seq 1 150); do
      instance_json="$($HYPRCTL instances -j 2>/dev/null || printf '[]')"
      HYPRLAND_INSTANCE_SIGNATURE="$(printf '%s' "$instance_json" | $JQ -r '.[0].instance // empty')"
      WAYLAND_DISPLAY="$(printf '%s' "$instance_json" | $JQ -r '.[0].wl_socket // empty')"

      if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && [ -n "$WAYLAND_DISPLAY" ]; then
        export HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
        ${pkgs.coreutils}/bin/sleep 1
        break
      fi

      ${pkgs.coreutils}/bin/sleep 0.2
    done

    exec ${pkgs.quickshell}/bin/qs -c ${quickshellConfig}
  '';
in {
  # Quickshell package
  home.packages = [pkgs.quickshell quickshellConfig];

  # Systemd user service — replaces waybar when active.
  # Conflicts with waybar.service so only one bar runs at a time.
  systemd.user.services.quickshell = {
    Unit = {
      Description = "Quickshell desktop shell";
      After = ["graphical-session.target" "wayland-wm@Hyprland.service"];
      PartOf = ["graphical-session.target"];
      Conflicts = ["waybar.service"];
    };
    Service = {
      ExecStart = "${quickshell-launcher}";
      Restart = "on-failure";
      RestartSec = 3;
    };
    # Auto-start only when the active theme uses quickshell as its bar.
    Install = lib.optionalAttrs ((theme.bar or "waybar") == "quickshell") {
      WantedBy = ["graphical-session.target"];
    };
  };

  # Restart quickshell after HM activation so it picks up new QML
  # config from the Nix store. Without this, quickshell keeps running
  # the old config until manually restarted — the user sees a flash
  # of waybar (which auto-starts via its own WantedBy from the
  # previous generation) before quickshell catches up.
  # Same pattern as the waybar activation hook in waybar.nix.
  home.activation.restart-quickshell-on-config-change = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if ${pkgs.systemd}/bin/systemctl --user is-active --quiet quickshell.service 2>/dev/null; then
      ${pkgs.systemd}/bin/systemctl --user restart quickshell.service 2>/dev/null || true
    fi
  '';

  # Hyprland keybinds for quickshell IPC
  # These call qsIpc.* functions via hyprctl dispatch exec.
  # Note: quickshell IPC uses DBus, not hyprctl. The keybinds should
  # use `qs -c <config> ipc <target> <function> <args>`.
  # For now, we use hyprctl dispatch exec as a proxy.
}
