# session.nix — per-user Hyprland configuration.
# Keybinds (US + RU layouts), window rules (maximise on small screens,
# float for utilities), animations, dwindle tuning, smart gaps, window
# groups, touchpad gestures. The system-level Hyprland enable lives in
# modules/nixos/desktop/sessions/hyprland.nix.
{
  config,
  pkgs,
  p,
  c,
  ...
}: let
  # Hyprland color literals — bare 8-digit RRGGBBAA hex with no
  # separator. Consumed by general.col.active_border, group borders,
  # groupbar, misc.background_color, and so on.
  rgba = c.hyprlandRGBA;

  # ── Floating popup sizing policy ────────────────────────────────────
  # Apps invoked from the waybar tray (chat clients, settings panels,
  # media players, terminal tools) all share the same UX contract:
  # float, given a fixed share of the workspace, centred. We codify
  # that as five categories so adding a new popup is one line, not a
  # three-line block scattered across the file.
  #
  # Sizes are expressed as percentages of the *logical* monitor size
  # (Hyprland resolves `size N% M%` against the post-scale geometry,
  # 1440×900 on this 14" 2.8K panel). Percentages move cleanly to a
  # different display; absolute pixel values do not.
  #
  # Rules of the road:
  #   - A category exists when ≥2 windows share the same visual
  #     contract. One-off windows stay as hand-written rules below.
  #   - `tool` is sized so a fullscreen TUI (btop, gptme, etc.) lands
  #     above the 80×24-char minimum; do not shrink it without
  #     re-checking that floor.
  #   - Override is for "almost the same, but slightly off"
  #     (e.g. one chat client wants a bit more height); use sparingly.
  popup = {
    chat = {
      width = "50%";
      height = "85%";
    }; # ayugram, telegram-likes
    tray = {
      width = "45%";
      height = "75%";
    }; # orbit (legacy: was also used by clash-verge popup)
    app = {
      # Roughly 1.5× smaller than the previous 70%×80% — Spotify
      # and Throne both fit the calmer footprint without horizontal
      # scrolling on their primary panes.
      width = "50%";
      height = "55%";
    }; # spotify, throne, other client apps
    tool = {
      width = "80%";
      height = "65%";
    }; # btop, ghostty popups, anything TUI
    media = {
      width = "70%";
      height = "70%";
    }; # mpv, image viewers
  };

  # Render `{match, category, override?}` to the three Hyprland rules
  # that every popup needs (float / size / center). `match` is a raw
  # Hyprland selector like `class:^(foo)$` or `title:^(foo)$` — both
  # forms work in `windowrulev2`. We pass it through verbatim so a
  # caller can match by title when class is shared (e.g. ghostty
  # under gtk-single-instance, where every window inherits the same
  # class from the host process).
  mkPopupRaw = {
    match,
    category,
    override ? {},
  }: let
    size = category // override;
  in [
    "float, ${match}"
    "size ${size.width} ${size.height}, ${match}"
    "center, ${match}"
  ];

  # Convenience wrapper for the common case: match by class.
  mkPopup = {
    class,
    category,
    override ? {},
  }:
    mkPopupRaw {
      match = "class:^(${class})$";
      inherit category override;
    };
in {
  # hyprshot — screenshot tool used in keybindings (no HM module, package only)
  home.packages = [pkgs.hyprshot];

  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;
    settings = {
      # Pin native panel mode + scale explicitly. The panel
      # (China Star SNE007ZA2-1, 14" 2.8K) advertises 120 Hz preferred
      # via EDID, but firmware can downshift to 60 Hz on certain BIOS
      # cold-boot paths — we hard-pin to avoid the drift. Fallback line
      # keeps any other monitor (HDMI dock, external DP) at preferred
      # mode and auto-position.
      # `vrr` here applies globally as a default; per-monitor we
      # override on the HDMI line below because the AOC 24G2W1G4
      # over HDMI 1.4 advertises FreeSync but flickers / drops the
      # signal when Hyprland actually drives VRR — disable it on
      # that output specifically.
      monitor = [
        "eDP-1, 2880x1800@120, 0x0, 2"
        # AOC 24G2W1G4: pin 1080p144 explicitly — `preferred` lands
        # on 60 Hz from EDID's preferred timing block. `vrr, 0`
        # disables FreeSync on this output (HDMI 1.4 + Hyprland VRR
        # flickers / drops the signal on this panel).
        "HDMI-A-1, 1920x1080@144, auto, 1, vrr, 0"
        ", preferred, auto, 1"
      ];

      # Clipboard, Hyprpaper, Waybar, Mako: managed by HM systemd services — auto-restart on crash
      exec-once = [
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
        "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"

        # Pre-warm the floating-terminal ghostty process: starts the
        # GTK4+OpenGL+fontconfig stack at login (~2.5 s) without
        # showing a window (`--initial-window=false`), so the first
        # Super+Return is a DBus-routed instant open instead of a
        # cold start. Process stays alive for the session because of
        # `quit-after-last-window-closed = false` in ghostty config.
        "ghostty --class=com.mitchellh.ghostty-floating --initial-window=false"
      ];

      # Plain ghostty would tile under the dwindle layout. We want
      # interactive terminals to come up floating at a fixed share of
      # the workspace.
      #
      # gtk-single-instance buckets ghostty processes by their app-id
      # (= `--class` value). With a unique class, this terminal gets
      # its own DBus-routed instance: first launch is a full GTK4
      # cold start (~2.5 s), every launch after is a DBus message to
      # the live process (~100 ms). The window inherits the class,
      # so the standard `mkPopup` rule below matches it. The popup
      # terminals (`-btop`, `-rebuild`, `-term`) follow the same
      # pattern, each with their own class.
      "$terminal" = "ghostty --class=com.mitchellh.ghostty-floating";
      "$menu" = "rofi -show drun";
      "$browser" = "firefox";

      "$mainMod" = "SUPER";

      bind = [
        "$mainMod, Return, exec, $terminal"
        "$mainMod, B, exec, $browser"
        # Russian layout equivalents — Hyprland matches by keycode, not keysym,
        # so these work correctly (unlike kitty which matched by keysym)
        "$mainMod, И, exec, $browser"
        # Application show/hide toggles — same scripts that drive the
        # waybar buttons. Each script parks the window on its own
        # special:<name> workspace; the toggle either pulls it onto
        # the current workspace (where the existing mkPopup rule keeps
        # it floating + sized + centred, so it sits above tiled
        # windows) or shoves it back to special. Russian layout dups
        # added by keycode (T→Е, S→Ы) so the chord survives a
        # caps-toggle layout switch.
        "$mainMod, T, exec, telegram-toggle"
        "$mainMod, Е, exec, telegram-toggle"
        "$mainMod, S, exec, spotify-toggle"
        "$mainMod, Ы, exec, spotify-toggle"
        "$mainMod, Q, killactive"
        "$mainMod, Й, killactive"
        "$mainMod, V, togglefloating"
        "$mainMod, М, togglefloating"
        "$mainMod, F, fullscreen"
        "$mainMod, А, fullscreen"
        "$mainMod, h, movefocus, l"
        "$mainMod, р, movefocus, l"
        "$mainMod, l, movefocus, r"
        "$mainMod, д, movefocus, r"
        "$mainMod, k, movefocus, u"
        "$mainMod, л, movefocus, u"
        "$mainMod, j, movefocus, d"
        "$mainMod, о, movefocus, d"
        "$mainMod, 1, workspace, 1"
        "$mainMod, 2, workspace, 2"
        "$mainMod, 3, workspace, 3"
        "$mainMod, 4, workspace, 4"
        "$mainMod, 5, workspace, 5"
        "$mainMod, 6, workspace, 6"
        "$mainMod, 7, workspace, 7"
        "$mainMod, 8, workspace, 8"
        "$mainMod, 9, workspace, 9"
        "$mainMod SHIFT, 1, movetoworkspace, 1"
        "$mainMod SHIFT, 2, movetoworkspace, 2"
        "$mainMod SHIFT, 3, movetoworkspace, 3"
        "$mainMod SHIFT, 4, movetoworkspace, 4"
        "$mainMod SHIFT, 5, movetoworkspace, 5"
        "$mainMod SHIFT, 6, movetoworkspace, 6"
        "$mainMod SHIFT, 7, movetoworkspace, 7"
        "$mainMod SHIFT, 8, movetoworkspace, 8"
        "$mainMod SHIFT, 9, movetoworkspace, 9"
        "$mainMod, R, exec, rofi -show drun"
        "$mainMod, К, exec, rofi -show drun"
        # Clipboard history — SUPER+C opens rofi with cliphist
        "$mainMod, C, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy"
        "$mainMod, С, exec, cliphist list | rofi -dmenu | cliphist decode | wl-copy"
        # Volume
        ", XF86AudioLowerVolume, exec, pamixer -d 5"
        ", XF86AudioRaiseVolume, exec, pamixer -u -i 5"
        ", XF86AudioMute, exec, pamixer -t"
        # Brightness
        ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
        ", XF86MonBrightnessUp, exec, brightnessctl set +5%"

        # Screenshots (hyprshot).
        # Bound to Super+P chords instead of Print/PrtSc because the
        # Lecoo Pro 14 ships PrtSc as Fn+F10 in firmware: holding any
        # software modifier (Super) cancels Fn, and the underlying
        # event reaches Wayland as plain F10 — not a Print keysym.
        # Verified with wev (key: 76, sym: F10). Super+P is a chord
        # under the left hand, conflict-free with our existing binds,
        # and independent of any Fn-Lock state.
        "$mainMod, P, exec, hyprshot -m output -o ~/Pictures/Screenshots"
        "$mainMod SHIFT, P, exec, hyprshot -m region -o ~/Pictures/Screenshots"
        "$mainMod CONTROL, P, exec, hyprshot -m window -o ~/Pictures/Screenshots"
        # RU layout — keep the same chord (P → З); Hyprland matches by
        # keycode within a layout, but we still register the cyrillic
        # variant explicitly so it survives the active-layout switch.
        "$mainMod, З, exec, hyprshot -m output -o ~/Pictures/Screenshots"
        "$mainMod SHIFT, З, exec, hyprshot -m region -o ~/Pictures/Screenshots"
        "$mainMod CONTROL, З, exec, hyprshot -m window -o ~/Pictures/Screenshots"

        # Window groups (tabbed layout)
        "$mainMod, G, togglegroup"
        "$mainMod, Г, togglegroup"
        "$mainMod, Tab, changegroupactive, f"
        "$mainMod SHIFT, Tab, changegroupactive, b"

        # Move windows with SUPER+SHIFT+hjkl
        "$mainMod SHIFT, h, movewindow, l"
        "$mainMod SHIFT, р, movewindow, l"
        "$mainMod SHIFT, l, movewindow, r"
        "$mainMod SHIFT, д, movewindow, r"
        "$mainMod SHIFT, k, movewindow, u"
        "$mainMod SHIFT, л, movewindow, u"
        "$mainMod SHIFT, j, movewindow, d"
        "$mainMod SHIFT, о, movewindow, d"
      ];

      # Resize windows with keyboard (vim-style + RU equivalents)
      binde = [
        "$mainMod CTRL, h, resizeactive, -30 0"
        "$mainMod CTRL, р, resizeactive, -30 0"
        "$mainMod CTRL, l, resizeactive, 30 0"
        "$mainMod CTRL, д, resizeactive, 30 0"
        "$mainMod CTRL, k, resizeactive, 0 -30"
        "$mainMod CTRL, л, resizeactive, 0 -30"
        "$mainMod CTRL, j, resizeactive, 0 30"
        "$mainMod CTRL, о, resizeactive, 0 30"
      ];

      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];

      # Lid switch — DPMS-off the internal panel only. Going through
      # `monitor disable` works but evacuates eDP-1's workspaces to
      # HDMI and never moves them back; DPMS just blanks the panel
      # while leaving the monitor object (and its workspaces) in
      # place, so HDMI is untouched and reopening the lid restores
      # everything exactly. logind already ignores lid events
      # (HandleLidSwitch=ignore at the system level), so suspend
      # never enters the picture either.
      bindl = [
        ", switch:on:Lid Switch, exec, hyprctl dispatch dpms off eDP-1"
        ", switch:off:Lid Switch, exec, hyprctl dispatch dpms on eDP-1"
      ];

      input = {
        kb_layout = "us,ru";
        kb_options = "grp:caps_toggle";
        follow_mouse = 1;
        sensitivity = 0;
        touchpad = {
          natural_scroll = true;
          disable_while_typing = true;
        };
      };

      # ── Cursor behaviour ────────────────────────────────────────────────
      # no_warps: when a window is moved (e.g. movewindow, movetoworkspace,
      # special-workspace toggle) Hyprland by default warps the pointer to
      # the new center. Disabling this keeps the cursor where the user
      # left it — preferred for the waybar-button toggle pattern, where
      # clicking the bar should not yank the mouse off-screen.
      cursor = {
        no_warps = true;
      };

      # ── Touchpad gestures (Hyprland 0.51+ new gesture system) ──────────
      gesture = [
        "3, horizontal, workspace"
      ];

      gestures = {
        workspace_swipe_distance = 250;
        workspace_swipe_cancel_ratio = 0.3;
      };

      # ── Dwindle layout tuning for 14" 1440×900 (logical) ───────────────
      dwindle = {
        preserve_split = true; # don't rearrange splits on resize
        force_split = 2; # always split right/bottom (predictable)
      };

      # ── General (borders, gaps) ─────────────────────────────────────────
      general = {
        gaps_in = 2;
        gaps_out = 3;
        border_size = 2;
        "col.active_border" = "${rgba p.fg_bright "ee"} ${rgba p.bg "ee"} 45deg";
        "col.inactive_border" = rgba p.border_inact "aa";
        resize_on_border = true;
      };

      # ── Workspace policy ───────────────────────────────────────────────
      # Pin workspaces to monitors. The dominant use case is docked
      # with the lid closed → HDMI is the primary surface and hosts
      # ws 1-8 (`default:true` on ws1 makes it the boot landing
      # workspace). eDP-1 hosts ws9 for ancillary tasks (chat,
      # monitoring) when the lid is open. `persistent:true` keeps
      # the workspaces alive even when empty so the per-monitor
      # binding survives across re-plug events.
      #
      # When HDMI is absent (laptop on the move), Hyprland evacuates
      # ws 1-8 to eDP-1 as fallback automatically; on re-plug the
      # `persistent` flag pulls them back to HDMI.
      #
      # Smart-gaps rules (w[tv1], f[1]) below: no gaps/border when a
      # single tiled or fullscreen window is visible — maximizes
      # usable area on the 14" panel.
      workspace = [
        "1, monitor:HDMI-A-1, default:true, persistent:true"
        "2, monitor:HDMI-A-1, persistent:true"
        "3, monitor:HDMI-A-1, persistent:true"
        "4, monitor:HDMI-A-1, persistent:true"
        "5, monitor:HDMI-A-1, persistent:true"
        "6, monitor:HDMI-A-1, persistent:true"
        "7, monitor:HDMI-A-1, persistent:true"
        "8, monitor:HDMI-A-1, persistent:true"
        "9, monitor:eDP-1, default:true, persistent:true"

        "w[tv1], gapsout:0, gapsin:0, border:false"
        "f[1], gapsout:0, gapsin:0, border:false"
      ];

      # ── Window groups (tabbed containers) ─────────────────────────────
      group = {
        "col.border_active" = "${rgba p.fg_bright "ee"} ${rgba p.bg "ee"} 45deg";
        "col.border_inactive" = rgba p.border_inact "aa";
        groupbar = {
          enabled = true;
          font_size = 10;
          height = 18;
          "col.active" = rgba p.border_act "ee";
          "col.inactive" = rgba p.bg_mid "cc";
          text_color = rgba p.fg "ff";
          gradients = false;
        };
      };

      # ── Decoration (rounding, shadow, blur) ────────────────────────────
      decoration = {
        rounding = 4;
        rounding_power = 3;
        shadow = {
          enabled = true;
          render_power = 3;
          range = 16;
          color = "rgba(00000052)";
        };
        blur = {
          enabled = true;
          size = 3;
          passes = 2;
        };
      };

      # ── Animations ─────────────────────────────────────────────────────
      animations = {
        enabled = true;
        bezier = [
          "expressiveFastSpatial, 0.42, 1.67, 0.21, 0.90"
          "expressiveSlowSpatial, 0.39, 1.29, 0.35, 0.98"
          "expressiveDefaultSpatial, 0.38, 1.21, 0.22, 1.00"
          "emphasizedDecel, 0.05, 0.7, 0.1, 1"
          "emphasizedAccel, 0.3, 0, 0.8, 0.15"
          "standardDecel, 0, 0, 0, 1"
          "menu_decel, 0.1, 1, 0, 1"
          "menu_accel, 0.52, 0.03, 0.72, 0.08"
        ];
        animation = [
          "windowsIn, 1, 3, emphasizedDecel, popin 80%"
          "windowsOut, 1, 2, emphasizedDecel, popin 90%"
          "windowsMove, 1, 3, emphasizedDecel, slide"
          "border, 1, 10, emphasizedDecel"
          "layersIn, 1, 2.7, emphasizedDecel, popin 93%"
          "layersOut, 1, 2.4, menu_accel, popin 94%"
          "fadeLayersIn, 1, 0.5, menu_decel"
          "fadeLayersOut, 1, 2.7, menu_accel"
          "workspaces, 1, 7, menu_decel, slide"
          "specialWorkspaceIn, 1, 2.8, emphasizedDecel, slidevert"
          "specialWorkspaceOut, 1, 1.2, emphasizedAccel, slidevert"
        ];
      };

      # ── Window rules ────────────────────────────────────────────────────
      # On a 14" 1440×900 logical panel, big apps benefit from filling the
      # workspace; popups (waybar-launched panels, TUI tools, media) follow
      # the `popup` category contract defined at the top of this file.
      # Super+F toggles maximize off when you want an explicit split.
      windowrulev2 =
        [
          # ── Large apps: auto-maximize (fill workspace) ──────────────────
          "maximize, class:^(firefox)$"
          "maximize, class:^(chromium-browser)$"
          "maximize, class:^(windsurf)$"
          "maximize, class:^(virt-manager)$"
        ]
        # ── Categorised popup panels ──────────────────────────────────────
        # Each call expands to three rules (float / size / center). See the
        # `popup` and `mkPopup` definitions at the top of this file for the
        # category sizes and the override mechanism.
        ++ (mkPopup {
          class = "com.ayugram.desktop";
          category = popup.chat;
        })
        # Throne (Xray/sing-box GUI) — popup.app sizing matches the
        # spotify / pwvucontrol slot family (70%×80%). The class is
        # bare `Throne` (capital T), verified at runtime against
        # `hyprctl clients`. The toggle script (throne-toggle)
        # parks the window on special:throne when hidden.
        ++ (mkPopup {
          class = "Throne";
          category = popup.app;
        })
        # orbit (network + bluetooth) is a layer-shell applet, not a
        # toplevel client — it does not appear in `hyprctl clients`,
        # so no window-rule is needed for it.
        ++ (mkPopup {
          class = "com.saivert.pwvucontrol";
          category = popup.tray;
        })
        ++ (mkPopup {
          class = "spotify";
          category = popup.app;
        })
        # KeePassXC — same `app` size category as Spotify/Throne
        # (50%×55%). Class is the lowercase reverse-DNS form
        # `org.keepassxc.KeePassXC`, verified at runtime against
        # `hyprctl clients`. The toggle script (keepassxc-toggle)
        # parks the window on special:keepassxc when hidden.
        ++ (mkPopup {
          class = "org.keepassxc.KeePassXC";
          category = popup.app;
        })
        ++ (mkPopup {
          class = "org.gnome.Nautilus";
          category = popup.app;
        })
        # btop and friends are TUI: `tool` is sized to clear the 80×24
        # character floor on this panel.
        ++ (mkPopup {
          class = "com.mitchellh.ghostty-btop";
          category = popup.tool;
        })
        ++ (mkPopup {
          class = "com.mitchellh.ghostty-rebuild";
          category = popup.tool;
        })
        ++ (mkPopup {
          class = "com.mitchellh.ghostty-term";
          category = popup.tool;
        })
        ++ (mkPopup {
          class = "mpv";
          category = popup.media;
        })
        # Floating Super+Return terminal — same `app` size category
        # as Spotify (70%×80%), so the two windows feel similar.
        # Class-based match works because `$terminal` launches with a
        # unique `--class` that opens its own gtk-single-instance
        # bucket; see the `$terminal` definition for the rationale.
        ++ (mkPopup {
          class = "com.mitchellh.ghostty-floating";
          category = popup.app;
        })
        ++ [
          # ── Utility/dialog apps: float (size left to the app) ───────────
          "float, class:^(blueman-manager)$"
          "float, class:^(blueman-adapters)$"
          "float, class:^(.blueman-manager-wrapped)$"
          "float, class:^(org.kde.kvantummanager)$"
          "float, class:^(qt5ct)$"
          "float, class:^(qt6ct)$"
          "float, class:^(nm-connection-editor)$"
          "float, class:^(pavucontrol)$"
          "float, class:^(xdg-desktop-portal-gtk)$"
          "float, class:^(org.gnome.Calculator)$"

          # ── Image viewers: float, native size ───────────────────────────
          "float, class:^(imv)$"
          "float, class:^(org.gnome.Loupe)$"
          "float, class:^(eog)$"

          # ── Browser picture-in-picture: float + pin to corner ───────────
          # Unique geometry (pinned to bottom-right), not a category member.
          "float, title:^(Picture-in-Picture)$"
          "pin, title:^(Picture-in-Picture)$"
          "size 25% 25%, title:^(Picture-in-Picture)$"
          "move 73% 72%, title:^(Picture-in-Picture)$"

          # ── File open/save dialogs: float + center ──────────────────────
          "float, title:^(Open File)(.*)$"
          "float, title:^(Save File)(.*)$"
          "float, title:^(Open Folder)(.*)$"
          "float, title:^(Save As)(.*)$"
          "float, title:^(Select a File)(.*)$"
          "float, title:^(Choose Files)(.*)$"
          "float, title:^(Confirm to replace files)(.*)$"
          "center, title:^(Open File)(.*)$"
          "center, title:^(Save File)(.*)$"
          "center, title:^(Open Folder)(.*)$"
          "center, title:^(Save As)(.*)$"
        ];

      env = [
        "XCURSOR_SIZE,24"
        "XCURSOR_THEME,Capitaine Cursors (Gruvbox)"
      ];

      # ── Misc (disable default wallpaper/splash, enable VRR) ─────────────
      # Without these, Hyprland briefly shows its default blue wallpaper + logo
      # between ReGreet exit and hyprpaper startup. background_color matches
      # our palette bg so the transition is seamless (black → bg → wallpaper).
      # vrr = 1: enable Adaptive-Sync on fullscreen content only — eliminates
      # tearing on video / games without flicker on static desktop content.
      # The Lecoo Pro 14 panel reports adaptive-sync support via EDID; on a
      # panel that doesn't, this option is a silent no-op.
      misc = {
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        background_color = rgba p.bg "ff";
        vrr = 1;
      };
    };
  };
}
