{
  lib,
  fetchurl,
  appimageTools,
  writeShellScript,
  # Runtime libs (mirrored from upstream flake.nix — AGPL-3.0).
  webkitgtk_4_1,
  libsoup_3,
  glib,
  gtk3,
  cairo,
  gdk-pixbuf,
  pango,
  atk,
  at-spi2-atk,
  at-spi2-core,
  dbus,
  nss,
  nspr,
  libdrm,
  libgbm,
  libxkbcommon,
  xorg,
  xdotool,
  fontconfig,
  freetype,
  fribidi,
  harfbuzz,
  expat,
  libglvnd,
  mesa,
  libgpg-error,
  e2fsprogs,
  gmp,
  zlib,
  stdenv,
}: let
  pname = "donutbrowser";
  version = "0.24.1";

  src = fetchurl {
    url = "https://github.com/zhom/donutbrowser/releases/download/v${version}/Donut_${version}_amd64.AppImage";
    hash = "sha256-nJ4WmbXQcnXWDaneucOlwzZmlOOBx+G/qDeCHH6/Vno=";
  };

  # Runtime libraries the Tauri app pulls from the system (webkit/gtk/X11
  # stack). List is 1:1 with upstream commonLibs from flake.nix.
  extraPkgs = _: [
    webkitgtk_4_1
    libsoup_3
    glib
    gtk3
    cairo
    gdk-pixbuf
    pango
    atk
    at-spi2-atk
    at-spi2-core
    dbus
    nss
    nspr
    libdrm
    libgbm
    libxkbcommon
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxcb
    xorg.libxshmfence
    xorg.libXtst
    xorg.libXi
    xorg.libXrender
    xorg.libXinerama
    xorg.libXcursor
    xorg.libXScrnSaver
    xdotool
    fontconfig
    freetype
    fribidi
    harfbuzz
    expat
    libglvnd
    libgpg-error
    e2fsprogs
    gmp
    zlib
    stdenv.cc.cc.lib
  ];

  # Unpack to extract .desktop / .png — `wrapType2` itself only places
  # the binary, it does not carry desktop integration.
  contents = appimageTools.extract {inherit pname version src;};

  # Custom init script that bypasses AppRun.wrapped (the AppImage type2
  # runtime). AppRun.wrapped crashes inside bwrap because it reads
  # /proc/self/exe expecting an embedded squashfs — which doesn't exist
  # after extraction. We replicate the GTK env from the linuxdeploy hook
  # and exec the Tauri binary directly.
  customInit = writeShellScript "donutbrowser-init" ''
    source /etc/profile
    export APPDIR="${contents}"
    source "$APPDIR/apprun-hooks/linuxdeploy-plugin-gtk.sh"
    # The AppImage bundles Ubuntu's libwayland-{client,server,egl,cursor}.
    # These conflict with the system Wayland and cause:
    #   "Could not create default EGL display: EGL_BAD_PARAMETER. Aborting..."
    # Fix: create a filtered lib dir excluding libwayland*, so the system
    # Wayland libs from the FHS rootfs are used instead.
    # See: https://github.com/tauri-apps/tauri/issues/11994
    FILTERED_LIB=$(mktemp -d /tmp/donut-libs.XXXXXX)
    for f in "$APPDIR/usr/lib"/*; do
      case "$(basename "$f")" in
        libwayland*) ;; # skip — use system wayland
        *) ln -sf "$f" "$FILTERED_LIB/" ;;
      esac
    done
    export LD_LIBRARY_PATH="$FILTERED_LIB:$APPDIR/usr/lib/x86_64-linux-gnu:''${LD_LIBRARY_PATH:-}"
    # libglvnd needs the Mesa EGL vendor JSON to find libEGL_mesa.so.
    export __EGL_VENDOR_LIBRARY_DIRS="${mesa}/share/glvnd/egl_vendor.d"
    # Override GDK_BACKEND to native Wayland (the GTK hook sets x11).
    export GDK_BACKEND=wayland
    # WebKit spawns helper processes via a relative path from the binary.
    export WEBKIT_EXEC_PATH="$APPDIR/usr/lib/x86_64-linux-gnu/webkit2gtk-4.1"
    # The bundled libwebkit2gtk resolves helper process paths relative to
    # CWD (e.g. ././/lib/x86_64-linux-gnu/webkit2gtk-4.1/). The actual
    # binaries live under $APPDIR/usr/, so CWD must be $APPDIR/usr.
    cd "$APPDIR/usr"
    exec "$APPDIR/usr/bin/donutbrowser" "$@"
  '';
in
  appimageTools.wrapType2 {
    inherit pname version src extraPkgs;

    extraInstallCommands = ''
      # `wrapType2` produces $out/bin/donutbrowser. We add .desktop / icons
      # so it shows up in the Hyprland app launcher.
      install -Dm644 ${contents}/usr/share/applications/donutbrowser.desktop \
        $out/share/applications/donutbrowser.desktop
      for size in 32 128 256 512; do
        if [ -f ${contents}/usr/share/icons/hicolor/''${size}x''${size}/apps/donutbrowser.png ]; then
          install -Dm644 ${contents}/usr/share/icons/hicolor/''${size}x''${size}/apps/donutbrowser.png \
            $out/share/icons/hicolor/''${size}x''${size}/apps/donutbrowser.png
        fi
      done

      # Patch bwrap wrapper: replace the default init (which chains through
      # AppRun.wrapped and crashes) with our customInit that runs the Tauri
      # binary directly. Can't use substituteInPlace (chmod fails in sandbox),
      # so copy-sed-move instead.
      OLD_INIT=$(grep -oP '/nix/store/[a-z0-9]+-donutbrowser-[0-9.]+-init' $out/bin/donutbrowser)
      if [ -n "$OLD_INIT" ]; then
        sed "s|$OLD_INIT|${customInit}|g" $out/bin/donutbrowser > $out/bin/donutbrowser.tmp
        mv $out/bin/donutbrowser.tmp $out/bin/donutbrowser
        chmod +x $out/bin/donutbrowser
      fi
    '';

    meta = {
      description = "Open-source anti-detect browser (Tauri, Chromium/Firefox engines)";
      homepage = "https://donutbrowser.com";
      changelog = "https://github.com/zhom/donutbrowser/releases/tag/v${version}";
      license = lib.licenses.agpl3Only;
      platforms = ["x86_64-linux"];
      mainProgram = pname;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
