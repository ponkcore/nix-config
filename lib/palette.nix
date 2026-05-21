# palette.nix — Gruvbox-warm color tokens.
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
  bg = "#32302f";
  bg_mid = "#373737";
  fg = "#f0e4c5";
  fg_bright = "#fbf1c7";
  fg_dim = "#a89984";
  accent = "#706e6b";
  accent_warm = "#d4bd99";
  border = "#706e6b";
  border_inact = "#5a5755";
  border_act = "#7b6d60";
  hover_bg = "#706e6b";
  hover_fg = "#32302f";
  red = "#cc241d";
  bright_red = "#fb4934";
  green = "#928441";
  bright_green = "#b8bb26";
  yellow = "#ebdbb2";
  bright_yellow = "#fabd2f";
  blue = "#6b8a8a";
  bright_blue = "#83a598";
  magenta = "#957b87";
  bright_magenta = "#d3869b";
  cyan = "#7b9b72";
  bright_cyan = "#8ec07c";
  gray = "#7b6d60";
}
