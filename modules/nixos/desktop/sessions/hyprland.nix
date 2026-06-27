# sessions/hyprland.nix — Hyprland Wayland compositor at the system level.
#
# Activated when "hyprland" is in the host's `desktops` list (see
# lib/mkHost.nix). Per-user keybinds, animations, and window rules
# live in home/desktop/sessions/hyprland/. Compositor-agnostic
# concerns (polkit, gtk portal, tooling) are in ../common.nix.
#
# ── On the three silent-wrapper derivations ─────────────────────────
#
# UWSM-managed Hyprland leaks chatter onto the post-greeter VT via
# three independent channels. Each derivation below patches exactly
# one channel, and each is necessary on its own:
#
#   hyprland-quiet              — wraps Hyprland with `2>/dev/null` so
#                                 Aquamarine / wlroots backend init
#                                 messages (libseat, DRM, EGL, GLES2,
#                                 input device probing) never reach
#                                 the controlling tty when
#                                 wayland-wm@Hyprland.service inherits
#                                 stderr. Pinned via:
#                                   programs.uwsm.waylandCompositors
#                                       .hyprland.binPath
#                                 Updated for 0.53+: invokes
#                                 start-hyprland (crash recovery
#                                 watchdog) as the inner binary.
#                                 start-hyprland does NOT suppress
#                                 stderr — the 2>/dev/null remains.
#
#   hyprland-silent-wrapper     — wraps the UWSM launcher itself with
#                                 `>/dev/null 2>/dev/null`. UWSM emits
#                                 its own startup chatter before the
#                                 systemd-user-unit hand-off; that
#                                 stream is separate from the
#                                 compositor stderr and survives
#                                 hyprland-quiet alone.
#
#   hyprland-uwsm-silent        — replaces the .desktop entry that
#                                 nwg-hello reads from XDG_DATA_DIRS.
#                                 Without this, the greeter launches
#                                 the upstream verbose entry that
#                                 calls `uwsm start hyprland-uwsm`
#                                 directly, bypassing our wrapper
#                                 chain entirely. Same .desktop
#                                 filename → last package wins in the
#                                 XDG_DATA_DIRS merge.
#
# Collapsing two of them into one would silently re-introduce
# whichever channel was dropped. The cost is three derivations and
# one mkForce override, paid once for an exhibition-grade silent
# boot.
{
  lib,
  pkgs,
  ...
}: let
  # start-hyprland is the 0.53+ crash recovery watchdog. It forks
  # Hyprland, monitors the child, and restarts in safe mode on
  # unclean exit. It does NOT redirect stderr — the 2>/dev/null
  # in the wrapper remains necessary for silent boot.
  hyprland-quiet = pkgs.writeShellScriptBin "Hyprland" ''
    exec ${pkgs.hyprland}/bin/start-hyprland "$@" 2>/dev/null
  '';

  hyprland-silent-wrapper = pkgs.writeShellScriptBin "hyprland-silent-wrapper" ''
    exec ${pkgs.uwsm}/bin/uwsm start -F -- ${hyprland-quiet}/bin/Hyprland \
      >>/dev/null 2>>/dev/null
  '';

  hyprland-uwsm-silent =
    pkgs.runCommand "hyprland-uwsm-silent" {
      passthru.providedSessions = ["hyprland-uwsm"];
    } ''
          mkdir -p "$out/share/wayland-sessions"
          cat > "$out/share/wayland-sessions/hyprland-uwsm.desktop" <<DESKTOP
      [Desktop Entry]
      Name=Hyprland (UWSM)
      Comment=Hyprland compositor managed by UWSM
      Exec=${hyprland-silent-wrapper}/bin/hyprland-silent-wrapper
      Type=Application
      DESKTOP
    '';
in {
  # Hyprland — package and portal from overlay (0.55.x).
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    package = pkgs.hyprland;
    portalPackage = pkgs.xdg-desktop-portal-hyprland;
  };

  # Workaround for XDG_CURRENT_DESKTOP when using start-hyprland with
  # UWSM: without this, UWSM sets XDG_CURRENT_DESKTOP to
  # start-hyprland instead of Hyprland. nixpkgs issue #476375.
  services.displayManager.defaultSession = "hyprland-uwsm";

  # Channel 1 (Aquamarine stderr): point UWSM's compositor binPath at
  # our quiet wrapper. mkForce because programs.hyprland.withUWSM
  # already sets this option upstream.
  programs.uwsm.waylandCompositors.hyprland.binPath = lib.mkForce "${hyprland-quiet}/bin/Hyprland";

  # Channel 3 (greeter .desktop entry): replace the upstream verbose
  # entry. Listed AFTER programs.hyprland so this package wins the
  # XDG_DATA_DIRS merge for the same filename.
  services.displayManager.sessionPackages = [hyprland-uwsm-silent];

  # Wayland environment variables — Hyprland-flavoured.
  # NIXOS_OZONE_WL / MOZ_ENABLE_WAYLAND / GDK_BACKEND etc. are also set by
  # niri.nix and gnome.nix; setting them per-session keeps each compositor
  # in charge of its own environment without leaking into common.nix.
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    QT_QPA_PLATFORM = "wayland;xcb";
    GDK_BACKEND = "wayland";
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_TYPE = "wayland";
    # Use logind backend directly — prevents libseat from trying seatd socket
    # (seatd is not enabled on this system, so the fallback error messages are noise)
    LIBSEAT_BACKEND = "logind";
  };

  # Hyprland-specific XDG portal — extends the gtk portal from common.nix.
  xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-hyprland];

  # xdph is the loudest portal in the family — it logs every Wayland
  # interface it discovers at session bootstrap. The default systemd
  # user-unit inherits stdout/stderr to the controlling tty, which on
  # the post-greeter handoff is briefly the VT (before compositor
  # take-over). Pin both streams to the journal so the handoff is
  # silent; `journalctl --user -u xdg-desktop-portal-hyprland` still
  # has the full diagnostic stream when needed.
  systemd.user.services.xdg-desktop-portal-hyprland.serviceConfig = {
    StandardOutput = "journal";
    StandardError = "journal";
  };
}
