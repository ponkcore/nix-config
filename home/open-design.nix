# open-design.nix — local-first design product daemon + web frontend.
#
# Provides the `od` CLI and a browser-based UI (Next.js static SPA
# served by caddy, reverse-proxying /api/* to the daemon).
# Agents (opencode, claude, codex, …) are auto-discovered via PATH.
{inputs, ...}: {
  imports = [inputs.open-design.homeManagerModules.default];

  services.open-design = {
    enable = true;
    autoStart = true;
    webFrontend.enable = true;
  };
}
