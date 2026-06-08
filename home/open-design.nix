# open-design.nix — local-first design product daemon + web frontend.
#
# Provides the `od` CLI and a browser-based UI (Next.js static SPA
# served by caddy, reverse-proxying /api/* to the daemon).
# Agents (opencode, claude, codex, …) are auto-discovered via PATH.
{
  inputs,
  pkgs,
  ...
}: {
  imports = [inputs.open-design.homeManagerModules.default];

  services.open-design = {
    enable = true;
    autoStart = true;
    webFrontend.enable = true;
    # zenity provides the native folder-picker dialog on Linux.
    # The daemon calls `zenity --file-selection --directory` when
    # the user clicks "Choose folder" or "New project" in the UI.
    extraBinPaths = ["${pkgs.zenity}/bin"];
    extraEnv = {
      GDK_BACKEND = "wayland";
    };
  };
}
