# palette.nix — Gruvbox dark medium color tokens.
#
# Standard Gruvbox dark medium palette (gruvbox-community).
# Previous revision used a custom "warm" variant with desaturated
# colors and a yellow/fg mix-up; reverted to canonical values.
# To roll back: git checkout lib/palette.nix && nixos-rebuild switch.
#
# Single source of truth distributed three ways:
#   1. theme/default.nix exports it as `_module.args.p` for theme/* modules
#   2. home/{fzf,wlogout,yazi,fastfetch}.nix receive `p` via _module.args
#   3. Direct import from modules/nixos/desktop/greeter/greetd.nix (greetd CSS)
#
# Token semantics — see docs/architecture.md §4 for the role of each.
#
# Plain (non-rec) attribute set: tokens never reference each other,
# so a self-recursive scope only adds noise to the eval graph.
{
  # ── Backgrounds (dark → light) ──────────────────────────────────────
  bg_dark = "#1d2021"; # bg0_h — darkest background (Waybar bar)
  bg = "#282828"; # bg0 — base background (Hyprland, Ghostty, Waybar workspaces)
  bg_mid = "#3c3836"; # bg1 — widget backgrounds (Waybar modules, rofi)
  # Available but unused: #32302f (bg0_s), #504945 (bg2),
  # #665c54 (bg3), #7c6f64 (bg4 / fg4)

  # ── Foregrounds (light → dim) ───────────────────────────────────────
  fg = "#ebdbb2"; # fg0 — main text
  fg_bright = "#fbf1c7"; # fg0_bright — bright text (Gruvbox light bg = bright fg in dark)
  fg_dim = "#a89984"; # fg3 — dim/secondary text
  # Available but unused: #d5c4a1 (fg1), #bdae93 (fg2)

  # ── Accents ─────────────────────────────────────────────────────────
  accent = "#665c54"; # bg3 — neutral accent (buttons, inactive fills)
  accent_warm = "#fabd2f"; # bright_yellow — warm accent (Waybar highlight, Orbit)
  orange = "#d65d0e"; # dark orange
  bright_orange = "#fe8019"; # bright orange

  # ── Borders ─────────────────────────────────────────────────────────
  border = "#7c6f64"; # bg4 — default border
  border_inact = "#7c6f64"; # bg4 — inactive border (spec: #7c6f64)
  border_act = "#fabd2f"; # bright_yellow — active border (spec: #fabd2f)

  # ── Hover ───────────────────────────────────────────────────────────
  hover_bg = "#665c54"; # bg3 — hover background
  hover_fg = "#282828"; # bg0 — hover text (inverted)

  # ── ANSI 16-color palette (base / bright) ───────────────────────────
  red = "#cc241d";
  bright_red = "#fb4934";
  green = "#98971a";
  bright_green = "#b8bb26";
  yellow = "#d79921";
  bright_yellow = "#fabd2f";
  blue = "#458588";
  bright_blue = "#83a598";
  magenta = "#b16286";
  bright_magenta = "#d3869b";
  cyan = "#689d6a";
  bright_cyan = "#8ec07c";
  gray = "#7c6f64"; # bg4 — neutral gray for palette[8]
}
