# cloakbrowser.nix — CloakBrowser stealth Chromium + profile manager.
#
# CloakBrowser patches Chromium at the C++ source level (58 patches):
# canvas, WebGL, audio, fonts, GPU, screen, WebRTC, network timing,
# automation signals, CDP input behaviour.
#
# Key CloakBrowser flags (C++ patched, not just CLI no-ops):
#   --fingerprint-device-memory   — V8 patch (navigator.deviceMemory)
#   --fingerprint-screen-*        — actually works (Screen DOM C++ patch)
#   --fingerprint-taskbar-height  — spoofs screen.availHeight
#   --fingerprint-storage-quota   — prevents incognito detection
#   --fingerprint-webrtc-ip       — spoofs WebRTC ICE candidates
#   navigator.webdriver = false   — source patch
#   navigator.plugins = 5         — real plugin list
#   window.chrome present         — not undefined
#   TLS fingerprint               — identical to real Chrome
#
# The browser binary is declarative; individual profiles are imperative
# and live in ~/.config/cloakbrowser/profiles.json.
{pkgs, ...}: let
  dataRoot = "\${XDG_DATA_HOME:-$HOME/.local/share}/cloakbrowser";
  profileJson = "\${XDG_CONFIG_HOME:-$HOME/.config}/cloakbrowser/profiles.json";

  # ── cb-profile: imperative profile manager ──────────────────────────
  cbProfile = pkgs.writeShellScriptBin "cb-profile" ''
        set -eu

        PROFILES_FILE="${profileJson}"
        DATA_ROOT="${dataRoot}"
        BROWSER="${pkgs.cloakbrowser}/bin/cloakbrowser"
        ROFI="${pkgs.rofi}/bin/rofi"

        # ── helpers ────────────────────────────────────────────────────────
        load_profiles() {
          mkdir -p "$(dirname "$PROFILES_FILE")"
          if [ ! -f "$PROFILES_FILE" ]; then
            printf '{"profiles":{}}\n' > "$PROFILES_FILE"
          fi
          ${pkgs.jq}/bin/jq -r '.profiles | keys[]' "$PROFILES_FILE" 2>/dev/null || true
        }

        get_profile() {
          ${pkgs.jq}/bin/jq -r --arg n "$1" '.profiles[$n] // empty' "$PROFILES_FILE"
        }

        save_profile() {
          local name="$1" seed="$2" platform="$3" brand="$4" timezone="$5" lang="$6" acceptLang="$7" colorScheme="$8"
          mkdir -p "$(dirname "$PROFILES_FILE")"
          local tmpfile
          tmpfile=$(mktemp)
          ${pkgs.jq}/bin/jq \
            --arg n "$name" \
            --argjson s "$seed" \
            --arg p "$platform" \
            --arg b "$brand" \
            --arg tz "$timezone" \
            --arg l "$lang" \
            --arg al "$acceptLang" \
            --arg cs "$colorScheme" \
            '.profiles[$n] = {
              seed: $s,
              platform: $p,
              brand: $b,
              timezone: $tz,
              lang: $l,
              acceptLang: $al,
              colorScheme: $cs
            }' "$PROFILES_FILE" > "$tmpfile"
          mv "$tmpfile" "$PROFILES_FILE"
        }

        delete_profile() {
          local name="$1"
          local tmpfile
          tmpfile=$(mktemp)
          ${pkgs.jq}/bin/jq --arg n "$name" 'del(.profiles[$n])' "$PROFILES_FILE" > "$tmpfile"
          mv "$tmpfile" "$PROFILES_FILE"
          rm -rf "$DATA_ROOT/$name"
        }

        random_seed() {
          ${pkgs.coreutils}/bin/od -An -N4 -tu4 /dev/urandom | tr -d ' '
        }

        # ── subcommands ────────────────────────────────────────────────────
        cmd_list() {
          load_profiles
        }

        cmd_create() {
          while true; do
            name=$($ROFI -dmenu -i -p 'profile name' -theme palette -mesg "letters, digits, hyphens, underscores")
            [ -n "$name" ] || exit 1
            case "$name" in
              *[!a-zA-Z0-9_-]*)
                $ROFI -e "only a-z, 0-9, -, _, no spaces" -theme palette
                continue
                ;;
              -*|_*)
                $ROFI -e "must start with a letter or digit" -theme palette
                continue
                ;;
            esac
            if [ -n "$(get_profile "$name")" ]; then
              $ROFI -e "profile '$name' already exists" -theme palette
              continue
            fi
            break
          done

          platform=$(printf 'windows\nmacos\nlinux' | $ROFI -dmenu -i -p "platform" -theme palette -mesg "select OS fingerprint type")
          [ -n "$platform" ] || exit 1

          seed=$(random_seed)
          save_profile "$name" "$seed" "$platform" "Chrome" "UTC" "en-US" "en-US,en" "light"
          mkdir -p "$DATA_ROOT/$name"
          printf 'created profile "%s" (seed=%s platform=%s)\n' "$name" "$seed" "$platform" >&2
          printf '%s\n' "$name"
        }

        cmd_delete() {
          local name="$1"
          if [ -z "$name" ]; then
            printf 'usage: cb-profile delete <name>\n' >&2
            exit 64
          fi
          if [ -z "$(get_profile "$name")" ]; then
            printf 'profile "%s" does not exist\n' "$name" >&2
            exit 1
          fi
          delete_profile "$name"
          printf 'deleted profile "%s"\n' "$name" >&2
        }

        cmd_launch() {
          local name="$1"; shift
          if [ -z "$name" ]; then
            printf 'usage: cb-profile launch <name> [chromium-args-or-urls...]\n' >&2
            exit 64
          fi
          local p
          p=$(get_profile "$name")
          if [ -z "$p" ]; then
            printf 'unknown profile: %s\n' "$name" >&2
            exit 64
          fi
          local seed platform brand timezone lang acceptLang colorScheme
          seed=$(    printf '%s\n' "$p" | ${pkgs.jq}/bin/jq -r '.seed')
          platform=$(printf '%s\n' "$p" | ${pkgs.jq}/bin/jq -r '.platform')
          brand=$(   printf '%s\n' "$p" | ${pkgs.jq}/bin/jq -r '.brand')
          timezone=$(printf '%s\n' "$p" | ${pkgs.jq}/bin/jq -r '.timezone')
          lang=$(    printf '%s\n' "$p" | ${pkgs.jq}/bin/jq -r '.lang')
          acceptLang=$(printf '%s\n' "$p" | ${pkgs.jq}/bin/jq -r '.acceptLang')
          colorScheme=$(printf '%s\n' "$p" | ${pkgs.jq}/bin/jq -r '.colorScheme // "light"')

          local data_dir="$DATA_ROOT/$name"
          mkdir -p "$data_dir"

          if [ -n "''${CLOAKBROWSER_PROXY_ENV_FILE:-}" ]; then
            # shellcheck disable=SC1090
            . "$CLOAKBROWSER_PROXY_ENV_FILE"
          fi

          # ── VPN routing strategy ───────────────────────────────────────
          # TUN transparent proxy preferred, SOCKS5 fallback.
          local use_socks=0

          if [ -n "''${CLOAKBROWSER_PROXY_SERVER:-}" ]; then
            use_socks=1
          elif [ -z "''${CLOAKBROWSER_NO_PROXY:-}" ]; then
            if ip link show throne-tun >/dev/null 2>&1; then
              printf 'TUN active (throne-tun) — transparent routing\n' >&2
            else
              local socks_port="''${CLOAKBROWSER_SOCKS_PORT:-2080}"
              if ${pkgs.coreutils}/bin/timeout 1 \
                bash -c 'exec 3<>"/dev/tcp/127.0.0.1/'"$socks_port"'"' 2>/dev/null; then
                export CLOAKBROWSER_PROXY_SERVER="socks5://127.0.0.1:$socks_port"
                use_socks=1
                printf 'TUN inactive — falling back to SOCKS on port %s\n' "$socks_port" >&2
              else
                printf 'WARNING: no VPN detected — traffic will use your real IP\n' >&2
              fi
            fi
          fi

          # ── spoof system-derived fingerprint leaks ───────────────────
          # CloakBrowser's C++ patches make these flags actually work
          # at the engine level — not just CLI no-ops.
          #
          # Spoofed via CloakBrowser native flags:
          #   screen.width/height       — --fingerprint-screen-* (C++ Screen patch)
          #   screen.availHeight        — --fingerprint-taskbar-height (C++ patch)
          #   navigator.deviceMemory    — --fingerprint-device-memory (V8 patch)
          #   hardwareConcurrency       — --fingerprint-hardware-concurrency
          #   WebRTC ICE candidates     — --fingerprint-webrtc-ip=auto
          #   storage quota             — --fingerprint-storage-quota
          #
          # Spoofed via Chromium built-in flags:
          #   prefers-color-scheme      — --blink-settings=preferredColorScheme
          #   prefers-reduced-motion    — --force-prefers-no-reduced-motion
          #   devicePixelRatio          — --force-device-scale-factor

          local blink_scheme
          case "$colorScheme" in
            dark|Dark)  blink_scheme="Dark"  ;;
            light|Light) blink_scheme="Light" ;;
            *)          blink_scheme="Light" ;;
          esac

          # ── screen resolution: seed-derived, platform-appropriate ──────
          # All spoofed widths MUST be >= the real CSS viewport width
          # (1600 on this eDP at scale 1.80).
          local resolutions scr_w scr_h scr_dpr taskbar_h
          case "$platform" in
            windows)
              resolutions="1920 1080 1.0 40
    2560 1440 1.0 40
    3840 2160 1.5 40" ;;
            macos)
              resolutions="1680 1050 2.0 25
    2560 1600 2.0 25" ;;
            linux)
              resolutions="1920 1080 1.0 40
    2560 1440 1.0 40" ;;
            *)
              resolutions="1920 1080 1.0 40" ;;
          esac
          local n_res
          n_res=$(printf '%s\n' "$resolutions" | wc -l)
          local res_idx=$((seed % n_res + 1))
          read -r scr_w scr_h scr_dpr taskbar_h <<EOF
    $(printf '%s\n' "$resolutions" | sed -n "''${res_idx}p")
    EOF

          # ── hardware concurrency: seed-derived ─────────────────────────
          local hw_concurrency_opts="4 8 12 16 6 8 4 12"
          local hw_idx=$((seed % 8 + 1))
          local hw_concurrency
          hw_concurrency=$(printf '%s\n' $hw_concurrency_opts | sed -n "''${hw_idx}p")

          # ── device memory: seed-derived ────────────────────────────────
          # CloakBrowser patches V8 to return this value instead of the
          # hardcoded 8. Common values: 4, 8, 16.
          local dev_mem_opts="4 8 8 16 8 4 8 16"
          local dm_idx=$((seed % 8 + 1))
          local dev_mem
          dev_mem=$(printf '%s\n' $dev_mem_opts | sed -n "''${dm_idx}p")

          printf 'spoof: %sx%s @ %s DPR (taskbar %s), %s cores, %s GB RAM, color=%s\n' \
            "$scr_w" "$scr_h" "$scr_dpr" "$taskbar_h" \
            "$hw_concurrency" "$dev_mem" "$blink_scheme" >&2

          set -- \
            --user-data-dir="$data_dir" \
            --fingerprint="$seed" \
            --fingerprint-platform="$platform" \
            --fingerprint-brand="$brand" \
            --fingerprint-screen-width="$scr_w" \
            --fingerprint-screen-height="$scr_h" \
            --fingerprint-taskbar-height="$taskbar_h" \
            --fingerprint-hardware-concurrency="$hw_concurrency" \
            --fingerprint-device-memory="$dev_mem" \
            --fingerprint-storage-quota=5000 \
            --fingerprint-webrtc-ip=auto \
            --force-device-scale-factor="$scr_dpr" \
            --timezone="$timezone" \
            --lang="$lang" \
            --accept-lang="$acceptLang" \
            --blink-settings="preferredColorScheme=$blink_scheme" \
            --force-prefers-no-reduced-motion \
            --disable-quic \
            --dns-over-https-mode=secure \
            --dns-over-https-templates=https://1.1.1.1/dns-query \
            --no-first-run \
            --no-default-browser-check \
            --disable-features=Translate \
            "$@"

          if [ "$use_socks" -eq 1 ]; then
            set -- \
              --proxy-server="$CLOAKBROWSER_PROXY_SERVER" \
              "$@"
          fi

          # Override GTK_THEME to match the profile's colorScheme.
          # Chromium reads the system GTK theme name from settings.ini
          # and enables dark browser UI if the theme name contains
          # "dark". --blink-settings only controls what web pages see
          # (CSS prefers-color-scheme), NOT the browser chrome. Without
          # this override, the system's Gruvbox-Dark theme leaks into
          # CloakBrowser's UI even for light profiles.
          #
          # PORTAL LEAK FIX: xdg-desktop-portal-gtk reports
          # org.freedesktop.appearance.color-scheme=1 (prefer-dark) to
          # all apps, derived from gtk-theme-name=Gruvbox-Dark in
          # settings.ini. GTK_THEME env var does NOT affect the portal
          # (separate process). Chromium 146 reads the portal and
          # overrides --blink-settings for prefers-color-scheme.
          #
          # Fix: xdg-dbus-proxy filters the session bus — allows
          # org.freedesktop.portal.FileChooser (file dialogs) but
          # blocks org.freedesktop.portal.Settings (color-scheme
          # leak). Previous approach (DBUS_SESSION_BUS_ADDRESS to
          # /dev/null) blocked ALL D-Bus — file upload broke.
          # Proxy and DNS use CLI flags — no D-Bus needed beyond
          # FileChooser. Per-process, does NOT affect other apps.
          case "$colorScheme" in
            dark|Dark)
              export GTK_THEME="Adwaita-dark"
              exec "$BROWSER" "$@"
              ;;
            *)
              export GTK_THEME="Adwaita:light"
              # D-Bus filtering proxy: allows FileChooser (file upload
              # dialogs) but blocks Settings (which leaks color-scheme=dark
              # from xdg-desktop-portal-gtk reading Gruvbox-Dark from
              # settings.ini). Previous approach (DBUS_SESSION_BUS_ADDRESS
              # to /dev/null) blocked ALL D-Bus — file dialogs broke.
              PROXY_SOCKET="''${XDG_RUNTIME_DIR}/cloakbrowser-dbus-$$.sock"
              ${pkgs.xdg-dbus-proxy}/bin/xdg-dbus-proxy \
                "unix:path=''${XDG_RUNTIME_DIR}/bus" \
                "$PROXY_SOCKET" \
                --filter \
                --see=org.freedesktop.portal.Desktop \
                --call=org.freedesktop.portal.Desktop=org.freedesktop.portal.FileChooser.* \
                --call=org.freedesktop.portal.Desktop=org.freedesktop.portal.Request.* \
                --broadcast=org.freedesktop.portal.Desktop=org.freedesktop.portal.Request.* \
                &
              PROXY_PID=$!
              i=0
              while [ $i -lt 20 ]; do
                [ -S "$PROXY_SOCKET" ] && break
                ${pkgs.coreutils}/bin/sleep 0.05
                i=$((i + 1))
              done
              if [ ! -S "$PROXY_SOCKET" ]; then
                printf 'WARNING: dbus-proxy failed — no file dialogs\n' >&2
                export DBUS_SESSION_BUS_ADDRESS="unix:path=/dev/null/cloakbrowser-no-dbus"
              else
                export DBUS_SESSION_BUS_ADDRESS="unix:path=$PROXY_SOCKET"
              fi
              trap 'kill "$PROXY_PID" 2>/dev/null || true; rm -f "$PROXY_SOCKET" 2>/dev/null || true' EXIT
              "$BROWSER" "$@"
              ;;
          esac
        }

        cmd_validate() {
          if [ "$#" -ne 1 ]; then
            printf 'usage: cb-profile validate <profile>\n' >&2
            cmd_list >&2
            exit 64
          fi
          exec "$0" launch "$1" \
            'https://abrahamjuliot.github.io/creepjs/' \
            'https://browserscan.net/' \
            'https://pixelscan.net/fingerprint-check' \
            'https://browserleaks.com/webrtc' \
            'https://browserleaks.com/tls' \
            'https://bot.sannysoft.com/' \
            'https://demo.fingerprint.com/playground'
        }

        # ── dispatch ───────────────────────────────────────────────────────
        case "''${1:-}" in
          list)     shift; cmd_list "$@" ;;
          create)   shift; cmd_create "$@" ;;
          delete)   shift; cmd_delete "$@" ;;
          launch)   shift; cmd_launch "$@" ;;
          validate) shift; cmd_validate "$@" ;;
          *)
            printf 'usage: cb-profile {list|create|delete|launch|validate} [args...]\n' >&2
            exit 64
            ;;
        esac
  '';

  # ── rofi picker: list + create + delete ─────────────────────────────
  cbRofi = pkgs.writeShellScriptBin "cloakbrowser-profiles" ''
    set -eu

    choices=$(mktemp)
    trap 'rm -f "$choices"' EXIT

    while true; do
      (
        printf '➕ Create profile...\n'
        printf '🗑 Delete profile...\n'
        ${cbProfile}/bin/cb-profile list
      ) > "$choices"

      selection=$(${pkgs.rofi}/bin/rofi -dmenu -i -p 'cloakbrowser' -theme palette < "$choices")
      [ -n "$selection" ] || exit 0

      case "$selection" in
        "➕ Create profile...")
          new_name=$(${cbProfile}/bin/cb-profile create)
          [ -n "$new_name" ] || continue
          exec ${cbProfile}/bin/cb-profile launch "$new_name"
          ;;
        "🗑 Delete profile...")
          del_choices=$(mktemp)
          ${cbProfile}/bin/cb-profile list > "$del_choices"
          if [ ! -s "$del_choices" ]; then
            ${pkgs.rofi}/bin/rofi -e "no profiles to delete" -theme palette
            rm -f "$del_choices"
            continue
          fi
          to_delete=$(${pkgs.rofi}/bin/rofi -dmenu -i -p 'delete' -theme palette < "$del_choices")
          rm -f "$del_choices"
          [ -n "$to_delete" ] || continue
          ${cbProfile}/bin/cb-profile delete "$to_delete"
          ${pkgs.rofi}/bin/rofi -e "deleted: $to_delete" -theme palette
          continue
          ;;
        *)
          exec ${cbProfile}/bin/cb-profile launch "$selection"
          ;;
      esac
    done
  '';

  # ── alias for shell convenience ─────────────────────────────────────
  cbAlias = pkgs.writeShellScriptBin "cb" ''
    exec ${cbProfile}/bin/cb-profile "$@"
  '';
in {
  home.packages = [
    pkgs.cloakbrowser
    cbProfile
    cbRofi
    cbAlias
  ];

  xdg.desktopEntries.cloakbrowser = {
    name = "CloakBrowser";
    genericName = "Stealth anti-detect browser profile picker";
    comment = "Pick, create, or delete a CloakBrowser profile";
    exec = "${cbRofi}/bin/cloakbrowser-profiles";
    icon = "cloakbrowser";
    terminal = false;
    categories = ["Network" "WebBrowser"];
    startupNotify = false;
    settings = {
      Keywords = "browser;chromium;cloak;stealth;antidetect;fingerprint;profile;rofi;";
    };
  };
}
