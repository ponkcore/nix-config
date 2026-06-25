# fingerprint-chromium.nix — anti-detect Chromium spike package + launcher.
# The browser binary is declarative; individual profiles are imperative and
# live in ~/.config/fingerprint-chromium/profiles.json so they can be
# created/deleted without rebuilding.
{pkgs, ...}: let
  dataRoot = "\${XDG_DATA_HOME:-$HOME/.local/share}/fingerprint-chromium";
  profileJson = "\${XDG_CONFIG_HOME:-$HOME/.config}/fingerprint-chromium/profiles.json";

  # ── fp-profile: imperative profile manager ──────────────────────────
  fpProfile = pkgs.writeShellScriptBin "fp-profile" ''
        set -eu

        PROFILES_FILE="${profileJson}"
        DATA_ROOT="${dataRoot}"
        BROWSER="${pkgs.fingerprint-chromium}/bin/fingerprint-chromium"
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
            printf 'usage: fp-profile delete <name>\n' >&2
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
            printf 'usage: fp-profile launch <name> [chromium-args-or-urls...]\n' >&2
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
          # colorScheme: default to "light" for profiles created before this
          # field existed.  "light" breaks correlation with the real system
          # (which is dark) — better for anti-detect.
          colorScheme=$(printf '%s\n' "$p" | ${pkgs.jq}/bin/jq -r '.colorScheme // "light"')

          local data_dir="$DATA_ROOT/$name"
          mkdir -p "$data_dir"

          # Enable DNS-over-HTTPS via Local State file.
          # --doh-url flag doesn't work in ungoogled-chromium, but the
          # Local State JSON file is read on every launch and controls
          # DoH settings. "secure" mode = DoH only, no system DNS fallback.
          local state_file="$data_dir/Local State"
          if [ -f "$state_file" ]; then
            ${pkgs.jq}/bin/jq '.dns_over_https = {mode: "secure", templates: "https://1.1.1.1/dns-query"}' \
              "$state_file" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
          else
            printf '{"dns_over_https":{"mode":"secure","templates":"https://1.1.1.1/dns-query"}}\n' \
              > "$state_file"
          fi

          if [ -n "''${FINGERPRINT_CHROMIUM_PROXY_ENV_FILE:-}" ]; then
            # shellcheck disable=SC1090
            . "$FINGERPRINT_CHROMIUM_PROXY_ENV_FILE"
          fi

          # ── VPN routing strategy ───────────────────────────────────────
          # Throne provides two routing modes:
          #
          # 1. TUN transparent proxy (preferred): sing-box creates nftables
          #    rules (table inet sing-box) that redirect TCP to a local
          #    tproxy port and fwmark-mark UDP for table 2022 routing.
          #    The browser is unaware of the VPN — no proxy fingerprint,
          #    QUIC works natively, WebRTC sees a normal connection.
          #
          # 2. SOCKS5 fallback (127.0.0.1:2080): when TUN is inactive,
          #    we fall back to explicit --proxy-server.  This makes the
          #    browser proxy-aware (worse for anti-detect) and requires
          #    --disable-quic (SOCKS5 does not tunnel UDP).
          #
          # Explicit overrides:
          #   FINGERPRINT_CHROMIUM_PROXY_SERVER — force a specific proxy
          #   FINGERPRINT_CHROMIUM_NO_PROXY=1   — connect directly (dangerous)
          #   FINGERPRINT_CHROMIUM_SOCKS_PORT   — non-default SOCKS port

          local use_socks=0

          if [ -n "''${FINGERPRINT_CHROMIUM_PROXY_SERVER:-}" ]; then
            # Explicit proxy override — respect it.
            use_socks=1
          elif [ -z "''${FINGERPRINT_CHROMIUM_NO_PROXY:-}" ]; then
            # Auto-detect: prefer TUN, fall back to SOCKS.
            if ip link show throne-tun >/dev/null 2>&1; then
              printf 'TUN active (throne-tun) — transparent routing\n' >&2
            else
              local socks_port="''${FINGERPRINT_CHROMIUM_SOCKS_PORT:-2080}"
              if ${pkgs.coreutils}/bin/timeout 1 \
                bash -c 'exec 3<>"/dev/tcp/127.0.0.1/'"$socks_port"'"' 2>/dev/null; then
                export FINGERPRINT_CHROMIUM_PROXY_SERVER="socks5://127.0.0.1:$socks_port"
                use_socks=1
                printf 'TUN inactive — falling back to SOCKS on port %s\n' "$socks_port" >&2
              else
                printf 'WARNING: no VPN detected (no throne-tun, no SOCKS on %s) — traffic will use your real IP\n' "$socks_port" >&2
              fi
            fi
          fi

          # ── spoof system-derived fingerprint leaks ───────────────────
          # fingerprint-chromium spoofs Canvas, WebGL, Audio, fonts,
          # WebRTC, UA/platform, timezone, and languages via --fingerprint.
          # But it does NOT spoof several system-derived properties that
          # leak the real machine identity.  We close those gaps with a
          # combination of fingerprint-chromium's own flags, Chromium
          # built-in flags, and blink-settings.
          #
          # What we spoof (and how):
          #   preferredColorScheme   — --blink-settings (real blink::Settings)
          #   preferredReducedMotion — --force-prefers-no-reduced-motion
          #   screen.width/height    — --fingerprint-screen-width/height
          #   devicePixelRatio       — --fingerprint-device-scale-factor
          #   hardwareConcurrency    — --fingerprint-hardware-concurrency
          #
          # What we CANNOT spoof (no flag, requires source patching):
          #   navigator.deviceMemory — hardcoded in V8, capped at 8
          #   WebGL unmasked renderer — fingerprint-chromium spoof is
          #     incomplete; real GPU (AMD Radeon 780M) leaks through
          #     WEBGL_debug_renderer_info on some test sites
          #
          # Usability: fingerprint-chromium's screen flags change JS-visible
          # values without affecting actual rendering.  The browser renders
          # at the real resolution; only JS fingerprinting sees spoofed
          # values.  Site layouts are unaffected.

          local blink_scheme
          case "$colorScheme" in
            dark|Dark)  blink_scheme="Dark"  ;;
            light|Light) blink_scheme="Light" ;;
            *)          blink_scheme="Light" ;;
          esac

          # ── screen resolution: seed-derived, platform-appropriate ──────
          local resolutions scr_w scr_h scr_dpr
          # ── screen resolution: seed-derived, platform-appropriate ──────
          # All spoofed widths MUST be >= the real CSS viewport width
          # (1600 on this eDP at scale 1.80).  If screen.width <
          # window.innerWidth, fingerprinting scripts detect the mismatch.
          local resolutions scr_w scr_h scr_dpr
          case "$platform" in
            windows)
              resolutions="1920 1080 1.0
    2560 1440 1.0
    3840 2160 1.5" ;;
            macos)
              resolutions="1680 1050 2.0
    2560 1600 2.0" ;;
            linux)
              resolutions="1920 1080 1.0
    2560 1440 1.0" ;;
            *)
              resolutions="1920 1080 1.0" ;;
          esac
          local n_res
          n_res=$(printf '%s\n' "$resolutions" | wc -l)
          local res_idx=$((seed % n_res + 1))
          read -r scr_w scr_h scr_dpr <<EOF
    $(printf '%s\n' "$resolutions" | sed -n "''${res_idx}p")
    EOF

          # ── hardware concurrency: seed-derived ─────────────────────────
          # Common CPU core counts.  Avoid 30 (real core count on this
          # machine) to break correlation.
          local hw_concurrency_opts="4 8 12 16 6 8 4 12"
          local hw_idx=$((seed % 8 + 1))
          local hw_concurrency
          hw_concurrency=$(printf '%s\n' $hw_concurrency_opts | sed -n "''${hw_idx}p")

          printf 'spoof: %sx%s @ %s DPR, %s cores, color=%s, motion=no-preference\n' \
            "$scr_w" "$scr_h" "$scr_dpr" "$hw_concurrency" "$blink_scheme" >&2

          set -- \
            --user-data-dir="$data_dir" \
            --fingerprint="$seed" \
            --fingerprint-platform="$platform" \
            --fingerprint-brand="$brand" \
            --fingerprint-screen-width="$scr_w" \
            --fingerprint-screen-height="$scr_h" \
            --fingerprint-device-scale-factor="$scr_dpr" \
            --fingerprint-hardware-concurrency="$hw_concurrency" \
            --timezone="$timezone" \
            --lang="$lang" \
            --accept-lang="$acceptLang" \
            --blink-settings="preferredColorScheme=$blink_scheme" \
            --force-prefers-no-reduced-motion \
            --disable-quic \
            --no-first-run \
            --no-default-browser-check \
            --disable-features=Translate \
            "$@"

          if [ "$use_socks" -eq 1 ]; then
            set -- \
              --proxy-server="$FINGERPRINT_CHROMIUM_PROXY_SERVER" \
              "$@"
          fi

          exec "$BROWSER" "$@"
        }

        cmd_validate() {
          if [ "$#" -ne 1 ]; then
            printf 'usage: fp-profile validate <profile>\n' >&2
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
            printf 'usage: fp-profile {list|create|delete|launch|validate} [args...]\n' >&2
            exit 64
            ;;
        esac
  '';

  # ── rofi picker: list + create + delete ─────────────────────────────
  fpRofi = pkgs.writeShellScriptBin "fingerprint-chromium-profiles" ''
    set -eu

    choices=$(mktemp)
    trap 'rm -f "$choices"' EXIT

    while true; do
      # Build the menu: actions first, then profiles
      (
        printf '➕ Create profile...\n'
        printf '🗑 Delete profile...\n'
        ${fpProfile}/bin/fp-profile list
      ) > "$choices"

      selection=$(${pkgs.rofi}/bin/rofi -dmenu -i -p 'fingerprint chromium' -theme palette < "$choices")
      [ -n "$selection" ] || exit 0

      case "$selection" in
        "➕ Create profile...")
          new_name=$(${fpProfile}/bin/fp-profile create)
          [ -n "$new_name" ] || continue
          exec ${fpProfile}/bin/fp-profile launch "$new_name"
          ;;
        "🗑 Delete profile...")
          del_choices=$(mktemp)
          ${fpProfile}/bin/fp-profile list > "$del_choices"
          if [ ! -s "$del_choices" ]; then
            ${pkgs.rofi}/bin/rofi -e "no profiles to delete" -theme palette
            rm -f "$del_choices"
            continue
          fi
          to_delete=$(${pkgs.rofi}/bin/rofi -dmenu -i -p 'delete' -theme palette < "$del_choices")
          rm -f "$del_choices"
          [ -n "$to_delete" ] || continue
          ${fpProfile}/bin/fp-profile delete "$to_delete"
          ${pkgs.rofi}/bin/rofi -e "deleted: $to_delete" -theme palette
          continue
          ;;
        *)
          exec ${fpProfile}/bin/fp-profile launch "$selection"
          ;;
      esac
    done
  '';

  # ── alias for shell convenience ─────────────────────────────────────
  fpAlias = pkgs.writeShellScriptBin "fp" ''
    exec ${fpProfile}/bin/fp-profile "$@"
  '';
in {
  home.packages = [
    pkgs.fingerprint-chromium
    fpProfile
    fpRofi
    fpAlias
  ];

  xdg.desktopEntries.fingerprint-chromium = {
    name = "Fingerprint Chromium";
    genericName = "Anti-detect browser profile picker";
    comment = "Pick, create, or delete a fingerprint-chromium profile";
    exec = "${fpRofi}/bin/fingerprint-chromium-profiles";
    icon = "fingerprint-chromium";
    terminal = false;
    categories = ["Network" "WebBrowser"];
    startupNotify = false;
    settings = {
      Keywords = "browser;chromium;fingerprint;antidetect;profile;rofi;";
    };
  };
}
