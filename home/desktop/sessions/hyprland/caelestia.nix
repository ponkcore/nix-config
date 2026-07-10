# caelestia.nix — Caelestia shell + CLI via forked HM module.
#
# The Caelestia HM module (from ponkcore/shell) provides the systemd
# user service, config file generation, and package wiring. The CLI
# is enabled for full shell functionality (wallpaper, scheme, IPC).
#
# Ownership:
#   wallpaper  — Caelestia (Phase 3A, hyprpaper disabled)
#   launcher   — Caelestia (Phase 3B, rofi -show drun replaced)
#   notifs     — Caelestia (Phase 3D, mako disabled)
#   lock/idle  — Caelestia (Phase 3E, hyprlock + hypridle disabled).
#                Validated stable 2026-07-09: 15 min observation,
#                4 lock/unlock cycles (IPC + loginctl), 0 crashes,
#                0 wl_display errors. Prior crashes were caused by
#                Phase 3F (power bridge), not Phase 3E.
{
  config,
  inputs,
  pkgs,
  lib,
  ...
}: {
  # Import the Caelestia HM module from our shell fork.
  imports = [
    inputs.caelestia-shell.homeManagerModules.default
  ];

  programs.caelestia = {
    enable = true;
    # with-cli package bundles the CLI into the shell binary,
    # enabling full functionality (wallpaper, scheme, IPC).
    package = inputs.caelestia-shell.packages.${pkgs.system}.with-cli;
    systemd = {
      enable = true;
      # Start after the UWSM Hyprland session target is ready.
      # UWSM uses the compositor prettyName here, so the target is
      # wayland-session@Hyprland.target (capital H), not @hyprland.
      target = "wayland-session@Hyprland.target";
    };
    cli = {
      enable = true;
      package = inputs.caelestia-cli.packages.${pkgs.system}.default;
    };
    # Shell runtime config — DO NOT use HM `settings` attrset here.
    # HM `settings` writes shell.json as a read-only Nix store symlink
    # via xdg.configFile, which prevents the shell from writing runtime
    # state (wallpaper changes, bar toggles, etc.). Instead, the config
    # is written as a writable file by the activation script below.
    settings = {};
  };

  # Write shell.json as a plain writable file (not a Nix store symlink).
  # This allows Caelestia to read AND write its config at runtime.
  # The file is only created if it doesn't exist — existing user
  # customizations are preserved across rebuilds.
  home.activation.writeCaelestiaConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        if [ ! -f "$HOME/.config/caelestia/shell.json" ]; then
          $DRY_RUN_CMD mkdir -p "$HOME/.config/caelestia"
          $DRY_RUN_CMD cat > "$HOME/.config/caelestia/shell.json" <<'CAELESTIA_CONFIG'
    {
      "appearance": {
        "transparency": {
          "enabled": false
        }
      },
      "bar": {
        "status": {
          "showAudio": false,
          "showLockStatus": false
        },
        "tray": {
          "background": false,
          "compact": true,
          "recolour": false
        },
        "workspaces": {
          "activeIndicator": true,
          "activeTrail": false,
          "occupiedBg": false,
          "perMonitorWorkspaces": true,
          "showWindowsOnSpecialWorkspaces": true,
          "windowIcons": [
            {"regex": "steam(_app_(default|[0-9]+))?", "icon": "sports_esports"}
          ]
        }
      },
      "dashboard": {
        "showWeather": false
      },
      "general": {
        "apps": {
          "explorer": ["nautilus", "--new-window"],
          "terminal": ["${pkgs.ghostty}/bin/ghostty", "--gtk-single-instance=true"]
        },
        "idle": {
          "timeouts": [],
          "lockBeforeSleep": true,
          "inhibitWhenAudio": true,
          "inhibitWhenCharging": false
        }
      },
      "services": {
        "smartScheme": true
      }
    }
    CAELESTIA_CONFIG
        fi
  '';

  # Seed cli.json with explicit theme policy if absent.
  # Without this file, all enable* flags default to True and the CLI
  # silently attempts to theme Discord, Spicetify, Pandora, Warp,
  # Chromium, Zed, Cava, Fuzzel, Btop, Nvtop, Htop — none installed.
  # iconTheme defaults to Papirus-{mode}, which IS installed via
  # modules/nixos/desktop/common.nix. adw-gtk3 provides the GTK3 base
  # theme that Caelestia overlays with @define-color CSS variables.
  # postHook triggers hyprctl reload after scheme changes so the
  # sourced scheme/current.conf is re-evaluated.
  home.activation.writeCaelestiaCliConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -f "$HOME/.config/caelestia/cli.json" ]; then
      $DRY_RUN_CMD mkdir -p "$HOME/.config/caelestia"
      $DRY_RUN_CMD cat > "$HOME/.config/caelestia/cli.json" <<'CAELESTIA_CLI'
    {
      "theme": {
        "enableTerm": true,
        "enableHypr": true,
        "enableGtk": true,
        "enableQt": false,
        "enableFuzzel": false,
        "enableBtop": false,
        "enableNvtop": false,
        "enableHtop": false,
        "enableDiscord": false,
        "enableSpicetify": false,
        "enablePandora": false,
        "enableWarp": false,
        "enableChromium": false,
        "enableZed": false,
        "enableCava": false,
        "iconTheme": "Papirus-Dark",
        "iconThemeDark": "Papirus-Dark",
        "iconThemeLight": "Papirus-Light",
        "postHook": "hyprctl reload 2>/dev/null || true"
      }
    }
    CAELESTIA_CLI
    fi
  '';

  # First-login scheme seeding — if scheme.json is absent, run
  # `caelestia scheme set catppuccin mocha dark` to generate the
  # complete theme state (scheme.json, current.conf, sequences.txt,
  # gtk.css). Without this, a fresh install has no current.conf and
  # Hyprland's sourced color variables are undefined (transparent
  # borders until the user manually runs `caelestia scheme set`).
  # The CLI's postHook (hyprctl reload) will fail outside a Wayland
  # session — the `2>/dev/null || true` in the postHook handles this.
  # dconf writes may also fail (no D-Bus) — silently ignored by the
  # CLI's @log_exception decorator. The critical files are generated
  # regardless. Never overwrites existing user-chosen scheme state.
  home.activation.seedCaelestiaScheme = lib.hm.dag.entryAfter ["writeCaelestiaCliConfig"] ''
    if [ ! -f "$HOME/.local/state/caelestia/scheme.json" ]; then
      if command -v caelestia >/dev/null 2>&1; then
        $DRY_RUN_CMD caelestia scheme set catppuccin mocha dark 2>/dev/null || true
      fi
    fi
  '';

  # Profile avatar for Caelestia lock screen (ProfilePic.qml reads
  # ~/.face). Create symlink to the existing profile image via
  # activation script — cannot use home.file.source with an absolute
  # path in pure evaluation mode.
  home.activation.createFaceSymlink = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -f "$HOME/.local/share/profile.jpg" ] && [ ! -e "$HOME/.face" ]; then
      $DRY_RUN_CMD ln -s "$HOME/.local/share/profile.jpg" "$HOME/.face"
    fi
  '';

  # Ensure the old quickshell service is stopped and disabled.
  # The service name is "quickshell.service" — if it's still
  # enabled from a prior generation, systemd will keep starting it.
  # We explicitly disable it here so it doesn't conflict with
  # caelestia.service.
  systemd.user.services.quickshell = {
    Unit = {
      Conflicts = ["caelestia.service"];
      ConditionEnvironment = "INVALID_QUICKSHELL_LEGACY";
    };
    Service.ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";
    Install.WantedBy = lib.mkForce [];
  };
}
