# env.nix — single source of truth for the user-shell session env vars
# that this flake actually owns.
#
# Cursor- and theme-related variables (XCURSOR_THEME, XCURSOR_SIZE,
# GTK_THEME analogues) are NOT set here: home.pointerCursor and the
# gtk module in theme/default.nix already emit them, and duplicating
# the values just means two places to keep in sync.
#
# Compositor-level env (Hyprland's `env = [...]`) is also separate:
# greetd → cage → uwsm starts with an empty environment, so the
# compositor needs explicit declarations regardless of what HM emits
# into ~/.config/hm-session-vars.sh.
_: {
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
  };
}
