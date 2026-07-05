# theme/themes/gruvbox-dark/default.nix — Gruvbox dark medium theme.
#
# Complete theme definition: palette + wallpaper + structural overrides
# for each UI component (waybar, mako, rofi, ghostty).
#
# To add a new theme: copy this directory, change palette.nix and/or
# any of the structural overrides below. theme/default.nix picks up
# the active theme by name.
#
# To switch themes at runtime (future): a rofi selector will write
# the theme name to a mutable state file; waybar reloads CSS via
# SIGUSR1. The structural layout here is the declarative base that
# all themes inherit from.
_: {
  palette = import ./palette.nix;
  wallpaper = ../../../assets/wallpaper.png;

  # ── Waybar ────────────────────────────────────────────────────────
  # Structural parameters consumed by theme/waybar/default.nix.
  # Changing these changes the bar layout without touching CSS.
  waybar = {
    position = "top";
    width = 496;
    spacing = 0;
    margins = {
      top = 0;
      bottom = 3;
      left = 6;
      right = 6;
    };
    borderRadius = 4;

    # Module layout. Sessions and hosts supply the actual module
    # definitions; the theme only controls the slot order. If a
    # module in the list has no definition, waybar silently skips it.
    modulesLeft = [
      "custom/separator"
      "custom/nix"
      "clock"
      "custom/separator"
    ];
    modulesCenter = [
      "hyprland/workspaces"
    ];
    modulesRight = [
      "custom/separator"
      "custom/cpu"
      "custom/separator"
      # Host-specific slots (custom/ultra-economy, custom/power-draw,
      # custom/battery) are injected by hosts/<name>/home/waybar.nix.
      # On lecoo these appear between custom/cpu and custom/power.
      # On other hosts the built-in "battery" module is used instead.
      "custom/power"
      "custom/separator"
    ];

    # Extra CSS appended after the palette-generated rules.
    # Used by future themes to inject structural overrides (pill shape,
    # bottom bar, etc.) without duplicating the base CSS.
    extraStyle = "";
  };

  # ── Mako ──────────────────────────────────────────────────────────
  # Currently driven entirely by palette — no structural overrides.
  mako = {};

  # ── Rofi ──────────────────────────────────────────────────────────
  rofi = {};

  # ── Ghostty ───────────────────────────────────────────────────────
  ghostty = {};
}
