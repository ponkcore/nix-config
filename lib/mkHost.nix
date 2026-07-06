# mkHost — helper to declare a NixOS host with minimal boilerplate.
#
# Usage (in flake.nix outputs):
#
#   nixosConfigurations = {
#     lecoo = mkHost {
#       hostname       = "lecoo";
#       username       = "oonishi";
#       system         = "x86_64-linux";
#       desktops       = [ "hyprland" ];        # may list multiple
#       defaultSession = "hyprland";            # required if >1 desktop
#       modules        = [ ./hosts/lecoo ];
#     };
#   };
#
# Every host gets:
#   - the universal NixOS module set (modules/nixos)
#   - the user's Home Manager profile (home/)
#   - the local package overlay (pkgs/)
#   - hostname propagated to networking.hostName
#   - hostname/username/desktops/defaultSession injected as
#     specialArgs (and extraSpecialArgs for HM) so any module can
#     react to the selected session set.
#
# Host-specific modules (hardware-configuration, hardware quirks, EC daemon,
# disk layout, etc.) come from `modules`. The host directory is just a
# composition file — it does not need to repeat the universal layer.
#
# `desktops` defaults to [] so headless/server hosts can omit it. The
# universal NixOS desktop layer is a no-op for an empty list. A host
# that DOES list desktops must also import modules/nixos/desktop —
# this is enforced by hosts/<name>/, not by this helper.
#
# `defaultSession` is required only when desktops has more than one
# entry; an assertion below catches misconfiguration at evaluation
# time rather than letting the greeter pick at random.
{inputs}: {
  hostname,
  username,
  system,
  desktops ? [],
  defaultSession ? null,
  modules ? [],
}: let
  # Resolve the effective default session: if the host listed exactly
  # one desktop, that is the default; otherwise take the explicit
  # defaultSession argument. An empty desktops list yields null.
  resolvedDefault =
    if defaultSession != null
    then defaultSession
    else if builtins.length desktops == 1
    then builtins.head desktops
    else null;
in
  inputs.nixpkgs.lib.nixosSystem {
    specialArgs = {
      inherit inputs hostname username desktops system;
      defaultSession = resolvedDefault;
    };
    modules =
      [
        # Sanity: if the host configures >1 desktop, defaultSession must
        # be set so the greeter has a deterministic pre-selection.
        ({lib, ...}: {
          assertions = [
            {
              assertion = builtins.length desktops <= 1 || defaultSession != null;
              message = ''
                mkHost: host "${hostname}" lists ${toString (builtins.length desktops)} desktop sessions
                (${lib.concatStringsSep ", " desktops}) but does not set defaultSession.
                Pass defaultSession = "<one of the above>" to mkHost.
              '';
            }
            {
              assertion =
                resolvedDefault == null || builtins.elem resolvedDefault desktops;
              message = ''
                mkHost: defaultSession = "${toString resolvedDefault}" for host "${hostname}"
                is not in desktops = [ ${lib.concatStringsSep " " desktops} ].
              '';
            }
          ];
        })

        # Universal NixOS layer — everything that should hold on any hardware.
        ../modules/nixos

        # Home Manager NixOS integration.
        inputs.home-manager.nixosModules.home-manager

        # Per-host wiring — set hostname and load the user's HM profile.
        (_: {
          nixpkgs.hostPlatform = system;
          nixpkgs.overlays = import ../pkgs {inherit inputs;};
          networking.hostName = hostname;

          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            # Without backupFileExtension any pre-existing non-symlink in a
            # path HM manages aborts activation. The home/cleanup.nix timer
            # purges stale .hm-backup files weekly.
            backupFileExtension = "hm-backup";
            users.${username} = import ../home;
            extraSpecialArgs = {
              inherit inputs hostname username desktops;
              defaultSession = resolvedDefault;
            };
          };

          nix.registry.nixpkgs.flake = inputs.nixpkgs;
        })
      ]
      ++ modules;
  }
