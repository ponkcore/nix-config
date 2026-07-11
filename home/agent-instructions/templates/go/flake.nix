{
  description = "Go development environment";

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
        name = "go-dev";

        buildInputs = with pkgs; [
          go
          gcc
          pkg-config
          gopls
          golangci-lint
        ];

        env = {
          GOPATH = "$HOME/go";
        };

        shellHook = ''
          echo "Go dev shell (NixOS 26.05)"
          echo "Go: $(go version)"
          export GOPATH="$HOME/go"
          export PATH="$GOPATH/bin:$PATH"
          mkdir -p "$GOPATH"
        '';
      };
    });
}
