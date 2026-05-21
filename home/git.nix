# git.nix — git identity and config.
# delta is the diff/blame pager (programs.delta.enable + delta block).
# safe.directory whitelists /etc/nixos so root-owned repo doesn't trip
# git's CVE-2022-24765 dubious-ownership guard when the user runs git
# against it.
_: {
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "ponkcore";
        # GitHub-provided noreply address — keeps the real email private
        # while letting GitHub link commits to the ponkcore account.
        email = "275808243+ponkcore@users.noreply.github.com";
      };
      init = {
        defaultBranch = "main";
      };
      core = {
        editor = "nvim";
        pager = "delta";
      };
      interactive = {
        diffFilter = "delta --color-only";
      };
      delta = {
        navigate = true;
        side-by-side = true;
        line-numbers = true;
        syntax-theme = "gruvbox-dark";
      };
      merge = {
        conflictstyle = "diff3";
      };
      diff = {
        colorMoved = "default";
      };
      safe = {
        directory = "/etc/nixos";
      };
    };
  };

  programs.delta.enable = true;
}
