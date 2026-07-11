{
  description = "Polyglot development environment (Python + Node.js)";

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
        name = "polyglot-dev";

        buildInputs = with pkgs; [
          python313
          uv
          nodejs_22
          pnpm
          gcc
          gnumake
          pkg-config
          openssl.dev
          zlib.dev
          curl
          jq
          git
        ];

        shellHook = ''
          echo "Polyglot dev shell (NixOS 26.05)"
          echo "Python: $(python --version)"
          echo "Node: $(node --version)"

          export npm_config_prefix="$HOME/.npm-global"
          export PATH="$HOME/.npm-global/bin:$PATH"
          mkdir -p "$HOME/.npm-global"

          if [ ! -d ".venv" ]; then
            echo "Creating Python venv at .venv..."
            python -m venv .venv
          fi
          source .venv/bin/activate

          echo "Ready. Python venv active, npm prefix set."
        '';
      };
    });
}
