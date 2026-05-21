{
  lib,
  stdenvNoCC,
  fetchurl,
}: let
  manifest = lib.importJSON ./manifest.json;
  inherit (manifest) version;
  inherit (stdenvNoCC.hostPlatform) system;

  platform =
    manifest.platforms.${system}
    or (throw "devin-cli: unsupported system ${system}");
in
  stdenvNoCC.mkDerivation {
    pname = "devin-cli";
    inherit version;

    src = fetchurl {
      inherit (platform) url sha256;
    };

    # The tarball is unpacked as `bin/` + `share/` at the top level — two
    # directories, which makes the stdenv unpacker complain "multiple
    # directories". `sourceRoot = "."` expands straight into $PWD.
    sourceRoot = ".";

    # static-pie ELF — nothing to patch (no interpreter, no RPATH).
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;
    dontStrip = true;
    dontPatchELF = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 bin/devin "$out/bin/devin"

      if [ -d share/man ]; then
        mkdir -p "$out/share/man"
        cp -r share/man/. "$out/share/man/"
      fi
      if [ -d share/devin ]; then
        mkdir -p "$out/share/devin"
        cp -r share/devin/. "$out/share/devin/"
      fi

      runHook postInstall
    '';

    meta = {
      description = "Cognition Devin command-line interface";
      homepage = "https://cli.devin.ai";
      changelog = "https://cli.devin.ai/docs/changelog";
      license = lib.licenses.unfree;
      platforms = ["x86_64-linux" "aarch64-linux"];
      mainProgram = "devin";
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
