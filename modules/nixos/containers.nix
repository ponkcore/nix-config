# containers.nix — Docker daemon + tooling.
#
# Universal: applies to any host that needs OCI containers. dockerd is
# socket-activated (enableOnBoot=false) so it stays cold until the user
# runs `docker` for the first time, after which systemd starts it on
# demand. autoPrune sweeps stale images weekly.
#
# Hosts that don't need containers can override `virtualisation.docker.enable
# = lib.mkForce false;` in their host module.
{pkgs, ...}: {
  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
    storageDriver = "overlay2";
  };

  # Docker CLI tools — colocated with Docker daemon config
  environment.systemPackages = with pkgs; [
    docker-compose
    dive
  ];
}
