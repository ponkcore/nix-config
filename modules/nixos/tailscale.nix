# tailscale.nix — mesh VPN (manual start).
#
# Conflicts with mihomo TUN over DNS hijacking, so daemon is installed
# but `wantedBy=[]`. Run by hand only when needed:
#   sudo tailscale up --accept-routes
# tailscale0 is added to firewall trustedInterfaces so tailnet traffic
# is allowed without firewall rules.
{
  config,
  lib,
  ...
}: {
  # Tailscale — mesh VPN. This host is a client: accepts subnet routes
  # 192.168.10.0/24 from asuslaptop (router), advertises nothing itself.
  #
  # Autostart DISABLED — Tailscale conflicts with mihomo TUN (both hijack
  # DNS and routing). Bring up manually: sudo tailscale up --accept-routes
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "client";
    extraUpFlags = ["--accept-routes"];
  };

  # Do not start tailscaled automatically — only manually via
  # `sudo tailscale up --accept-routes`. This prevents the MagicDNS
  # (100.100.100.100) conflict with mihomo's DNS hijack.
  systemd.services.tailscaled.wantedBy = lib.mkForce [];

  # tailscale0 — trusted interface (tailnet traffic bypasses the firewall).
  networking.firewall.trustedInterfaces = ["tailscale0"];
}
