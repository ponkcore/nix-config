# btop.nix — interactive system monitor (htop successor).
_: {
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "gruvbox";
      theme_background = true;
      truecolor = true;
    };
  };
}
