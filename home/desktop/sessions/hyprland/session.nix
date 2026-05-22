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
      monitor = [
        "eDP-1, 2880x1800@120, 0x0, 2"
        ", preferred, auto, 1"
      ];

      # Clipboard, Hyprpaper, Waybar, Mako: managed by HM systemd services — auto-restart on crash
      exec-once = [
        "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
        "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
      ];

      "$terminal" = "ghostty";
      "$menu" = "rofi -show drun";
      "$browser" = "firefox";

      "$mainMod" = "SUPER";

      bind = [
        "$mainMod, Return, exec, $terminal"
        "$mainMod, B, exec, $browser"
        # Russian layout equivalents — Hyprland matches by keycode, not keysym,
        # so these work correctly (unlike kitty which matched by keysym)
        "$mainMod, И, exec, $browser"
        "$mainMod, D, exec, $menu"
        "$mainMod, В, exec, $menu"
        "$mainMod, Q, killactive"
        "$mainMod, Й, killactive"
        "$mainMod, M, exit"
        "$mainMod, Ь, exit"
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

        # Screenshots (hyprshot)
        ", Print, exec, hyprshot -m output -o ~/Pictures/Screenshots"
        "$mainMod, Print, exec, hyprshot -m region -o ~/Pictures/Screenshots"
        "$mainMod SHIFT, Print, exec, hyprshot -m window -o ~/Pictures/Screenshots"

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

      # ── Smart gaps: no gaps/border when single tiled window ─────────────
      # Maximizes usable area on a small 14" screen when focused on one app.
      # w[tv1] = 1 tiled visible window; f[1] = 1 fullscreen window
      workspace = [
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
      # On a 14" 1440×900 screen, most apps benefit from filling the workspace.
      # Terminals are the exception — two side-by-side at ~711px works fine.
      # Super+F toggles maximize off when you want an explicit split.
      windowrulev2 = [
        # ── Large apps: auto-maximize (fill workspace) ──────────────────
        "maximize, class:^(firefox)$"
        "maximize, class:^(chromium-browser)$"
        "maximize, class:^(windsurf)$"
        "maximize, class:^(org.gnome.Nautilus)$"
        "maximize, class:^(virt-manager)$"

        # ── Ayugram — popup panel style (toggled from waybar icon) ──────
        # Wayland app_id is com.ayugram.desktop (from .desktop file), not AyuGram.
        # Absolute size (700x754) preserves the exact dimensions the user
        # dialed in interactively on the 1440x900 logical panel; switching
        # to a different display means re-tuning here.
        "float, class:^(com.ayugram.desktop)$"
        "size 700 754, class:^(com.ayugram.desktop)$"
        "center, class:^(com.ayugram.desktop)$"

        # ── Clash Verge — popup panel style (toggled from waybar icon) ──
        # Wayland app_id taken from StartupWMClass in clash-verge.desktop.
        # Special workspace 'special:clash' is the hide target — same UX
        # pattern as Ayugram. First click launches, subsequent clicks
        # toggle visibility, never minimised to a system tray (Waybar has
        # no tray module on this host).
        "float, class:^(clash-verge)$"
        "size 911 719, class:^(clash-verge)$"
        "center, class:^(clash-verge)$"

        # ── Spotify — popup panel style (toggled from waybar icon) ──────
        # Spotify 1.2.74+ is native Wayland and reports app_id=spotify
        # (lowercase). Same hide/show contract as Telegram and Clash:
        # special workspace 'special:spotify' is the hide target. Size
        # tuned for the 14" 2.8K panel — slightly wider than the
        # natural Spotify default so the right-side queue panel fits
        # without horizontal scroll.
        "float, class:^(spotify)$"
        "size 1024 720, class:^(spotify)$"
        "center, class:^(spotify)$"

        # ── adw-{bluetooth,network} — popup panel style ─────────────────
        # Both libadwaita applets are toggled from waybar and share the
        # same visual contract: floating, centred, identical size. 600
        # is the smallest width that adw-network does not shrink below
        # (its content has a real min-content of ~590 with text-labelled
        # tabs); adw-bluetooth happily lives at the same width with a
        # touch of extra breathing room. Keeping them in lockstep means
        # the panels feel like a single coherent set in the panel UX.
        "float, class:^(com.ezratweaver.AdwBluetooth)$"
        "size 600 640, class:^(com.ezratweaver.AdwBluetooth)$"
        "center, class:^(com.ezratweaver.AdwBluetooth)$"

        "float, class:^(com.github.adw-network)$"
        "size 600 640, class:^(com.github.adw-network)$"
        "center, class:^(com.github.adw-network)$"

        # ── Waybar popup terminals ──────────────────────────────────────
        # btop — popup monitor panel (toggled from waybar CPU icon)
        "float, class:^(com.mitchellh.ghostty-btop)$"
        "size 80% 25%, class:^(com.mitchellh.ghostty-btop)$"
        "center, class:^(com.mitchellh.ghostty-btop)$"
        # rebuild — popup terminal (toggled from waybar NixOS icon, LKM)
        "float, class:^(com.mitchellh.ghostty-rebuild)$"
        "size 60% 70%, class:^(com.mitchellh.ghostty-rebuild)$"
        "center, class:^(com.mitchellh.ghostty-rebuild)$"
        # term — popup terminal (toggled from waybar NixOS icon, PKM)
        "float, class:^(com.mitchellh.ghostty-term)$"
        "size 60% 70%, class:^(com.mitchellh.ghostty-term)$"
        "center, class:^(com.mitchellh.ghostty-term)$"

        # ── Utility/dialog apps: float ──────────────────────────────────
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

        # ── Media: float + sensible size ────────────────────────────────
        "float, class:^(mpv)$"
        "size 70% 70%, class:^(mpv)$"
        "center, class:^(mpv)$"
        "float, class:^(imv)$"
        "float, class:^(org.gnome.Loupe)$"
        "float, class:^(eog)$"

        # ── Browser picture-in-picture: float + pin to corner ───────────
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
