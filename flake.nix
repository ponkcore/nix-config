{
  description = "ponkcore — portable NixOS configuration";

  # See docs/architecture.md for the layer model and lib/mkHost.nix
  # for the helper that turns a host spec into a nixosSystem.
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # agenix — encrypted secrets in the repo, decrypted on activation
    # using the target host's SSH host key. See secrets/secrets.nix
    # for authorised public keys and docs/handbook.md for the workflow.
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
      # No macOS hosts — drop the (stale) nix-darwin transitive input.
      inputs.darwin.follows = "";
    };

    # llm-agents pins its own nixpkgs because the npm packages it ships
    # are incompatible with our nixos channel. `inputs.nixpkgs.follows`
    # breaks the build.
    llm-agents.url = "github:numtide/llm-agents.nix";

    # letta-code — memory-first coding agent (letta-ai/letta-code).
    # Pinned to v0.30.24. Compaction for mod-provided models fixed
    # (v0.30.20), context_window race fixed (v0.28.8/v0.29.4),
    # auth.json base_url override fixed (v0.28.9).
    # The upstream bun.nix is stale; our overlay pkgs/letta-code/
    # provides a regenerated bun.nix.
    letta-code = {
      url = "github:letta-ai/letta-code/v0.30.24";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 26.05 migration: Hyprland flake input removed — 26.05 ships
    # hyprland 0.55.4 + all ecosystem packages natively.

    # Caelestia shell + CLI — forked from caelestia-dots.
    # All accepted phases (fork baseline, gating, wallpaper, launcher,
    # notifications, lock/idle, Lecoo power-mode + charge-limit bridge)
    # have landed on main.
    caelestia-shell = {
      url = "github:ponkcore/shell/main";
      inputs.nixpkgs.follows = "nixpkgs";
      # Mutual follows with caelestia-cli below — dedupes the shell's
      # own (lagging) cli input in favour of our pinned fork.
      inputs.caelestia-cli.follows = "caelestia-cli";
    };

    caelestia-cli = {
      url = "github:ponkcore/cli/main";
      inputs.nixpkgs.follows = "nixpkgs";
      # Use our pinned shell fork instead of the CLI's own (lagging)
      # caelestia-shell input — dedupes shell/quickshell/m3shapes nodes.
      inputs.caelestia-shell.follows = "caelestia-shell";
    };
  };

  outputs = {nixpkgs, ...} @ inputs: let
    mkHost = import ./lib/mkHost.nix {inherit inputs;};
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    nixosConfigurations = {
      lecoo = mkHost {
        hostname = "lecoo";
        username = "oonishi";
        inherit system;
        # Active desktop sessions on this host. Single-entry list →
        # defaultSession is inferred. To add niri/GNOME later: extend
        # this list and set defaultSession explicitly.
        desktops = ["hyprland"];
        modules = [./hosts/lecoo];
      };
    };

    # nixosTests covering invariants worth catching in CI before they
    # reach a real machine. See tests/default.nix for the menu and
    # tests/<name>.nix for the per-check rationale.
    checks.${system} = import ./tests {inherit pkgs inputs;};

    formatter.${system} = pkgs.alejandra;
  };
}
