# audio.nix — PipeWire audio stack.
#
# Universal: laptops, desktops, VMs all benefit from PipeWire's unified
# routing for ALSA / PulseAudio / JACK clients. RTKit gives the audio
# threads realtime priority — without it, low-latency capture (e.g.
# JACK at 64 frames) has audible xruns.
{pkgs, ...}: {
  # Audio codec power saving — enter D3 after 1 second of idle
  # (default was 10s). The AMD ACP codec draws ~0.3 W when powered;
  # faster D3 entry saves a small but measurable amount on battery.
  # power_save_controller=Y also powers down the controller itself.
  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=1 power_save_controller=Y
  '';

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
