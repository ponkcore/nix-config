# mpv.nix — Vulkan-accelerated media player.
# `vo=gpu-next` selects the modern Vulkan rendering pipeline (default
# in newer mpv); `hwdec=auto` lets ffmpeg pick AMD VAAPI decoder.
_: {
  programs.mpv = {
    enable = true;
    config = {
      hwdec = "auto";
      vo = "gpu-next";
      profile = "gpu-hq";
      keep-open = true;
    };
  };
}
