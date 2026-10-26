# oh-my-pi — standalone coding agent binary package.
# Upstream ships a Bun-compiled Linux x64 ELF per release with a published
# sha256. We pin that release asset directly: no curl installer, no global Bun
# install, no mutable node_modules in $HOME.
#
# Host requirement: nix-ld (programs.nix-ld.enable = true). The binary's
# PT_INTERP is /lib64/ld-linux-x86-64.so.2 — the nix-ld shim — so the ELF can
# only be exec'd directly on a host that has it.
{
  lib,
  stdenv,
  fetchurl,
}: let
  pname = "oh-my-pi";
  version = "18.11.1";

  src = fetchurl {
    url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/omp-linux-x64";
    hash = "sha256-vx6GqTWx6iYWalKAAB7M6hIF5sIe/htYU/D9Nox1SXQ=";
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
      # Launch the Bun standalone binary DIRECTLY. Its PT_INTERP is
      # /lib64/ld-linux-x86-64.so.2 - on this host the nix-ld shim - which
      # execs the real loader with the ORIGINAL argv (binary first), so
      # omp's worker re-entry seam resolves process.execPath to this ELF
      # and every "__omp_worker_*" subprocess spawn works.
      #
      # DO NOT relaunch via an explicit "ld.so binary" exec (the
      # pre-2026-10-26 method). Under that launch the raw
      # /proc/self/cmdline keeps the loader as argv[0]; Bun then reports
      # process.execPath = the ld.so path, and every worker spawn becomes
      # "ld.so __omp_worker_SELECTOR" - the rtld opens the selector string
      # as the program file and exits 127. That silently killed every
      # subprocess-based feature (browser shared daemon, stats activity,
      # text-predict, JS eval subprocess) since the first 18.0.0
      # packaging.
      #
      # Pin the real loader to the glibc this package was built against
      # so loading is version-stable; NIX_LD_LIBRARY_PATH stays the host's.
      # NB: this heredoc is UNQUOTED - backticks and "\$..." in comment
      # text are executed/expanded at build time. Keep prose free of both.
      export NIX_LD="${dynamicLinker}"
      exec "$out/libexec/omp-linux-x64" "\$@"
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
