# fzf.nix — fuzzy finder.
# Palette tokens come via _module.args.p (theme/default.nix injects).
# Fish keybindings (Ctrl+E edit, Ctrl+G git files, Ctrl+B git branches)
# live in fish.nix.
{p, ...}: {
  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
    ];
    colors = {
      inherit (p) bg fg border;
      hl = p.accent_warm;
      "hl+" = p.fg_bright;
      pointer = p.bright_yellow;
      marker = p.bright_green;
      spinner = p.bright_cyan;
      info = p.bright_blue;
      prompt = p.accent_warm;
    };
  };
}
