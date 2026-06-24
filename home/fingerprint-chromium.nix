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
      local name="$1" seed="$2" platform="$3" brand="$4" timezone="$5" lang="$6" acceptLang="$7"
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
        '.profiles[$n] = {
          seed: $s,
          platform: $p,
          brand: $b,
          timezone: $tz,
          lang: $l,
          acceptLang: $al
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
      save_profile "$name" "$seed" "$platform" "Chrome" "UTC" "en-US" "en-US,en"
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
      if ! get_profile "$name" >/dev/null 2>&1; then
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
      local seed platform brand timezone lang acceptLang
      seed=$(    printf '%s\n' "$p" | ${pkgs.jq}/bin/jq -r '.seed')
      platform=$(printf '%s\n' "$p" | ${pkgs.jq}/bin/jq -r '.platform')
      brand=$(   printf '%s\n' "$p" | ${pkgs.jq}/bin/jq -r '.brand')
      timezone=$(printf '%s\n' "$p" | ${pkgs.jq}/bin/jq -r '.timezone')
      lang=$(    printf '%s\n' "$p" | ${pkgs.jq}/bin/jq -r '.lang')
      acceptLang=$(printf '%s\n' "$p" | ${pkgs.jq}/bin/jq -r '.acceptLang')

      local data_dir="$DATA_ROOT/$name"
      mkdir -p "$data_dir"

      if [ -n "''${FINGERPRINT_CHROMIUM_PROXY_ENV_FILE:-}" ]; then
        # shellcheck disable=SC1090
        . "$FINGERPRINT_CHROMIUM_PROXY_ENV_FILE"
      fi

      set -- \
        --user-data-dir="$data_dir" \
        --fingerprint="$seed" \
        --fingerprint-platform="$platform" \
        --fingerprint-brand="$brand" \
        --timezone="$timezone" \
        --lang="$lang" \
        --accept-lang="$acceptLang" \
        --no-first-run \
        --no-default-browser-check \
        --disable-features=Translate \
        --enable-features=DnsOverHttps \
        --doh-url=https://1.1.1.1/dns-query \
        "$@"

      if [ -n "''${FINGERPRINT_CHROMIUM_PROXY_SERVER:-}" ]; then
        set -- --proxy-server="$FINGERPRINT_CHROMIUM_PROXY_SERVER" "$@"
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

  # ── rofi picker: list + create button ────────────────────────────────
  fpRofi = pkgs.writeShellScriptBin "fingerprint-chromium-profiles" ''
    set -eu

    # Use a temp file so rofi results are clean
    choices=$(mktemp)
    trap 'rm -f "$choices"' EXIT

    while true; do
      # Build the menu: "➕ Create profile..." then the profile list
      (
        printf '➕ Create profile...\n'
        ${fpProfile}/bin/fp-profile list
      ) > "$choices"

      selection=$(${pkgs.rofi}/bin/rofi -dmenu -i -p 'fingerprint chromium' -theme palette < "$choices")
      [ -n "$selection" ] || exit 0

      if [ "$selection" = "➕ Create profile..." ]; then
        new_name=$(${fpProfile}/bin/fp-profile create)
        [ -n "$new_name" ] || continue
        exec ${fpProfile}/bin/fp-profile launch "$new_name"
      else
        exec ${fpProfile}/bin/fp-profile launch "$selection"
      fi
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
