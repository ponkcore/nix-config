# fonts.nix — system-wide font catalogue + fontconfig defaults.
#
# Cyrillic + Latin + CJK + emoji + monospace nerd fonts; subpixel-RGB
# antialiasing, slight hinting (best for HiDPI displays where heavy
# hinting blurs glyphs). Default monospace is JetBrainsMono Nerd Font
# so glyphs in waybar / fish prompt / ghostty render uniformly.
{pkgs, ...}: {
  fonts = {
    enableDefaultPackages = false;

    packages = with pkgs; [
      # LGC = Latin + Greek + Cyrillic only (vs full noto-fonts with 1096 fonts)
      noto-fonts-lgc-plus
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      nerd-fonts.jetbrains-mono
      nerd-fonts.caskaydia-cove
      nerd-fonts.bigblue-terminal
      nerd-fonts.monaspace
      noto-fonts-color-emoji
    ];

    fontconfig = {
      enable = true;
      antialias = true;
      hinting = {
        enable = true;
        style = "slight";
      };
      subpixel = {
        rgba = "rgb";
        lcdfilter = "default";
      };
      defaultFonts = {
        serif = ["Noto Serif" "Noto Sans CJK SC"];
        sansSerif = ["Noto Sans" "Noto Sans CJK SC"];
        monospace = ["JetBrainsMono Nerd Font" "Noto Sans Mono CJK SC"];
        emoji = ["Noto Color Emoji"];
      };
    };
  };
}
