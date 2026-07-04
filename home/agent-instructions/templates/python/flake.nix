{
  description = "Python development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      pythonEnv = pkgs.python313;
    in {
      devShells.default = pkgs.mkShell {
        name = "python-dev";

        buildInputs = with pkgs; [
          pythonEnv
          pythonEnv.pkgs.pip
          pythonEnv.pkgs.virtualenv
          gcc
          gnumake
          pkg-config
          zlib.dev
          openssl.dev
          uv
        ];

        shellHook = ''
          echo "Python dev shell (NixOS 26.05)"
          echo "Python: $(python --version)"

          if [ ! -d ".venv" ]; then
            echo "Creating virtual environment at .venv..."
            python -m venv .venv
          fi

          source .venv/bin/activate

          if [ -f "requirements.txt" ]; then
            pip install -r requirements.txt --quiet
          fi

          echo "Venv active: $(which python)"
        '';
      };
    });
}
