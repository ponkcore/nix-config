# direnv.nix — auto-activated environments per directory.
# `nix-direnv` extends classic direnv with `use flake` / `use nix` so
# entering a project dir transparently builds its devshell. Fish
# integration auto-enables when programs.fish.enable = true.
_: {
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
