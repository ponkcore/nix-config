# fingerprint-chromium — Chromium/V8 anti-detect spike package.
# Upstream ships delayed-source releases: the current binary is
# available before the matching patch source. This derivation wraps the
# Linux TAR.XZ binary for a time-boxed NixOS validation spike only.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  fontconfig,
  freetype,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libglvnd,
  libnotify,
  libpulseaudio,
  libuuid,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  udev,
  vulkan-loader,
  xorg,
}: let
  version = "148.0.7778.215";
  archiveVersion = "${version}-1";
in
  stdenv.mkDerivation {
    pname = "fingerprint-chromium";
    inherit version;

    src = fetchurl {
      url = "https://github.com/adryfish/fingerprint-chromium/releases/download/${version}/ungoogled-chromium-${archiveVersion}-x86_64_linux.tar.xz";
      hash = "sha256-cNI5gwMy5YIKo038soQWHKwEKe7iXaZCgwr+BL2nF/Q=";
    };

    sourceRoot = "ungoogled-chromium-${archiveVersion}-x86_64_linux";

    strictDeps = true;

    nativeBuildInputs = [
      autoPatchelfHook
      makeWrapper
    ];

    buildInputs = [
      alsa-lib
      at-spi2-atk
      at-spi2-core
      cairo
      cups
      dbus
      expat
      fontconfig
      freetype
      glib
      gtk3
      libdrm
      libgbm
      libglvnd
      libnotify
      libpulseaudio
      libuuid
      libxkbcommon
      mesa
      nspr
      nss
      pango
      stdenv.cc.cc.lib
      udev
      vulkan-loader
      xorg.libX11
      xorg.libxcb
      xorg.libXcomposite
      xorg.libXcursor
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXrandr
      xorg.libXrender
      xorg.libXScrnSaver
      xorg.libXtst
    ];

    runtimeLibs = lib.makeLibraryPath ([
        libgbm
        libglvnd
        mesa
        vulkan-loader
      ]
      ++ [stdenv.cc.cc.lib]);

    dontConfigure = true;
    dontBuild = true;

    autoPatchelfIgnoreMissingDeps = [
      "libQt5Core.so.5"
      "libQt5Gui.so.5"
      "libQt5Widgets.so.5"
      "libQt6Core.so.6"
      "libQt6Gui.so.6"
      "libQt6Widgets.so.6"
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p $out/opt/fingerprint-chromium $out/bin
      cp -R . $out/opt/fingerprint-chromium/

      makeWrapper $out/opt/fingerprint-chromium/chrome $out/bin/fingerprint-chromium \
        --prefix LD_LIBRARY_PATH : "$out/opt/fingerprint-chromium:$out/opt/fingerprint-chromium/lib:$out/opt/fingerprint-chromium/lib.target:$runtimeLibs" \
        --set-default NIXOS_OZONE_WL 1 \
        --set-default ELECTRON_OZONE_PLATFORM_HINT auto \
        --set-default __EGL_VENDOR_LIBRARY_DIRS "${mesa}/share/glvnd/egl_vendor.d" \
        --add-flags "--enable-features=UseOzonePlatform,WaylandWindowDecorations" \
        --add-flags "--ozone-platform=wayland" \
        --add-flags "--disable-non-proxied-udp"

      ln -s $out/bin/fingerprint-chromium $out/bin/fp-chromium
      ln -s $out/opt/fingerprint-chromium/chromedriver $out/bin/fingerprint-chromedriver

      install -Dm644 $out/opt/fingerprint-chromium/product_logo_48.png \
        $out/share/icons/hicolor/48x48/apps/fingerprint-chromium.png

      runHook postInstall
    '';

    meta = {
      description = "Chromium/V8 anti-detect browser with seed-based fingerprint spoofing";
      homepage = "https://github.com/adryfish/fingerprint-chromium";
      changelog = "https://github.com/adryfish/fingerprint-chromium/releases/tag/${version}";
      license = lib.licenses.bsd3;
      platforms = ["x86_64-linux"];
      mainProgram = "fingerprint-chromium";
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
