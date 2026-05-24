# orbit — WiFi/Bluetooth/VPN/Ethernet manager for Wayland
# (Rust + GTK4 + GTK Layer Shell, glassmorphism UI).
#
# Upstream: https://github.com/LifeOfATitan/orbit
#
# Pinned to a specific commit (no upstream tag yet). Build is plain
# `rustPlatform.buildRustPackage` against the upstream Cargo.lock.
# Runtime depends on networkmanager (libnm/nmcli/dbus interface),
# bluez (D-Bus interface for the bluetooth tab), and openssl
# (reqwest pulls it in for the captive-portal / public-IP probes).
#
# The CLI exposes `orbit toggle`, `orbit show`, `orbit hide`, etc.,
# so a Waybar `on-click` binding wires it to a tray click without
# any kill-and-respawn workaround. Daemon-mode is stood up by a
# systemd user unit (see `home/orbit.nix`).
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  wrapGAppsHook4,
  glib,
  gtk4,
  gtk4-layer-shell,
  gdk-pixbuf,
  cairo,
  pango,
  graphene,
  harfbuzz,
  openssl,
  dbus,
  # Runtime-only tools the daemon shells out to.
  networkmanager,
  bluez,
}:
rustPlatform.buildRustPackage rec {
  pname = "orbit";
  version = "2.4.13-unstable-2026-05-24";

  src = fetchFromGitHub {
    owner = "LifeOfATitan";
    repo = "orbit";
    rev = "eb772615558b61cda81861a3fbac49f7e37dc1f8";
    hash = "sha256-18xO4DcU9u3FFem19muJ0R8K7V/mzOp68EE5ASQ3swg=";
  };

  cargoLock = {
    lockFile = src + "/Cargo.lock";
  };

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook4
  ];

  buildInputs = [
    glib
    gtk4
    gtk4-layer-shell
    gdk-pixbuf
    cairo
    pango
    graphene
    harfbuzz
    openssl
    dbus
  ];

  # GApps wrapper handles GIO_MODULE_DIR and XDG_DATA_DIRS for
  # GSchemas. Extend PATH so `orbit` can shell out to nmcli /
  # bluetoothctl (it does both for the Wi-Fi and Bluetooth tabs).
  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : ${lib.makeBinPath [networkmanager bluez]}
    )
  '';

  # `cargoLock.lockFile = src + "/Cargo.lock"` works without a
  # postPatch shim (unlike adw-network), since here Cargo.lock is
  # committed to the repository.

  meta = {
    description = "WiFi/Bluetooth/VPN/Ethernet manager for Wayland (Rust + GTK4 + Layer Shell)";
    homepage = "https://github.com/LifeOfATitan/orbit";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "orbit";
  };
}
