# tailscale.nix — mesh VPN (manual start).
#
# Conflicts with throne's TUN mode over DNS hijacking, so the daemon is
# installed but `wantedBy=[]`. Run by hand only when needed:
#   sudo tailscale up --accept-routes
# tailscale0 is added to firewall trustedInterfaces so tailnet traffic
# is allowed without firewall rules.
{lib, ...}: {
  # Tailscale — mesh (peer-to-peer) VPN. Every node runs `tailscaled`,
  # auths once against the coordination server, then talks directly to
  # other nodes in the same tailnet over WireGuard. Each node gets a
  # stable 100.x.y.z IP that "follows" it across networks.
  #
  # Two roles a node can take:
  #   - client (this host) — joins the tailnet, can reach other nodes
  #     by their 100.x.y.z (or MagicDNS hostname) and accepts the
  #     subnet routes other nodes advertise. Does not expose any of
  #     its local subnets back to the tailnet.
  #   - subnet router — additionally advertises one or more of its
  #     local CIDRs (`tailscale up --advertise-routes=192.168.10.0/24`),
  #     so other clients can reach plain LAN devices behind it as if
  #     they were on the tailnet. Optionally exit-node, accepting all
  #     of another client's egress traffic.
  # `useRoutingFeatures = "client"` selects the first role: kernel-
  # level `net.ipv4.ip_forward` and `net.ipv6.conf.all.forwarding` are
  # left off, so this host cannot route on behalf of other peers even
  # if asked. `--accept-routes` makes it consume routes that subnet
  # routers in the tailnet advertise.
  #
  # Autostart DISABLED — Tailscale conflicts with throne's TUN mode
  # (`programs.throne.tunMode.enable` in modules/nixos/desktop/common.nix):
  # both grab the system DNS and a TUN-style default route, so running
  # them simultaneously breaks resolution and outgoing connectivity.
  # Bring tailscaled up manually only when throne is down:
  #   sudo systemctl start tailscaled
  #   sudo tailscale up --accept-routes
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "client";
    extraUpFlags = ["--accept-routes"];
  };

  # Do not start tailscaled automatically — only manually via
  # `sudo tailscale up --accept-routes`. Prevents the MagicDNS
  # (100.100.100.100) collision with throne's DNS hijack.
  systemd.services.tailscaled.wantedBy = lib.mkForce [];

  # tailscale0 — trusted interface (tailnet traffic bypasses the firewall).
  networking.firewall.trustedInterfaces = ["tailscale0"];
}
