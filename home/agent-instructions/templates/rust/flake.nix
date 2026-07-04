{
  description = "Rust development environment";

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
    in {
      devShells.default = pkgs.mkShell {
        name = "rust-dev";

        buildInputs = with pkgs; [
          rustup
          gcc
          pkg-config
          openssl.dev
          openssl.out
          libiconv
        ];

        env = {
          OPENSSL_DIR = "${pkgs.openssl.dev}";
          OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
          OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";
          PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
        };

        shellHook = ''
          echo "Rust dev shell (NixOS 26.05)"

          if ! rustup toolchain list | grep -q stable; then
            rustup toolchain install stable
          fi

          echo "Rust: $(rustc --version 2>/dev/null || echo 'run: rustup toolchain install stable')"
          echo "Cargo: $(cargo --version 2>/dev/null || echo 'not yet installed')"
        '';
      };
    });
}
