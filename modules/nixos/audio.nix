# audio.nix — PipeWire audio stack.
#
# Universal: laptops, desktops, VMs all benefit from PipeWire's unified
# routing for ALSA / PulseAudio / JACK clients. RTKit gives the audio
# threads realtime priority — without it, low-latency capture (e.g.
# JACK at 64 frames) has audible xruns.
_: {
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Realtime kit — needed by PipeWire for low-latency audio
  security.rtkit.enable = true;
}
