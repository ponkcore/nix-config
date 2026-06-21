# media.nix — polished local media viewers for the desktop.
# Images open in GNOME Loupe, videos in Celluloid over the existing
# mpv engine, and local music in Gapless with the GStreamer codec
# plugins nixpkgs currently omits from its package closure.
{pkgs, ...}: let
  gapless-with-codecs = pkgs.gapless.overrideAttrs (old: {
    buildInputs =
      old.buildInputs
      ++ (with pkgs.gst_all_1; [
        gst-libav
        gst-plugins-ugly
      ]);
  });
in {
  home.packages = [
    pkgs.loupe
    pkgs.celluloid
    gapless-with-codecs
  ];
}
