# oh-my-pi — standalone coding agent binary package.
# Upstream ships a Bun-compiled Linux x64 ELF per release with a published
# sha256. We pin that release asset directly: no curl installer, no global Bun
# install, no mutable node_modules in $HOME.
{
  lib,
  stdenv,
  fetchurl,
}: let
  pname = "oh-my-pi";
  version = "16.1.16";

  src = fetchurl {
    url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-linux-x64";
    hash = "sha256-68iuvhqOnrQobSoQhwIPckTMsjADU246CPeEbPUfaXw=";
  };

  inherit (stdenv.cc.bintools) dynamicLinker;
in
  stdenv.mkDerivation {
    inherit pname version src;

    dontUnpack = true;
    # Bun standalone binaries keep their compiled payload inside the ELF/trailer.
    # Rewriting the ELF with autoPatchelfHook makes the binary fall back to the
    # plain Bun runtime. Keep the upstream asset byte-for-byte and launch it via
    # Nix's dynamic linker instead.
    dontStrip = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 "$src" "$out/libexec/omp-linux-x64"
      mkdir -p "$out/bin"
      cat > "$out/bin/omp" <<EOF
      #!${stdenv.shell}
      exec "${dynamicLinker}" "$out/libexec/omp-linux-x64" "\$@"
      EOF
      chmod +x "$out/bin/omp"

      runHook postInstall
    '';

    meta = {
      description = "Coding agent with IDE, LSP, DAP, subagents, and native tools";
      homepage = "https://github.com/can1357/oh-my-pi";
      changelog = "https://github.com/can1357/oh-my-pi/releases/tag/v${version}";
      license = lib.licenses.mit;
      platforms = ["x86_64-linux"];
      mainProgram = "omp";
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
