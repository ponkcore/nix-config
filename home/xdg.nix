# xdg.nix — XDG user dirs + MIME associations.
# Default browser = Firefox; default text/code editor = Neovim
# (launched directly inside a uniquely-classed Ghostty so the
# Hyprland popup.tool window-rule floats it — see desktopEntries
# below; the dedicated class avoids spawning a tiled terminal via
# xdg-terminal-exec / com.mitchellh.ghostty.desktop).
{config, ...}: {
  xdg = {
    enable = true;

    # Override the upstream nvim.desktop (Terminal=true → forks via
    # xdg-terminal-exec → ghostty.desktop → no unique class → tiles)
    # with a launcher that spawns ghostty with the
    # `com.mitchellh.ghostty-nvim` class directly. The matching
    # window-rule in home/desktop/sessions/hyprland/session.nix
    # floats this class at popup.tool size (80%×65%). Used by
    # Nautilus when opening text/code files; in-terminal `nvim` is
    # untouched and stays inline.
    desktopEntries.nvim = {
      name = "Neovim wrapper";
      genericName = "Text Editor";
      comment = "Edit text files";
      icon = "nvim";
      # `-e nvim` invokes the editor inside ghostty; `--` passes the
      # remaining argv to nvim verbatim, so `nvim.desktop %F` lands
      # the selected file paths as nvim arguments.
      exec = "ghostty --class=com.mitchellh.ghostty-nvim -e nvim -- %F";
      terminal = false;
      categories = ["Utility" "TextEditor"];
      startupNotify = false;
      mimeType = [
        "text/english"
        "text/plain"
        "text/x-makefile"
        "text/x-c++hdr"
        "text/x-c++src"
        "text/x-chdr"
        "text/x-csrc"
        "text/x-java"
        "text/x-moc"
        "text/x-pascal"
        "text/x-tcl"
        "text/x-tex"
        "application/x-shellscript"
        "text/x-c"
        "text/x-c++"
      ];
      # Keywords mirror upstream so rofi search still resolves.
      settings = {
        Keywords = "Text;editor;";
        TryExec = "ghostty";
      };
    };

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
