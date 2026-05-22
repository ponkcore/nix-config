# adw-network — GNOME-inspired NetworkManager frontend (GTK4 + libadwaita).
#
# Upstream is a Rust + GTK4/libadwaita app (PlayRood32/adw-network). It is
# not in nixpkgs (Feb 2026 — AUR only), and the upstream tag does not ship
# a Cargo.lock, which would force a fragile vendor strategy if we built
# from source. The release tarball is a single statically-prepared
# Linux/x86_64 binary, so we follow the donutbrowser pattern: prebuilt
# binary, fixed at runtime via autoPatchelfHook, integrated with GTK
# resources via wrapGAppsHook4.
#
# Runtime deps for the binary itself are picked up by autoPatchelfHook
# (gtk4, libadwaita, glib, gdk-pixbuf, dbus, openssl, …). The app then
# shells out to NetworkManager / iw for actual network ops, so we add
# them to PATH via the GApps wrapper.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  wrapGAppsHook4,
  makeWrapper,
  # Runtime libraries the prebuilt binary links against.
  gtk4,
  libadwaita,
  glib,
  gdk-pixbuf,
  cairo,
  pango,
  graphene,
  harfbuzz,
  dbus,
  openssl,
  libsecret,
  # Runtime tools invoked at runtime (nmcli, nmtui, iw, …).
  networkmanager,
  iw,
}: let
  pname = "adw-network";
  version = "1.0.0";

  binTar = fetchurl {
    url = "https://github.com/PlayRood32/adw-network/releases/download/v${version}/adwaita-network-linux-x86_64.tar.gz";
    hash = "sha256-yhioC0w1UWR6dTALKGzqDqLxqMIWJw44TSliS6UKUK4=";
  };

  # The release tarball ships only the binary; .desktop and icon live in
  # the git tag, fetched separately so we don't pull a full git clone.
  desktopFile = fetchurl {
    url = "https://raw.githubusercontent.com/PlayRood32/adw-network/v${version}/data/com.github.adw-network.desktop";
    hash = "sha256-h+IhMhZ/22Nyz0+98aYKBEno7x5YidGhVqjrVAwGkDg=";
  };

  iconFile = fetchurl {
    url = "https://raw.githubusercontent.com/PlayRood32/adw-network/v${version}/data/icons/hicolor/scalable/apps/icon.png";
    hash = "sha256-UYoyir7hkjm6XyC8v+PxXEdLxcGLityzfJeT7PfGQMw=";
  };
in
  stdenv.mkDerivation {
    inherit pname version;
    src = binTar;
    sourceRoot = ".";

    nativeBuildInputs = [
      autoPatchelfHook
      wrapGAppsHook4
      makeWrapper
    ];

    buildInputs = [
      gtk4
      libadwaita
      glib
      gdk-pixbuf
      cairo
      pango
      graphene
      harfbuzz
      dbus
      openssl
      libsecret
    ];

    # No build phase — we ship a prebuilt ELF.
    dontBuild = true;
    dontConfigure = true;

    unpackPhase = ''
      runHook preUnpack
      tar -xzf $src
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall

      install -Dm755 adwaita-network $out/bin/adwaita-network
      install -Dm644 ${desktopFile}  $out/share/applications/com.github.adw-network.desktop
      install -Dm644 ${iconFile}     $out/share/icons/hicolor/scalable/apps/icon.png

      runHook postInstall
    '';

    # GApps wrapper handles GIO_MODULE_DIR and XDG_DATA_DIRS for GSchemas.
    # We further extend PATH so the app can shell out to nmcli / iw.
    preFixup = ''
      gappsWrapperArgs+=(
        --prefix PATH : ${lib.makeBinPath [networkmanager iw]}
      )
    '';

    meta = {
      description = "Modern NetworkManager frontend (Rust + GTK4 + libadwaita)";
      homepage = "https://github.com/PlayRood32/adw-network";
      changelog = "https://github.com/PlayRood32/adw-network/releases/tag/v${version}";
      license = lib.licenses.gpl3Plus;
      platforms = ["x86_64-linux"];
      mainProgram = "adwaita-network";
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
