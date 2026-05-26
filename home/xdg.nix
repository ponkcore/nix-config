# xdg.nix — XDG user dirs + MIME associations.
# Default browser = Firefox; default text/code editor = Neovim
# (Terminal=true desktop entries fork a Ghostty via xdg-terminal-exec —
# package added in theme/ghostty.nix).
{config, ...}: {
  xdg = {
    enable = true;

    userDirs = {
      enable = true;
      download = "${config.home.homeDirectory}/Downloads";
      documents = "${config.home.homeDirectory}/Documents";
      music = "${config.home.homeDirectory}/Music";
      pictures = "${config.home.homeDirectory}/Pictures";
      videos = "${config.home.homeDirectory}/Videos";
      desktop = null;
      publicShare = null;
      templates = null;
    };

    mimeApps = {
      enable = true;
      defaultApplications = {
        # Browser
        "x-scheme-handler/http" = "firefox.desktop";
        "x-scheme-handler/https" = "firefox.desktop";
        "x-scheme-handler/chrome" = "firefox.desktop";
        "text/html" = "firefox.desktop";
        "application/xhtml+xml" = "firefox.desktop";

        # Terminal (for Terminal=true desktop entries like nvim)
        "x-scheme-handler/terminal" = "com.mitchellh.ghostty.desktop";

        # Obsidian deep-links (obsidian://open?vault=… etc.)
        "x-scheme-handler/obsidian" = "obsidian.desktop";

        # Text / code — all opened in Neovim
        "text/plain" = "nvim.desktop";
        "text/markdown" = "nvim.desktop";
        "text/x-markdown" = "nvim.desktop";
        "text/xml" = "nvim.desktop";
        "text/css" = "nvim.desktop";
        "text/javascript" = "nvim.desktop";
        "text/x-python" = "nvim.desktop";
        "text/x-python3" = "nvim.desktop";
        "text/x-shellscript" = "nvim.desktop";
        "text/x-c" = "nvim.desktop";
        "text/x-csrc" = "nvim.desktop";
        "text/x-chdr" = "nvim.desktop";
        "text/x-c++src" = "nvim.desktop";
        "text/x-c++hdr" = "nvim.desktop";
        "text/x-go" = "nvim.desktop";
        "text/x-rust" = "nvim.desktop";
        "text/x-java" = "nvim.desktop";
        "text/x-nix" = "nvim.desktop";
        "text/x-makefile" = "nvim.desktop";
        "text/x-toml" = "nvim.desktop";
        "text/x-yaml" = "nvim.desktop";
        "application/json" = "nvim.desktop";
        "application/xml" = "nvim.desktop";
        "application/x-shellscript" = "nvim.desktop";
        "inode/directory" = "org.gnome.Nautilus.desktop";
      };
    };
  };
}
