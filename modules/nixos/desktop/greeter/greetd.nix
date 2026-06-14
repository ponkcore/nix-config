# greeter/greetd.nix — greetd display manager + nwg-hello greeter on sway.
#
# The default greeter for hosts whose `desktops` list does NOT include
# "gnome". GNOME hosts use gdm instead (see ./gdm.nix when added).
# Selection happens in ../default.nix based on the active session set.
#
# ── Stack rationale ─────────────────────────────────────────────────
#
# greetd needs a Wayland compositor to host the GUI greeter. Three
# tried hosts on this machine:
#
#   cage 0.2.x — spans the bounding box of the output layout (no
#     letterbox, no per-output config, no mirror). Multi-monitor with
#     dissimilar resolutions = visible crop. Plus xdph SEGV at exit.
#
#   Hyprland kiosk — solves the mirror trivially via `monitor =
#     mirror,...`, but Hyprland's own .portal file claims xdph;
#     CPortalManager destructor SEGVs after wl_display_disconnect()
#     (hyprwm/xdg-desktop-portal-hyprland#400, closed not-planned
#     2026-05-21). Operator-visible: error window flashes at handoff.
#
#   sway 1.11 — per-output gtk-layer-shell surfaces, no portal claim
#     (XDG_CURRENT_DESKTOP=sway → portal looks for xdg-desktop-portal-
#     wlr, which does NOT autostart in a stripped greeter session).
#     Combined with nwg-hello (the only GTK greeter that natively
#     handles multi-monitor via monitor_nums + form_on_monitors), this
#     is the cleanest stack that actually solves all four constraints
#     at once: silent boot, multi-monitor, gruvbox theming, no xdph.
#
# Decision: 2026-05-30, option 2 from
# researches/2026-05-30-greeter-stack-for-hyprland-multi-monitor.result.md.
#
# Architecture notes:
#   - sway is invoked by absolute store path. `programs.sway.enable`
#     is intentionally left off so sway does NOT appear as a
#     selectable user-session in /run/current-system/sw/share/
#     wayland-sessions/. The greeter sway is a kiosk-only host.
#   - nwg-hello reads its config from /etc/nwg-hello/{json,css}. The
#     hyprland.conf shipped with the package is unused (we go via
#     sway). Wallpaper lives at /etc/greetd/wallpaper.jpg, served
#     both by sway's `output * bg` and by the nwg-hello CSS
#     `background-image` on the form layer.
#   - Greeter env: XDG_CURRENT_DESKTOP=sway, GTK_USE_PORTAL=0,
#     GDK_DEBUG=no-portals — belt-and-suspenders against any portal
#     autostart inside the greeter session.
#   - greeterManagesPlymouth = false. nwg-hello has no plymouth
#     integration; let greetd own the plymouth-quit transition. The
#     fbcon flash window is covered by silent-vt + silent-vt-keep
#     in modules/nixos/boot.nix.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Palette — shared via lib/palette.nix.
  p = import ../../../../lib/palette.nix;

  # Greeter wrapper — runs sway under dbus-run-session.
  #
  # Why dbus-run-session:
  #   - sway 1.11 uses libdbus internally (idle inhibitor, IPC).
  #   - GTK3 (nwg-hello) requires DBUS_SESSION_BUS_ADDRESS for
  #     gsettings / accessibility.
  #
  # All sway stderr is silenced. wlroots/Aquamarine init messages
  # otherwise reach controlling tty during the brief plymouth-quit
  # → sway-DRM-takeover window and flash on the panel before the
  # form appears (silent-vt-keep eventually rebinds, but only after
  # half a second of visible text). Greetd's StandardError=journal
  # still captures the wrapper's own diagnostics.
  greeterScript = pkgs.writeShellScript "sway-greeter-run" ''
    exec ${pkgs.dbus}/bin/dbus-run-session -- \
      ${pkgs.sway}/bin/sway --config ${swayGreeterConfig} 2>/dev/null
  '';

  # ── sway kiosk config ────────────────────────────────────────────
  # Minimal sway config: per-output background, US/RU keyboard,
  # nwg-hello as the only foreground app, exit when nwg-hello exits.
  #
  # Output strategy:
  #   - eDP-1 native 2880x1800; sway picks the panel's preferred mode.
  #   - HDMI-A-1 native 1920x1080; same.
  #   - Each output gets the wallpaper as solid background; nwg-hello
  #     overlays its own gtk-layer-shell surface per output, sized to
  #     that output's native mode. No spanning, no crop.
  #   - No `output * scale 1.5` — nwg-hello scales internally via GTK
  #     and the system's per-monitor xdg-output scale; trying to set
  #     a scale here doubles up with GTK's own and looks blurry.
  #
  # Input strategy:
  #   - xkb_layout us,ru with caps_toggle — matches user session.
  #   - repeat_rate / repeat_delay tuned to feel like Hyprland.
  #
  # No keybinds. The greeter has no use for sway-level binds; nwg-
  # hello handles its own keyboard input. Ctrl+Alt+F1..F6 stays
  # functional via kernel VT switching, independent of sway.
  # ── sway kiosk config ────────────────────────────────────────────
  # eDP-1 is forced as the only active output during the greeter.
  # `output * disable` first turns off EVERY output, then eDP-1 is
  # explicitly re-enabled — so the greeter is deterministically on the
  # internal panel regardless of what external monitor (HDMI / DP /
  # USB-C) happens to be plugged in or how sway enumerates outputs.
  # Rationale:
  #   - nwg-hello picks the form's monitor by wl_output index, which is
  #     not stable across boots; pinning to the single active output
  #     removes that nondeterminism entirely.
  #   - The greeter is a brief attention surface; running it on a
  #     second panel has no value, only failure modes.
  #   - The user-session Hyprland reconfigures all outputs from scratch
  #     post-login, so any external panel comes up there with zero
  #     carry-over from the greeter.
  # `output * bg` then paints the single active output (eDP-1).
  swayGreeterConfig = pkgs.writeText "sway-greeter-config" ''
    output * disable
    output eDP-1 enable
    output * bg /etc/greetd/wallpaper.jpg fill

    # Keyboard — match user session.
    input "type:keyboard" {
        xkb_layout us,ru
        xkb_options grp:caps_toggle
        repeat_rate 50
        repeat_delay 300
    }

    # Cursor — Capitaine Gruvbox, same as user session.
    seat seat0 xcursor_theme "Capitaine Cursors (Gruvbox)" 24

    # No window decorations / gaps / animations. nwg-hello uses
    # gtk-layer-shell so it floats outside sway's tiling tree
    # anyway; these are belt-and-suspenders.
    default_border none
    default_floating_border none
    gaps inner 0
    gaps outer 0

    # Launch sequence: nwg-hello runs in foreground; on exit, sway
    # shuts itself down → greetd starts the user session.
    #
    # nwg-hello in nixpkgs hardcodes its config-search path to its
    # own /nix/store/.../etc/nwg-hello/nwg-hello.{json,css} and does
    # NOT fall through to /etc/nwg-hello/ — see main.py lines 55-66
    # in nwg-hello 0.4.1. The if-elif picks the store-path first
    # and never re-reads from /etc. We therefore pass our config
    # files explicitly via --config / --stylesheet so the operator
    # JSON+CSS in /etc are actually used.
    exec "${pkgs.nwg-hello}/bin/nwg-hello --config /etc/nwg-hello/nwg-hello.json --stylesheet /etc/nwg-hello/nwg-hello.css; swaymsg exit"
  '';

  # ── nwg-hello config (JSON) ──────────────────────────────────────
  # monitor_nums = [] → surface on every active output.
  # form_on_monitors = [0] → form on the first (and, with the sway
  # `output * disable` + `output eDP-1 enable` policy above, only)
  # enumerated output, i.e. the internal eDP-1 panel.
  #
  # session_dirs uses /run/current-system/sw/share for nixos-style
  # path layout. The greetd systemd unit re-asserts XDG_DATA_DIRS
  # below for safety.
  #
  # GTK theme = Adwaita + prefer-dark-theme. Gruvbox is delivered
  # via the CSS file below — keeps the GTK theme dependency surface
  # narrow (no need to pull gruvbox-gtk-theme into the greeter).
  nwgHelloConfig = pkgs.writeText "nwg-hello.json" (
    builtins.toJSON {
      # nwg-hello does NOT honour XDG_DATA_DIRS — it reads session
      # .desktop files from these paths only. NixOS exposes the
      # session set as `services.displayManager.sessionData.desktops`,
      # a derivation containing share/wayland-sessions/. Point at
      # that store path directly. The /run/current-system/sw/share
      # tree contains the user's PATH packages, NOT session
      # definitions — pointing nwg-hello there gave it an empty
      # list and crashed on `sessions[0]` with IndexError.
      session_dirs = [
        "${config.services.displayManager.sessionData.desktops}/share/wayland-sessions"
        "${config.services.displayManager.sessionData.desktops}/share/xsessions"
      ];
      custom_sessions = [];
      monitor_nums = [];
      form_on_monitors = [0];
      delay_secs = 1;
      cmd-sleep = "systemctl suspend";
      cmd-reboot = "systemctl reboot";
      cmd-poweroff = "systemctl poweroff";
      gtk-theme = "Adwaita";
      gtk-icon-theme = "";
      gtk-cursor-theme = "Capitaine Cursors (Gruvbox)";
      prefer-dark-theme = true;
      template-name = "";
      time-format = "%H:%M";
      date-format = "%a, %d %b";
      layer = "overlay";
      keyboard-mode = "exclusive";
      lang = "";
      avatar-show = false;
      avatar-size = 100;
      avatar-border-width = 1;
      avatar-border-color = "#eee";
      avatar-corner-radius = 15;
      avatar-circle = false;
      env-vars = [];
    }
  );

  # ── nwg-hello CSS — gruvbox-warm theme ───────────────────────────
  # Selectors come from the nwg-hello default stylesheet:
  #   window, #form-wrapper, entry, button, #power-button,
  #   #welcome-label, #clock-label, #date-label,
  #   #form-label, #form-combo, #password-entry, #login-button.
  # Wallpaper is loaded via background-image on the window node.
  nwgHelloCss = pkgs.writeText "nwg-hello.css" ''
    /* ── Wallpaper ─────────────────────────────────────────────── */
    window {
        background-image: url("/etc/greetd/wallpaper.jpg");
        background-size: cover;
        background-position: center;
        color: ${p.fg};
    }

    /* ── Login form frame ──────────────────────────────────────── */
    #form-wrapper {
        background-color: alpha(${p.bg}, 0.92);
        border: 1px solid ${p.border};
        border-radius: 12px;
        padding: 24px 32px;
    }

    /* ── Welcome / clock / date ────────────────────────────────── */
    #welcome-label {
        color: ${p.fg_bright};
        font-size: 32px;
        font-weight: 600;
    }

    #clock-label {
        color: ${p.accent_warm};
        font-family: monospace;
        font-size: 64px;
        font-weight: 700;
    }

    #date-label {
        color: ${p.fg_dim};
        font-size: 18px;
    }

    /* ── Form labels ───────────────────────────────────────────── */
    #form-label,
    label {
        color: ${p.fg_dim};
        font-weight: 500;
    }

    /* ── Entry (password / username) ──────────────────────────── */
    entry,
    #password-entry {
        background-color: ${p.bg_mid};
        color: ${p.fg};
        border: 1px solid ${p.border_inact};
        border-radius: 6px;
        padding: 8px 12px;
        caret-color: ${p.accent_warm};
    }

    entry:focus,
    #password-entry:focus {
        border-color: ${p.accent_warm};
        box-shadow: 0 0 0 1px ${p.accent_warm};
    }

    /* ── Combobox (session selector) ───────────────────────────── */
    combobox,
    #form-combo {
        background-color: ${p.bg_mid};
        color: ${p.fg};
        border: 1px solid ${p.border_inact};
        border-radius: 6px;
        padding: 4px 8px;
    }

    combobox:hover,
    #form-combo:hover {
        border-color: ${p.accent_warm};
    }

    /* ── Buttons (generic) ─────────────────────────────────────── */
    button {
        background-color: ${p.bg_mid};
        color: ${p.fg};
        border: 1px solid ${p.border_inact};
        border-radius: 6px;
        padding: 8px 20px;
        font-weight: 500;
    }

    button:hover {
        background-color: ${p.hover_bg};
        color: ${p.hover_fg};
        border-color: ${p.accent_warm};
    }

    /* ── Login button — primary action ─────────────────────────── */
    #login-button {
        background-color: ${p.accent_warm};
        color: ${p.bg};
        border-color: ${p.accent_warm};
        font-weight: 600;
    }

    #login-button:hover {
        background-color: ${p.bright_yellow};
        color: ${p.bg};
    }

    /* ── Power buttons (sleep/reboot/poweroff) ─────────────────── */
    #power-button {
        background: none;
        border: none;
        border-radius: 18px;
        padding: 8px;
    }

    #power-button:hover {
        background-color: alpha(${p.fg_bright}, 0.1);
    }

    #power-button:active {
        background-color: alpha(${p.bright_yellow}, 0.2);
    }
  '';
in {
  # ── greetd ─────────────────────────────────────────────────────
  services.greetd = {
    enable = true;
    # nwg-hello has no plymouth integration → let greetd own the
    # plymouth-quit handoff. silent-vt+silent-vt-keep mute the
    # fbcon side-channel.
    greeterManagesPlymouth = false;
    restart = true;
  };

  services.greetd.settings.default_session.command = lib.mkForce "${greeterScript}";

  # ── greetd systemd service environment ─────────────────────────
  systemd.services.greetd = {
    environment = {
      # nwg-hello session enumeration
      XDG_DATA_DIRS = "${config.services.displayManager.sessionData.desktops}/share:/run/current-system/sw/share";
      # Mark this as a sway session so the system portal config
      # (if any portal is ever D-Bus-activated) looks for
      # xdg-desktop-portal-wlr, NOT xdg-desktop-portal-hyprland.
      XDG_CURRENT_DESKTOP = "sway";
      # Belt-and-suspenders: prevent GTK clients (nwg-hello) from
      # ever asking for a portal even if the bus has one available.
      GTK_USE_PORTAL = "0";
      GDK_DEBUG = "no-portals";
    };
    # Keep wlroots / sway init noise out of the controlling tty.
    serviceConfig.StandardError = "journal";
  };

  # ── nwg-hello config files ─────────────────────────────────────
  environment.etc."nwg-hello/nwg-hello.json".source = nwgHelloConfig;
  environment.etc."nwg-hello/nwg-hello.css".source = nwgHelloCss;

  # Wallpaper — readable by the unprivileged greeter user.
  environment.etc."greetd/wallpaper.jpg".source = ../../../../assets/wallpaper.jpg;

  # ── Packages required by the greeter session ───────────────────
  # Cursor theme path resolves via /run/current-system/sw/share/icons.
  environment.systemPackages = [
    pkgs.nwg-hello
    pkgs.sway
    pkgs.capitaine-cursors-themed
  ];

  # ── greeter user (required by greetd) ──────────────────────────
  users.users.greeter = {
    isSystemUser = true;
    group = "greeter";
    home = "/var/lib/greeter";
    createHome = true;
  };
  users.groups.greeter = {};

  # nwg-hello caches the last-used user/session at
  # /var/cache/nwg-hello/cache.json. The directory does not exist
  # on a fresh install — first launch logs a non-fatal "No such file
  # or directory" then proceeds. tmpfiles ensures the directory
  # exists with greeter ownership so the cache write later succeeds
  # silently.
  systemd.tmpfiles.rules = [
    "d /var/cache/nwg-hello 0755 greeter greeter -"
  ];
}
