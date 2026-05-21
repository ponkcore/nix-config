# cli.nix — modern CLI replacements with Gruvbox theming.
# Provides bat (cat), eza (ls), zoxide (cd), gh (GitHub CLI). The git
# pager (`delta`) lives in home/git.nix because that is where it is
# wired into the git config. MANPAGER is set in env.nix; fish aliases
# live in fish.nix.
_: {
  programs.bat = {
    enable = true;
    config = {
      theme = "gruvbox-dark";
      style = "plain";
    };
  };

  # eza — ls replacement (aliases set in fish.nix)
  programs.eza = {
    enable = true;
    icons = "auto";
    git = true;
  };

  # zoxide — cd replacement (auto-integrates with fish via programs.fish.enable)
  programs.zoxide = {
    enable = true;
  };

  # gh — GitHub CLI for repo/PR/release management. Auth state lives
  # in ~/.config/gh/hosts.yml after `gh auth login`; HM only installs
  # the binary. Shell completion is wired up automatically.
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      prompt = "enabled";
    };
  };
}
