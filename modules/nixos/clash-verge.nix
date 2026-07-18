# clash-verge.nix — Clash Verge Rev (mihomo) as the primary desktop
# proxy on lecoo. Throne remains installed and launchable as a manual
# fallback; exactly one TUN/DNS owner may be active at a time.
#
# `clash-verge.service` supervises the service IPC process, but the GUI
# starts `verge-mihomo` — it is NOT a standalone core supervisor.
# Restarting the service therefore requires the GUI to re-activate the
# core. This is an accepted trade-off for better GUI UX.
#
# TUN mode grants capabilities via security.wrappers so the GUI can
# create the TUN device without sudo. The TUN stack must be `system`
# (not gVisor/generic) for CloakBrowser transparent routing to work.
#
# DNS hijack is configured in the mutable GUI profile and handled by
# mihomo itself. Validate it after each profile or TUN-stack change.
# Profiles, Merge YAML, and subscriptions are mutable user state and
# are never committed or modified from Nix.
{...}: {
  programs.clash-verge = {
    enable = true;
    autoStart = false;
    serviceMode = true;
    tunMode = true;
  };

  # Trust the Clash Verge TUN interfaces so return traffic is not
  # dropped by nixos-fw-log-refuse. mihomo names its TUN device
  # "Mihomo" (system stack), "Meta" (gVisor stack), or "utun"
  # (generic) depending on the configured TUN stack. Only the
  # `system` stack is used in practice here, but all three are
  # trusted so a stack switch does not silently break connectivity.
  # `throne-tun` is trusted separately in security.nix.
  networking.firewall.trustedInterfaces = ["Mihomo" "Meta" "utun"];
}
