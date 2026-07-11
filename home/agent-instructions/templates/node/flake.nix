{
  description = "Node.js development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.default = pkgs.mkShell {
        name = "node-dev";

        buildInputs = with pkgs; [
          nodejs_22
          pnpm
          yarn
          python3
          gcc
          gnumake
          pkg-config
        ];

        shellHook = ''
          echo "Node.js dev shell (NixOS 26.05)"
          echo "Node: $(node --version)"
          echo "npm: $(npm --version)"

          export npm_config_prefix="$HOME/.npm-global"
          export PATH="$HOME/.npm-global/bin:$PATH"
          mkdir -p "$HOME/.npm-global"

          echo "npm global prefix: $npm_config_prefix"
          echo "Use 'npm install' for local installs. Use 'npx' for one-off tools."
        '';
      };
    });
}
