# greeter/greetd.nix — greetd display manager + ReGreet greeter.
#
# The default greeter for hosts whose `desktops` list does NOT include
# "gnome". GNOME hosts use gdm instead (see ./gdm.nix when added).
# Selection happens in ../default.nix based on the active session set.
#
# greetd runs cage as a Wayland kiosk; cage in turn runs ReGreet (GTK4)
# which presents the login form. Custom CSS in extraCss themes the
# greeter using the gruvbox palette directly imported from lib/.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Palette — shared via lib/palette.nix. Path is one level deeper now
  # that this file lives under modules/nixos/desktop/greeter/.
  p = import ../../../../lib/palette.nix;
in {
  # greetd — minimal display manager backend
  services.greetd = {
    enable = true;
    # Smooth Plymouth→greeter handoff: ReGreet handles Plymouth quit itself
    greeterManagesPlymouth = true;
    # No autologin — user must enter password
    restart = true;
  };

  # Silent greeter: redirect cage/wlroots stderr to /dev/null.
  # cage's wlr_log_init() messages (libseat, DRM, EGL, GLES2) go to stderr
  # via greetd's terminal setup (NOT through systemd's StandardError).
  # This suppresses the ~0.5s VT flash between Plymouth quit and ReGreet render.
  #
  # Multi-monitor handling: cage cannot mirror outputs nor restrict to a
  # named output (cage 0.2.1 — see researches/2026-05-29-greetd-cage-
  # multi-monitor-mirror.result.md). When a second display is attached at
  # boot, cage spans the regreet window across the bounding box of every
  # output, splitting the form. Workaround: a wrapper child of cage uses
  # wlr-randr against the cage Wayland socket (cage advertises
  # zwlr_output_manager_v1) to disable every output except eDP-1, then
  # exec's regreet. Idempotent — non-existent outputs are no-ops with
  # `|| true`. The brief (~100 ms) two-output flash before wlr-randr
  # completes is acceptable; an architectural fix would be to swap cage
  # for Hyprland-as-greeter (deferred — see decisions/ when filed).
  services.greetd.settings.default_session.command = let
    greeterWrapper = pkgs.writeShellScript "greeter-wrapper" ''
      # Disable every connected output except the internal panel.
      # Output names that do not exist on the current hardware are
      # silently ignored — wlr-randr returns non-zero, suppressed by
      # `|| true`. eDP-1 is the canonical internal panel name on
      # AMD/Intel laptops; adjust if the host uses a different one.
      for out in HDMI-A-1 HDMI-A-2 DP-1 DP-2 DP-3; do
        ${lib.getExe pkgs.wlr-randr} --output "$out" --off 2>/dev/null || true
      done
      exec ${lib.getExe config.programs.regreet.package}
    '';
  in
    lib.mkForce (
      "${pkgs.bash}/bin/bash -c 'exec ${pkgs.dbus}/bin/dbus-run-session "
      + "${lib.getExe pkgs.cage} ${lib.escapeShellArgs config.programs.regreet.cageArgs} "
      + "-- ${greeterWrapper} 2>/dev/null'"
    );

  # ReGreet discovers sessions via XDG_DATA_DIRS.
  # The greetd systemd service does NOT source /etc/set-environment,
  # so we must inject XDG_DATA_DIRS explicitly.
  #
  # GTK_USE_PORTAL=0 + GDK_DEBUG=no-portals — suppress xdg-desktop-portal
  # autostart inside the greeter session. xdg-desktop-portal-hyprland
  # 1.3.11/1.3.12 reliably SEGVs in CCWlOutput::~CCWlOutput during atexit
  # when cage exits: its global CPortalManager destructor sends Wayland
  # destructor requests after wl_display_disconnect() has already poisoned
  # the display object map (use-after-free hitting WL_ARRAY_POISON_PTR
  # at 0x44). Upstream issue hyprwm/xdg-desktop-portal-hyprland#400 closed
  # "not planned"; partial fix in v1.3.7 (commit fb9c8d6) covers only the
  # toplevel proxy, not the broader teardown path. Regreet uses no portal
  # services, so disabling GTK→portal IPC has no functional cost. Belt
  # and braces: the two vars block GTK4's modern path (GTK_USE_PORTAL)
  # and GDK's debug-controlled fallback (GDK_DEBUG=no-portals).
  # Researched 2026-05-29 — see
  # ~/Documents/talos-brain/researches/2026-05-29-xdg-desktop-portal-hyprland-segv-greeter-exit.result.md
  systemd.services.greetd = {
    environment = {
      XDG_DATA_DIRS = "${config.services.displayManager.sessionData.desktops}/share:/run/current-system/sw/share";
      GTK_USE_PORTAL = "0";
      GDK_DEBUG = "no-portals";
    };
    # Redirect greetd's stderr to journal instead of VT.
    # Prevents "waitpid: Holding login session N open" and similar
    # diagnostic messages from leaking onto the console.
    serviceConfig.StandardError = "journal";
  };

  # ReGreet — GTK4 greetd frontend running inside cage (Wayland kiosk)
  programs.regreet = {
    enable = true;
    # cage -s: allow VT switching (needed for SysRq / TTY escape)
    cageArgs = ["-s"];

    # Gruvbox-Dark GTK — consistent with HM gtk.theme.
    # Use gruvbox-gtk-theme (has gtk-4.0 assets) over the older
    # gruvbox-dark-gtk (gtk-2.0/3.0 only) so ReGreet renders without
    # falling back to default Adwaita colours.
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
    # UI font — match the rest of the system (mako uses the same).
    # 11pt Cantarell rendered tiny on the laptop's HiDPI panel; Noto
    # Sans 14 is the canonical desktop UI font for this config.
    font = {
      name = "Noto Sans";
      size = 14;
      package = pkgs.noto-fonts-lgc-plus;
    };

    # regreet.toml — background + GTK settings
    settings = {
      background = {
        # Wallpaper accessible to greeter user (installed via environment.etc below)
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

    # CSS — style the login box, clock, and buttons
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

  # Wallpaper accessible to the greeter user
  # Home dir is mode 700 — greeter cannot read /home/oonishi/.local/share/...
  # so we install a system-level copy at /etc/greetd/wallpaper.png
  # Source: tracked in repo at assets/wallpaper.png (flake pure-eval compatible)
  environment.etc."greetd/wallpaper.jpg".source = ../../../../assets/wallpaper.jpg;

  # greeter user — required by regreet module assertion
  # greetd runs the greeter session under this system user
  users.users.greeter = {
    isSystemUser = true;
    group = "greeter";
    home = "/var/lib/greeter";
    createHome = true;
  };
  users.groups.greeter = {};
}
