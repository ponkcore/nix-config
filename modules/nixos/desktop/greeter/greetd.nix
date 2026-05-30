# greeter/greetd.nix — greetd display manager + ReGreet greeter.
#
# The default greeter for hosts whose `desktops` list does NOT include
# "gnome". GNOME hosts use gdm instead (see ./gdm.nix when added).
# Selection happens in ../default.nix based on the active session set.
#
# ── On the choice of compositor for the greeter session ──────────────
#
# greetd needs a Wayland compositor to host ReGreet. Two viable hosts
# exist on a NixOS system that already runs Hyprland:
#
#   cage (kiosk compositor, 0.2.x)
#     - cannot mirror outputs
#     - cannot restrict to a named output without external wlr-randr
#     - cage's `-s` flag (VT switching) issues VT_ACTIVATE during
#       startup, which re-binds vtcon1 to fbcon and flashes any queued
#       kernel/systemd output onto the panel after silent-vt unbind
#     - atexit teardown triggers xdg-desktop-portal-hyprland SEGV
#       (CCWlOutput dtor after wl_display poison) — see #400 closed
#       "not planned"
#
#   Hyprland kiosk (already installed for the user session)
#     - native `mirror` directive: HDMI-A-1 displays a copy of eDP-1
#       at the HDMI's resolution (handles 2880x1800@2 → 1920x1080@1)
#     - clean exit via greetd → no portal autostart, no atexit dance
#     - libseat/logind session take-over does NOT issue VT_ACTIVATE
#       on its own; the VT remains under fbcon-detached state from
#       silent-vt + silent-vt-keep
#     - zero closure delta — Hyprland is already in the system
#
# Decision (2026-05-30): swap cage for Hyprland-as-greeter. Solves
# the multi-monitor "regreet appears only on eDP-1, drifts to HDMI-A-1
# after ~5 seconds" bug architecturally. Also closes the second
# log-flash window (cage's VT_ACTIVATE) at the source.
#
# Research backing: researches/2026-05-29-greetd-multi-monitor-mirror-
# alternatives.result.md — Hyprland + regreet rated #1 candidate.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Palette — shared via lib/palette.nix.
  p = import ../../../../lib/palette.nix;

  # ── Hyprland greeter kiosk config ────────────────────────────────
  # Minimal Hyprland configuration for the greeter session. Hosts
  # exactly one window (regreet) and exits when regreet exits.
  #
  # Monitor strategy:
  #   - eDP-1 is the source of truth. Native 2880x1800 at scale 2
  #     (logical 1440x900) — matches the user-session config so
  #     regreet renders identically.
  #   - HDMI-A-1 mirrors eDP-1 via Hyprland's native `mirror` arg.
  #     The mirrored output renders the source's framebuffer scaled
  #     to fit the HDMI's 1920x1080 — no separate workspace, no
  #     bounding-box drift, no wlr-randr race.
  #   - Catch-all line for any future external display: also mirror
  #     eDP-1 by default (safer than extending and getting a blank
  #     half-screen on an unexpected DP/USB-C dock).
  #
  # No keybinds (the greeter has no use for compositor-level binds —
  # ReGreet handles its own keyboard input). No animations, no
  # decoration, no wallpaper inside the compositor (regreet renders
  # its own background from /etc/greetd/wallpaper.jpg).
  greeterHyprlandConfig = pkgs.writeText "greeter-hyprland.conf" ''
    # Monitors — mirror every external output to the internal panel.
    #
    # scale 1.5 on eDP-1 (logical 1920x1200): a compromise between
    # readable HiDPI rendering on the laptop panel and reasonable
    # element sizing on the HDMI mirror. scale 2 (user-session
    # default) made the regreet form oversized; scale 1 made the
    # 2880x1800 panel render too small on a single login window.
    #
    # Aspect ratio caveat: eDP-1 is 16:10 (2880x1800), HDMI-A-1 is
    # typically 16:9. Hyprland's `mirror` blits the source
    # framebuffer to the target without letterbox, so ~10% of the
    # vertical content is cropped on a 16:9 mirror target. Acceptable
    # trade for "regreet visible on both panels"; the login form
    # itself is small enough to remain visible inside the cropped
    # region.
    monitor = eDP-1, 2880x1800@120, 0x0, 1.5
    monitor = HDMI-A-1, 1920x1080@60, auto, 1, mirror, eDP-1
    monitor = , preferred, auto, 1, mirror, eDP-1

    # Cursor — Hyprland renders the cursor itself outside any GTK
    # surface (e.g. when hovering bare compositor area). regreet's
    # cursorTheme only theming the GTK pointer; the compositor needs
    # XCURSOR_THEME / HYPRCURSOR_THEME exported via env. Without
    # these the greeter shows the default white wlroots arrow.
    env = XCURSOR_THEME, Capitaine Cursors (Gruvbox)
    env = XCURSOR_SIZE, 24
    env = HYPRCURSOR_THEME, Capitaine Cursors (Gruvbox)
    env = HYPRCURSOR_SIZE, 24

    # Input — match user session (US/RU with caps_toggle) so the
    # operator types into the password field with the same layout
    # they use in the desktop session.
    input {
      kb_layout = us,ru
      kb_options = grp:caps_toggle
      repeat_rate = 50
      repeat_delay = 300
    }

    # No window decoration / animation / gaps. The greeter is one
    # full-window GTK app — no compositor chrome around it.
    general {
      border_size = 0
      gaps_in = 0
      gaps_out = 0
      no_focus_fallback = true
    }

    decoration {
      rounding = 0
      shadow {
        enabled = false
      }
      blur {
        enabled = false
      }
    }

    animations {
      enabled = false
    }

    misc {
      disable_hyprland_logo = true
      disable_splash_rendering = true
      force_default_wallpaper = 0
      vfr = true
      # Disable Hyprland's own QoL warnings — the greeter session
      # is throwaway and does not need them.
      disable_autoreload = true
    }

    # No user keybinds. The greeter has none. Ctrl+Alt+F1..F6 still
    # works (kernel VT switching is independent of compositor binds).

    # Window rule — make the regreet window fullscreen and centered.
    # `regreet` advertises app_id = "regreet" via GTK4. Without this
    # rule Hyprland would tile it; the greeter expects a single
    # full-screen presentation.
    windowrulev2 = fullscreen, class:^(regreet)$
    windowrulev2 = noborder, class:^(regreet)$

    # Launch sequence:
    #   1. regreet runs synchronously (we do NOT exec-once because
    #      we want to know when it exits)
    #   2. when regreet exits, dispatch exit → Hyprland tears down →
    #      greetd starts the user session
    exec-once = ${lib.getExe config.programs.regreet.package} && hyprctl dispatch exit
  '';

  # Greeter wrapper script — runs Hyprland with the kiosk config and
  # silences stderr so wlroots/Aquamarine init noise (DRM, EGL, GLES2,
  # libseat) never reaches the controlling tty during the brief
  # window between the greetd service start and Hyprland's DRM
  # take-over.
  #
  # We bypass UWSM here on purpose. UWSM is a user-session lifecycle
  # manager; the greeter is a system-level throwaway compositor that
  # should not register with the user systemd instance. Calling
  # /run/current-system/sw/bin/Hyprland directly avoids the UWSM
  # service-template overhead and keeps the exit path simple.
  greeterScript = pkgs.writeShellScript "greeter-hyprland-kiosk" ''
    exec /run/current-system/sw/bin/Hyprland \
      --config ${greeterHyprlandConfig} \
      2>/dev/null
  '';
in {
  # greetd — minimal display manager backend
  services.greetd = {
    enable = true;
    # Smooth Plymouth → greeter handoff: ReGreet handles Plymouth
    # quit itself.
    greeterManagesPlymouth = true;
    # No autologin — user must enter password.
    restart = true;
  };

  # Hyprland kiosk as the greeter compositor. dbus-run-session is
  # required so regreet's GTK4 stack has a session bus to talk to
  # (gnome-keyring, accountsservice). bash -c keeps the redirect
  # syntax clean.
  services.greetd.settings.default_session.command = lib.mkForce (
    "${pkgs.bash}/bin/bash -c '"
    + "exec ${pkgs.dbus}/bin/dbus-run-session ${greeterScript}"
    + "'"
  );

  # ReGreet discovers sessions via XDG_DATA_DIRS.
  # The greetd systemd service does NOT source /etc/set-environment,
  # so we must inject XDG_DATA_DIRS explicitly.
  #
  # GTK_USE_PORTAL=0 + GDK_DEBUG=no-portals — suppress
  # xdg-desktop-portal autostart inside the greeter session.
  # xdg-desktop-portal-hyprland 1.3.11/1.3.12 SEGVs in
  # CCWlOutput::~CCWlOutput during atexit. With Hyprland-as-greeter
  # we do not exhibit cage's exit fragility, but xdph autostart on
  # GTK app boot would still spin up an unnecessary portal stack
  # for a 2-second login session. Researched 2026-05-29.
  systemd.services.greetd = {
    environment = {
      XDG_DATA_DIRS = "${config.services.displayManager.sessionData.desktops}/share:/run/current-system/sw/share";
      GTK_USE_PORTAL = "0";
      GDK_DEBUG = "no-portals";
    };
    # Redirect greetd's stderr to journal instead of VT.
    serviceConfig.StandardError = "journal";
  };

  # ReGreet — GTK4 greetd frontend (now hosted by Hyprland, not cage)
  programs.regreet = {
    enable = true;

    # Gruvbox-Dark GTK — consistent with HM gtk.theme.
    theme = {
      name = "Gruvbox-Dark";
      package = pkgs.gruvbox-gtk-theme;
    };
    iconTheme = {
      name = "oomox-gruvbox-dark";
      package = pkgs.gruvbox-dark-icons-gtk;
    };
    cursorTheme = {
      name = "Capitaine Cursors (Gruvbox)";
      package = pkgs.capitaine-cursors-themed;
    };
    # UI font — match the rest of the system.
    font = {
      name = "Noto Sans";
      size = 14;
      package = pkgs.noto-fonts-lgc-plus;
    };

    # regreet.toml — background + GTK settings
    settings = {
      background = {
        path = "/etc/greetd/wallpaper.jpg";
        fit = "Cover";
      };
      GTK = {
        application_prefer_dark_theme = true;
        cursor_blink = false;
      };
      appearance = {
        greeting_msg = "Welcome back!";
      };
      widget.clock = {
        format = "%a %H:%M";
        resolution = "500ms";
      };
    };

    # CSS — style the login box, clock, and buttons.
    extraCss =
      /*
      CSS
      */
      ''
        /* ── Login box frame ─────────────────────────────────────────── */
        .background {
          background-color: alpha(${p.bg}, 0.92);
          border: 1px solid ${p.border};
          border-radius: 12px;
          box-shadow: 0 4px 24px alpha(#000000, 0.5);
        }

        /* ── Labels (User:, Session:) ─────────────────────────────────── */
        label {
          color: ${p.fg_dim};
          font-weight: 500;
        }

        /* ── Message label (greeting, errors) ─────────────────────────── */
        #message_label {
          color: ${p.fg_bright};
          font-size: 1.1em;
        }

        /* ── Clock frame ──────────────────────────────────────────────── */
        #clock_frame {
          background-color: alpha(${p.bg}, 0.85);
          border: 1px solid ${p.border};
          border-radius: 0 0 12px 12px;
          border-top-width: 0px;
          padding: 8px 24px;
        }

        #clock_frame label {
          color: ${p.accent_warm};
          font-size: 1.4em;
          font-weight: 600;
        }

        /* ── Combo box / entry ─────────────────────────────────────────── */
        combobox, entry {
          color: ${p.fg};
          background-color: ${p.bg_mid};
          border: 1px solid ${p.border_inact};
          border-radius: 6px;
          padding: 6px 10px;
        }

        combobox:hover, entry:hover {
          border-color: ${p.accent_warm};
        }

        combobox:focus, entry:focus {
          border-color: ${p.accent_warm};
          box-shadow: 0 0 0 1px ${p.accent_warm};
        }

        /* ── Buttons ──────────────────────────────────────────────────── */
        button {
          color: ${p.fg};
          background-color: ${p.bg_mid};
          border: 1px solid ${p.border_inact};
          border-radius: 6px;
          padding: 6px 20px;
          font-weight: 500;
        }

        button:hover {
          background-color: ${p.hover_bg};
          color: ${p.hover_fg};
          border-color: ${p.accent_warm};
        }

        button:focus {
          border-color: ${p.accent_warm};
          box-shadow: 0 0 0 1px ${p.accent_warm};
        }

        /* Login button — primary action */
        button.suggested-action {
          background-color: ${p.accent_warm};
          color: ${p.bg};
          border-color: ${p.accent_warm};
          font-weight: 600;
        }

        button.suggested-action:hover {
          background-color: ${p.bright_yellow};
          color: ${p.bg};
        }

        /* Reboot/poweroff — destructive */
        button.destructive-action {
          color: ${p.bright_red};
          border-color: alpha(${p.red}, 0.4);
        }

        button.destructive-action:hover {
          background-color: alpha(${p.red}, 0.2);
          color: ${p.bright_red};
        }

        /* Toggle button (manual session entry) */
        togglebutton {
          color: ${p.fg_dim};
          background-color: ${p.bg_mid};
          border: 1px solid ${p.border_inact};
          border-radius: 6px;
        }

        togglebutton:checked {
          background-color: ${p.hover_bg};
          color: ${p.hover_fg};
          border-color: ${p.accent_warm};
        }

        /* ── Info bar (notifications) ──────────────────────────────────── */
        infobar {
          background-color: alpha(${p.bg_mid}, 0.9);
          border-radius: 6px;
        }

        infobar label {
          color: ${p.fg_dim};
        }
      '';
  };

  # Wallpaper accessible to the greeter user.
  # Home dir is mode 700 — greeter cannot read /home/oonishi/.local/share/...
  # so we install a system-level copy at /etc/greetd/wallpaper.jpg.
  environment.etc."greetd/wallpaper.jpg".source = ../../../../assets/wallpaper.jpg;

  # greeter user — required by regreet module assertion.
  # greetd runs the greeter session under this system user.
  users.users.greeter = {
    isSystemUser = true;
    group = "greeter";
    home = "/var/lib/greeter";
    createHome = true;
  };
  users.groups.greeter = {};
}
