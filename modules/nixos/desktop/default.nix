# desktop/default.nix — Wayland desktop dispatcher.
#
# Reads the host's `desktops` list (set in flake.nix → mkHost) and
# imports the matching session/greeter modules. A host that does NOT
# pass any desktops gets nothing from this layer — that is the
# headless / server case.
#
# Contract:
#   - common.nix is imported whenever desktops is non-empty.
#   - sessions/<name>.nix is imported when "<name>" appears in desktops.
#   - greeter selection: gdm if "gnome" ∈ desktops, otherwise greetd.
#   - Adding a new session = drop a file under sessions/ and add the
#     corresponding lib.mkIf line below. No edits to existing sessions.
#
# `desktops` flows in via specialArgs from lib/mkHost.nix; if a host
# imports this module without going through mkHost, `desktops` is
# missing and the default below treats the host as headless.
{
  lib,
  desktops ? [],
  ...
}: let
  has = name: builtins.elem name desktops;
in {
  imports =
    lib.optionals (desktops != []) [
      ./common.nix
    ]
    ++ lib.optionals (has "hyprland") [./sessions/hyprland.nix]
    # Future sessions plug in here; the files do not exist yet but
    # the dispatcher already knows where to look. Adding niri/GNOME
    # later means creating ./sessions/<name>.nix and uncommenting
    # the corresponding line.
    # ++ lib.optionals (has "niri")     [ ./sessions/niri.nix     ]
    # ++ lib.optionals (has "gnome")    [ ./sessions/gnome.nix    ]
    # Greeter selection — gdm wins iff GNOME is active, otherwise
    # greetd + ReGreet handles all sessions (Hyprland, niri, …).
    ++ lib.optionals (desktops != [] && !(has "gnome")) [./greeter/greetd.nix];
  # ++ lib.optionals (has "gnome")                       [ ./greeter/gdm.nix    ];
}
