# fonts.nix — system-wide font catalogue + fontconfig defaults.
#
# Cyrillic + Latin + CJK + emoji + monospace nerd fonts; subpixel-RGB
# antialiasing, slight hinting (best for HiDPI displays where heavy
# hinting blurs glyphs). Default monospace is JetBrainsMono Nerd Font
# so glyphs in shell/UI components render uniformly.
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
      nerd-fonts.commit-mono
      nerd-fonts.departure-mono
      nerd-fonts.bigblue-terminal
      nerd-fonts.monaspace
      noto-fonts-color-emoji

      # Cozette — 6×13 bitmap font, designed for bars / status panels.
      # Kept as a compact pixel-art option for small utility surfaces.
      cozette

      # Inter — modern sans-serif designed for screen UI (Rasmus
      # Andersson, 2016+). Available system-wide as a known UI sans option.
      inter

      # IBM Plex — corporate sans/serif/mono family, calm tone,
      # excellent at small sizes. Kept as an auxiliary humanist UI option.
      ibm-plex
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
