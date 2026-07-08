# cloakbrowser — CloakBrowser stealth Chromium (free tier, v146).
#
# CloakBrowser patches Chromium at the C++ source level: 58 patches
# covering canvas, WebGL, audio, fonts, GPU, screen, WebRTC, network
# timing, automation signals, and CDP input behaviour.
#
# Key CloakBrowser C++ patches (not available in stock Chromium):
#   --fingerprint-device-memory  — spoofs navigator.deviceMemory (V8 patch)
#   --fingerprint-screen-*       — actually works (Screen DOM C++ patch)
#   --fingerprint-storage-quota  — normalizes storage quota (incognito detection)
#   --fingerprint-taskbar-height — spoofs screen.availHeight
#   --fingerprint-webrtc-ip      — spoofs WebRTC ICE candidates
#   navigator.webdriver = false  — source patch (not just flag)
#   navigator.plugins = 5        — real plugin list (not 0)
#   window.chrome present        — not undefined like ungoogled
#   TLS fingerprint              — identical to real Chrome (ja3/ja4)
#
# Free tier: Chromium 146 (previous major). Pro tier (v148, paid
# license) downloads from cloakbrowser.dev behind a key — not
# packageable without the key. When Chrome 149 ships, v148 rolls
# down to free.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  imagemagick,
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
  libx11,
  libxcb,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxrandr,
  libxrender,
  libxscrnsaver,
  libxtst,
}: let
  version = "146.0.7680.177.5";
  icon = fetchurl {
    url = "https://cloakbrowser.dev/favicon.ico";
    hash = "sha256-mDQixEi5h2iSqdcj7r8nuqSLMn2RR+0nacfq0nHZMi4=";
  };
in
  stdenv.mkDerivation {
    pname = "cloakbrowser";
    inherit version;

    src = fetchurl {
      url = "https://github.com/CloakHQ/CloakBrowser/releases/download/chromium-v${version}/cloakbrowser-linux-x64.tar.gz";
      hash = "sha256-ShK83pX6G7G+7ytBq15cJ8Nr544749DayMZNcFIWZw4=";
    };

    sourceRoot = ".";

    strictDeps = true;

    nativeBuildInputs = [
      autoPatchelfHook
      makeWrapper
      imagemagick
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
      libx11
      libxcb
      libxcomposite
      libxcursor
      libxdamage
      libxext
      libxfixes
      libxi
      libxrandr
      libxrender
      libxscrnsaver
      libxtst
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

      mkdir -p $out/opt/cloakbrowser $out/bin
      cp -R . $out/opt/cloakbrowser/

      makeWrapper $out/opt/cloakbrowser/chrome $out/bin/cloakbrowser \
        --prefix LD_LIBRARY_PATH : "$out/opt/cloakbrowser:$out/opt/cloakbrowser/lib:$out/opt/cloakbrowser/lib.target:$runtimeLibs" \
        --set-default NIXOS_OZONE_WL 1 \
        --set-default ELECTRON_OZONE_PLATFORM_HINT auto \
        --set-default __EGL_VENDOR_LIBRARY_DIRS "${mesa}/share/glvnd/egl_vendor.d" \
        --add-flags "--enable-features=UseOzonePlatform,WaylandWindowDecorations" \
        --add-flags "--ozone-platform=wayland" \
        --add-flags "--disable-non-proxied-udp"

      ln -s $out/opt/cloakbrowser/chromedriver $out/bin/cloakbrowser-chromedriver

      # Install icon (convert ICO first frame to PNG at multiple sizes)
      for size in 48 64 128 256; do
        mkdir -p $out/share/icons/hicolor/''${size}x''${size}/apps
        ${imagemagick}/bin/convert "${icon}[0]" -resize ''${size}x''${size} \
          $out/share/icons/hicolor/''${size}x''${size}/apps/cloakbrowser.png
      done

      runHook postInstall
    '';

    meta = {
      description = "Stealth Chromium with C++ source-level fingerprint patches (free tier, v146)";
      homepage = "https://github.com/CloakHQ/CloakBrowser";
      changelog = "https://github.com/CloakHQ/CloakBrowser/releases/tag/chromium-v${version}";
      license = lib.licenses.mit;
      platforms = ["x86_64-linux"];
      mainProgram = "cloakbrowser";
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
