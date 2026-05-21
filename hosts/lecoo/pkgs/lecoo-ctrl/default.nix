{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  glibc,
  gcc,
}: let
  manifest = lib.importJSON ./manifest.json;
  inherit (manifest) version;
  inherit (stdenv.hostPlatform) system;

  platform =
    manifest.platforms.${system}
    or (throw "lecoo-ctrl: unsupported system ${system}");
in
  stdenv.mkDerivation {
    pname = "lecoo-ctrl";
    inherit version;

    src = fetchurl {
      inherit (platform) url sha256;
    };

    # The tarball ships two binaries at the top level (no subdirectory) —
    # the stdenv unpacker cannot infer sourceRoot automatically.
    sourceRoot = ".";

    # Pre-built dynamically-linked ELFs — autoPatchelfHook substitutes the
    # Nix interpreter and RPATH for libc / libgcc_s.
    nativeBuildInputs = [autoPatchelfHook];
    buildInputs = [glibc gcc.cc.lib];

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 lecoo-ec-daemon $out/bin/lecoo-ec-daemon
      install -Dm755 lecoo-ctrl      $out/bin/lecoo-ctrl

      runHook postInstall
    '';

    meta = {
      description = "Lecoo EC Control Daemon & CLI for Emdoor laptops (ITE IT5571-07)";
      homepage = "https://github.com/LaVashikk/Lecoo-Control-Center";
      changelog = "https://github.com/LaVashikk/Lecoo-Control-Center/releases/tag/v${version}";
      license = lib.licenses.mit;
      platforms = ["x86_64-linux"];
      mainProgram = "lecoo-ctrl";
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
