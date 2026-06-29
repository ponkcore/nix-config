# theme/default.nix — compositor-agnostic Wayland theming.
#
# Aggregator: exports the gruvbox palette `p`, the wallpaper path, and
# the color helpers `c` to all submodules via _module.args, then
# imports the user-level UI bits that work under ANY Wayland compositor
# — waybar, mako, rofi, ghostty, and the script library.
#
# Helper scripts (notification toggle, lecoo charge mode, telegram
# toggle, etc.) live in theme/scripts.nix to keep this file focused
# on visual concerns. Compositor-specific config (Hyprland keybinds,
# hyprlock, hypridle, hyprpaper; future niri/swaylock/swayidle/swaybg;
# future GNOME dconf) lives in home/desktop/sessions/<name>/ and is
# imported by home/desktop/default.nix based on the active session set.
#
# Imported from home/desktop/default.nix when desktops is non-empty.
# Headless/server hosts never see this file.
{
  pkgs,
  lib,
  ...
}: let
  # Palette derived from Gruvbox warm tones: amber, parchment, burnt umber.
  p = import ../lib/palette.nix;

  # Color helpers — convert palette tokens into the surface formats
  # different consumers expect (Hyprland literals, rofi rasi rgba,
  # GTK rgba). Single source of truth, replaces the three hand-rolled
  # converters previously inlined in session.nix, lock.nix and rofi.nix.
  c = import ../lib/color.nix;

  # Wallpaper paths. `wallpaper` remains the original full-resolution
  # asset for lock-screen use; `sessionWallpaper` is a pre-scaled copy
  # for the live Hyprland wallpaper daemon so hyprpaper does not keep a
  # large image resident just to paint a 2880x1800 panel.
  wallpaper = "${../assets/wallpaper.png}";
  sessionWallpaper = "${sessionWallpaperAsset}";
  sessionWallpaperAsset = pkgs.runCommand "wallpaper-session.png" {nativeBuildInputs = [pkgs.imagemagick];} ''
    magick \
      ${../assets/wallpaper.png} \
      -resize 2880x1800^ \
      -gravity center \
      -extent 2880x1800 \
      "$out"
  '';
in {
  # _module.args makes p, c, and wallpaper paths available as function
  # arguments to ALL submodules imported below (e.g.,
  # `{ pkgs, p, c, wallpaper, ... }:`). The script bin args are wired up
  # in scripts.nix.
  _module.args = {
    inherit p c wallpaper sessionWallpaper;
  };

  imports = [
    ./scripts.nix
    ./waybar
    ./ghostty.nix
    ./mako.nix
    ./rofi.nix
  ];

  # ── Cursor (Wayland-wide, session-level) ──────────────────────────────
  # home.pointerCursor sets XCURSOR_THEME/SIZE for the entire Wayland session,
  # installs theme to ~/.local/share/icons, and configures GTK/X11 fallback.
  # gtk.cursorTheme below is kept for GTK-specific overrides.
  home.pointerCursor = {
    name = "Capitaine Cursors (Gruvbox)";
    package = pkgs.capitaine-cursors-themed;
    size = 24;
    gtk.enable = true;
  };

  # ── dconf (GTK dark preference) ───────────────────────────────────────
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      # Supplementary accent hint — maps to #c88800 (dark amber), NOT
      # #fabd2f. The real fix is the CSS override below; this just
      # shifts the system-reported accent away from blue for apps
      # that query gsettings directly. May not be read on Hyprland
      # without gnome-settings-daemon.
      accent-color = "yellow";
    };
    "org/gnome/nautilus/window-state" = {
      maximized = false;
      initial-size = "(890, 550)";
    };
  };

  # ── GTK theme ─────────────────────────────────────────────────────────
  gtk = {
    enable = true;
    theme = {
      # gruvbox-gtk-theme ships proper gtk-4.0/ assets; the older
      # gruvbox-dark-gtk only carries gtk-2.0/3.0 and produces a
      # "Failed to import gtk.css" warning on every gtk4 launch
      # (mako, orbit, keepassxc, …).
      name = "Gruvbox-Dark";
      package = pkgs.gruvbox-gtk-theme;
    };
    cursorTheme = {
      name = "Capitaine Cursors (Gruvbox)";
      package = pkgs.capitaine-cursors-themed;
      size = 24;
    };
    iconTheme = {
      name = "oomox-gruvbox-dark";
      package = pkgs.gruvbox-dark-icons-gtk;
    };
  };

  # ── GTK4/libadwaita accent override ────────────────────────────────
  # libadwaita apps (Nautilus, Settings, pwvucontrol, etc.) hardcode
  # the accent color to Adwaita blue (#3584e4). The gruvbox-gtk-theme
  # GTK4 CSS uses @define-color (GTK named-color registry) but does
  # NOT set --accent-bg-color (CSS custom property), so libadwaita's
  # blue bleeds through on hover, selection, and active states.
  #
  # Root causes (research 2026-06-29-libadwaita-accent-override):
  #   1. Sass-compiled literals (_views.scss, _menus.scss) are baked
  #      at build time — CSS variable overrides can't reach them.
  #   2. .osd re-declares --accent-bg-color with higher specificity
  #      than :root — !important on :root is required.
  #   3. @define-color (underscore, GTK registry) and --accent-bg-color
  #      (dash, CSS variable) are separate namespaces — both needed.
  #   4. --accent-color is Oklab-derived from --accent-bg-color; must
  #      be set explicitly to avoid auto-derivation producing wrong hue.
  #
  # This override sets both namespaces + direct selector rules for all
  # 25 common libadwaita UI patterns. Written via xdg.configFile with
  # mkForce because HM's gtk module also writes gtk-4.0/gtk.css.
  xdg.configFile."gtk-4.0/gtk.css" = lib.mkForce {
    text = ''
      @import url("file://${pkgs.gruvbox-gtk-theme}/share/themes/Gruvbox-Dark/gtk-4.0/gtk.css");

      /* ── 1. GTK named-color registry (underscore syntax) ── */
      @define-color accent_bg_color ${p.accent_warm};
      @define-color accent_fg_color ${p.bg};
      @define-color accent_color ${p.accent_warm};

      /* ── 2. Core accent CSS variables on :root ── */
      /* !important required: .osd re-declares with higher specificity. */
      :root {
        --accent-bg-color: ${p.accent_warm} !important;
        --accent-fg-color: ${p.bg} !important;
        --accent-color: ${p.accent_warm} !important;
        --accent-blue: ${p.accent_warm} !important;
      }

      /* ── 3. Cascade propagation into floating surfaces ── */
      window, dialog, popover {
        --accent-bg-color: ${p.accent_warm};
        --accent-fg-color: ${p.bg};
        --accent-color: ${p.accent_warm};
      }

      /* ── 4. Suggested-action buttons ── */
      button.suggested-action { background-color: ${p.accent_warm}; color: ${p.bg}; }
      button.suggested-action:hover { background-color: #fcc84a; color: ${p.bg}; }
      button.suggested-action:active { background-color: #d9a520; color: ${p.bg}; }

      /* ── 5. Toggle / checked buttons ── */
      button:checked, togglebutton:checked { background-color: ${p.accent_warm}; color: ${p.bg}; }
      button:checked:hover, togglebutton:checked:hover { background-color: #fcc84a; color: ${p.bg}; }

      /* ── 6. Checkboxes and radio buttons ── */
      checkbutton check:checked, checkbutton check:indeterminate {
        background-color: ${p.accent_warm}; border-color: ${p.accent_warm}; color: ${p.bg};
      }
      radiobutton radio:checked {
        background-color: ${p.accent_warm}; border-color: ${p.accent_warm}; color: ${p.bg};
      }

      /* ── 7. Switches ── */
      switch:checked { background-color: ${p.accent_warm}; }
      switch:checked slider { background-color: ${p.bg}; }

      /* ── 8. Progress bars and level bars ── */
      progressbar progress, progressbar trough progress { background-color: ${p.accent_warm}; }
      levelbar block.filled, levelbar block.high { background-color: ${p.accent_warm}; border-color: #d9a520; }

      /* ── 9. Sliders / scales ── */
      scale highlight, scale trough highlight { background-color: ${p.accent_warm}; }
      scale slider:focus { outline-color: ${p.accent_warm}; }

      /* ── 10. Entry / text field focus ── */
      entry:focus, entry:focus-within, searchentry:focus, searchentry:focus-within,
      spinbutton:focus, spinbutton:focus-within, textview:focus {
        border-color: ${p.accent_warm}; outline-color: ${p.accent_warm};
        box-shadow: inset 0 0 0 2px ${p.accent_warm};
      }

      /* ── 11. Focus rings ── */
      *:focus-visible { outline-color: ${p.accent_warm}; box-shadow: 0 0 0 2px ${p.accent_warm}; }

      /* ── 12. List rows: selected and hover ── */
      row:selected { background-color: ${p.bg2}; color: ${p.fg}; }
      row:selected:hover { background-color: ${p.hover_bg}; color: ${p.fg}; }
      row:hover { background-color: rgba(250, 189, 47, 0.10); }
      row.button.suggested-action { background-color: ${p.accent_warm}; color: ${p.bg}; }
      row.button.suggested-action:hover { background-color: #fcc84a; color: ${p.bg}; }

      /* ── 13. Sidebar navigation items ── */
      .sidebar row:selected, .navigation-sidebar row:selected, stacksidebar list row:selected {
        background-color: ${p.bg2}; color: ${p.fg};
      }
      .sidebar row:selected:hover, .navigation-sidebar row:selected:hover {
        background-color: ${p.hover_bg};
      }
      .sidebar row:hover, .navigation-sidebar row:hover {
        background-color: rgba(250, 189, 47, 0.08);
      }

      /* ── 14. Headerbar selection mode ── */
      headerbar.selection-mode, .selection-mode headerbar, .selection-mode.titlebar {
        background-color: ${p.accent_warm}; color: ${p.bg};
      }
      headerbar.selection-mode button, .selection-mode headerbar button { color: ${p.bg}; }

      /* ── 15. Popovers and dropdown menus ── */
      /* _menus.scss uses Sass-compiled literals — direct rules required. */
      popover row:selected, popover modelbutton:selected, popover > contents row:hover {
        background-color: ${p.bg2}; color: ${p.fg};
      }
      popover modelbutton:hover, popover row:hover {
        background-color: rgba(250, 189, 47, 0.10);
      }
      popover.menu row:selected, popover.menu row:hover {
        background-color: ${p.bg2}; color: ${p.fg};
      }

      /* ── 16. Context menus ── */
      menu menuitem:hover, menu menuitem:selected {
        background-color: ${p.bg2}; color: ${p.fg};
      }

      /* ── 17. Tab bars ── */
      tabbar tab:checked, tabbar tab:selected { background-color: ${p.bg2}; color: ${p.fg}; }
      tabbar tab:hover { background-color: rgba(250, 189, 47, 0.08); }

      /* ── 18. File chooser sidebar and path bar ── */
      filechooser.sidebar row:selected, filechooser stacksidebar list row:selected {
        background-color: ${p.bg2}; color: ${p.fg};
      }
      filechooser pathbar button:checked, filechooser pathbar button.text-button:checked {
        background-color: ${p.accent_warm}; color: ${p.bg};
      }
      filechooser pathbar button:hover { background-color: rgba(250, 189, 47, 0.10); }

      /* ── 19. Text selection ── */
      selection { background-color: ${p.accent_warm}; color: ${p.bg}; }
      :root { --selection-bg-color: ${p.accent_warm}; --selection-fg-color: ${p.bg}; }

      /* ── 20. Links ── */
      *:link { color: ${p.accent_warm}; }
      *:link:hover { color: #fcc84a; }

      /* ── 21. Tooltips ── */
      tooltip { background-color: ${p.bg_mid}; color: ${p.fg}; border: 1px solid ${p.border}; }

      /* ── 22. OSD widgets ── */
      .osd progressbar progress, .osd levelbar block.filled { background-color: ${p.accent_warm}; }

      /* ── 23. Rubberband selection ── */
      rubberband, .rubberband {
        background-color: rgba(250, 189, 47, 0.25); border: 1px solid ${p.accent_warm};
      }

      /* ── 24. Expander rows ── */
      row.expander:checked > box > label { color: ${p.accent_warm}; }

      /* ── 25. Flowbox / gridview selected items ── */
      /* Sass-compiled $view_selected_color — direct override required. */
      flowbox > flowboxchild:selected, gridview > child.activatable:selected {
        background-color: ${p.bg2}; color: ${p.fg};
      }
      flowbox > flowboxchild:hover, gridview > child.activatable:hover {
        background-color: rgba(250, 189, 47, 0.10);
      }
    '';
  };
}
