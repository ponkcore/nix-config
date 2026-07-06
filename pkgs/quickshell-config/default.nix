# quickshell-config/default.nix — matteogini's quickshell shell adapted for NixOS.
#
# Derivation that copies all QML files and scripts into the Nix store,
# then patches hardcoded paths and binary names to match our system:
#
# Path replacements:
#   /home/matteo/.config/quickshell/ → $out/
#   /home/matteo/.config/hypr        → /etc/nixos (config editor shortcut)
#   /home/matteo/.config/ghostty     → HM-managed path
#   /home/matteo/.config/fish        → HM-managed path
#   /home/matteo/.local/bin/battery_mode.sh → our eco-toggle
#
# Binary replacements:
#   zeditor     → ghostty -e nvim (config editor)
#   pavucontrol → pwvucontrol
#   blueberry   → blueman-manager
#   checkupdates → our update-check script (removed, handled differently)
#
# Hardware replacements:
#   BAT1 → BAT0, ACAD → ADP1
#
# ASUS-specific (removed/disabled):
#   supergfxctl (GPU switching — no dual-GPU)
#   asusctl (keyboard LEDs, battery charge limit — not available on AMD)
#   ryzenadj / setwatt (CPU TDP — we use our eco-toggle instead)
{
  pkgs,
  update-check,
  ultra-economy-toggle ? null,
  ...
}: let
  # Helper to create a config-editor launcher
  configEditor = pkgs.writeShellScriptBin "qs-config-edit" ''
    dir="''${1:-/etc/nixos}"
    exec ${pkgs.ghostty}/bin/ghostty --class=com.mitchellh.ghostty-config -e fish -c "cd '$dir' && nvim"
  '';

  # Battery mode toggle: use our ultra-economy-toggle if available,
  # otherwise no-op.
  batteryModeBin =
    if ultra-economy-toggle != null
    then "${ultra-economy-toggle}/bin/ultra-economy-toggle"
    else "${pkgs.coreutils}/bin/true";
in
  pkgs.stdenv.mkDerivation {
    pname = "quickshell-config";
    version = "0.1.0";

    src = ./.;

    buildInputs = [pkgs.python3];

    installPhase = ''
      runHook preInstall

      mkdir -p $out

      # Install QML files
      cp shell.qml $out/
      cp AppLauncher.qml $out/
      cp BluetoothMenu.qml $out/
      cp ClipboardManager.qml $out/
      cp PowerMenu.qml $out/
      cp ThemeSwitcher.qml $out/
      cp WifiMenu.qml $out/

      # Install scripts
      cp count_tiled.sh $out/
      cp get_apps.py $out/
      cp launch_app.sh $out/

      # Make scripts executable
      chmod +x $out/count_tiled.sh $out/launch_app.sh

      runHook postInstall
    '';

    postFixup = ''
      # Replace hardcoded quickshell config paths
      substituteInPlace $out/shell.qml \
        --replace "/home/matteo/.config/quickshell/count_tiled.sh" "$out/count_tiled.sh" \
        --replace "/home/matteo/.config/quickshell" "/etc/nixos" \
        --replace "/home/matteo/.local/bin/battery_mode.sh" "${batteryModeBin}" \
        --replace "/home/matteo/.config/hypr/modules/look_and_feel.conf" "/etc/nixos/hosts/lecoo/default.nix" \
        --replace "/home/matteo/.config/hypr" "/etc/nixos" \
        --replace "/home/matteo/.config/waybar/" "/etc/nixos/theme/waybar/" \
        --replace "/home/matteo/.config/ghostty" "$HOME/.config/ghostty" \
        --replace "/home/matteo/.config/fish" "$HOME/.config/fish" \
        --replace "/home/matteo/.config/fastfetch" "$HOME/.config/fastfetch" \
        --replace "/home/matteo/.config/tofi/" "/etc/nixos/" \
        --replace "/home/matteo/.config/kitty" "$HOME/.config/ghostty" \
        --replace "/home/matteo/.config/foot" "$HOME/.config/ghostty"

      # Replace binaries
      substituteInPlace $out/shell.qml \
        --replace "pavucontrol" "pwvucontrol" \
        --replace "blueberry" "blueman-manager" \
        --replace "\"zeditor\"" "\"${configEditor}/bin/qs-config-edit\""

      # Fix zeditor calls with path args (zeditor /path → qs-config-edit /path)
      substituteInPlace $out/shell.qml \
        --replace '"qs-config-edit", "/etc/nixos"' '"qs-config-edit", "/etc/nixos"' \
        --replace '"qs-config-edit", "/etc/nixos/theme/waybar/"' '"qs-config-edit", "/etc/nixos/theme/waybar/"' \
        --replace '"qs-config-edit", "/etc/nixos/"' '"qs-config-edit", "/etc/nixos/"' \
        --replace '"qs-config-edit", "$HOME/.config/ghostty"' '"qs-config-edit", "$HOME/.config/ghostty"' \
        --replace '"qs-config-edit", "$HOME/.config/fish"' '"qs-config-edit", "$HOME/.config/fish"' \
        --replace '"qs-config-edit", "$HOME/.config/fastfetch"' '"qs-config-edit", "$HOME/.config/fastfetch"'

      # Fix hardware paths
      substituteInPlace $out/shell.qml \
        --replace "BAT1" "BAT0" \
        --replace "ACAD" "ADP1"

      # Replace checkupdates with our update-check (simpler: just count
      # non-empty output, avoid nested quotes that break QML parsing)
      substituteInPlace $out/shell.qml \
        --replace "checkupdates 2>/dev/null | wc -l" "${update-check}/bin/update-check 2>/dev/null | grep -c 'upd' || echo 0"

      # Fix AppLauncher paths
      substituteInPlace $out/AppLauncher.qml \
        --replace "/home/matteo/.config/quickshell/get_apps.py" "$out/get_apps.py" \
        --replace "/home/matteo/.config/quickshell/launch_app.sh" "$out/launch_app.sh"

      # Fix launch_app.sh log path
      substituteInPlace $out/launch_app.sh \
        --replace "/tmp/quickshell_launch.log" "/tmp/quickshell_launch.log"

      # Fix ThemeSwitcher paths
      substituteInPlace $out/ThemeSwitcher.qml \
        --replace "/home/matteo/.config/hypr/scripts/switch_theme.sh" "${pkgs.coreutils}/bin/true"

      # Remove ASUS-specific Process blocks by replacing with no-ops
      # supergfxctl, asusctl, ryzenadj, setwatt
      substituteInPlace $out/shell.qml \
        --replace "supergfxctl" "echo" \
        --replace "asusctl" "echo" \
        --replace "ryzenadj" "echo" \
        --replace "setwatt" "echo"
    '';

    meta = with pkgs.lib; {
      description = "Quickshell config adapted from matteogini/dotfiles";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  }
