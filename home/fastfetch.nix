# fastfetch.nix — system summary block (htop's faster alternative).
# Palette via _module.args.p. Invoked manually on demand.
{
  pkgs,
  p,
  ...
}: {
  programs.fastfetch = {
    enable = true;
    settings = {
      logo = {
        source = "nixos";
        color = {
          "1" = p.accent_warm;
          "2" = p.fg_bright;
          "3" = p.fg_dim;
          "4" = p.accent_warm;
        };
        padding = {
          right = 2;
        };
      };
      display = {
        separator = "  ";
        color = {
          keys = p.accent_warm;
          title = p.fg_bright;
        };
      };
      modules = [
        "title"
        "separator"
        "os"
        "kernel"
        "uptime"
        "packages"
        "separator"
        "cpu"
        "gpu"
        "memory"
        "swap"
        "disk"
        "separator"
        "wm"
        "shell"
        "terminal"
        "separator"
        {
          type = "colors";
          symbol = "circle";
        }
      ];
    };
  };
}
