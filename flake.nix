{
  description = "ponkcore — portable NixOS configuration";

  # See docs/architecture.md for the layer model and lib/mkHost.nix
  # for the helper that turns a host spec into a nixosSystem.
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    # Cross-channel pull for individual packages whose stable
    # release is regressed or behind upstream. Currently used for
    # `throne`: nixos-25.11 ships 1.0.8-unstable-2025-10-29 with a
    # broken v1 NixOS patch (TUN elevation does not actually work);
    # nixos-unstable shipped 1.0.13 + corrected v2 patches in
    # nixpkgs commit d380eba (2026-01-25). See ADR / journal entry
    # for the rationale; remove this input once 25.11 receives the
    # backport.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
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
    };

    # llm-agents pins its own nixpkgs because the npm packages it ships
    # are incompatible with our nixos-25.11 channel. `inputs.nixpkgs.follows`
    # breaks the build.
    llm-agents.url = "github:numtide/llm-agents.nix";

    # poetry2nix — builds Poetry-managed Python applications without an
    # imperative `poetry install`. Used by pkgs/gptme/ since gptme is
    # not in nixpkgs and ships a poetry.lock at every release.
    poetry2nix = {
      url = "github:nix-community/poetry2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Open Design — local-first design product (daemon + web frontend).
    # Ships its own Home Manager module via homeManagerModules.default.
    open-design.url = "github:nexu-io/open-design";

    # letta-code — memory-first coding agent (letta-ai/letta-code).
    # Pinned to v0.27.9 (pi-ai@^0.79.1, mods support). The upstream
    # bun.nix is stale (still references pi-ai@0.75.5); our overlay
    # pkgs/letta-code/ provides a regenerated bun.nix.
    letta-code = {
      url = "github:letta-ai/letta-code/v0.27.9";
      inputs.nixpkgs.follows = "nixpkgs";
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
