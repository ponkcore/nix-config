# home/firefox/default.nix — primary browser.
#
# Profile shell only: extension list, profile id, and the wiring that
# splices in ./arkenfox.nix prefs. Privacy hardening prefs live in
# their own file so an upstream user.js refresh produces a single
# isolated diff rather than churn across this module.
#
# Extensions sourced from NUR (Nix User Repository, rycee branch) so
# no MITM-prone extension-store fetching: uBlock + Sidebery + Vimium-C.
{
  config,
  pkgs,
  ...
}: let
  arkenfox = import ./arkenfox.nix {inherit config;};

  # Firefox extensions from NUR (rycee's firefox-addons).
  # Sidebery removed in favour of Firefox 136+ native vertical tabs
  # (about:preferences → Tabs → Tab orientation → Vertical).
  # keepassxc-browser pairs with the keepassxc native-messaging host
  # wired below — extension talks to the running KeePassXC over a
  # local socket, no cloud round-trip.
  extensions = with pkgs.nur.repos.rycee.firefox-addons; [
    ublock-origin
    vimium-c
    keepassxc-browser
  ];
in {
  programs.firefox = {
    enable = true;

    # Native-messaging hosts. Firefox-wrapped from nixpkgs only scans
    # the wrapper's own lib/mozilla/native-messaging-hosts/ — manifests
    # under /etc/profiles/.../lib/mozilla/... are invisible to it. This
    # option splices the KeePassXC manifest into the wrapper, so the
    # keepassxc-browser extension can reach the running keepassxc
    # process. Pair with `Browser.Enabled = true` in keepassxc.ini
    # (toggle in Settings → Browser Integration on existing hosts;
    # the seed in home/keepassxc.nix sets it for fresh hosts).
    nativeMessagingHosts = [pkgs.keepassxc];

    profiles.default = {
      id = 0;
      isDefault = true;

      extensions.packages = extensions;

      settings =
        arkenfox
        // {
          # ── VA-API hardware video decode ───────────────────────────
          # Offloads H.264/H.265/AV1 decode from CPU to the VCN block
          # on Radeon 780M, saving 1-3W during video playback.
          # Requires MOZ_DISABLE_RDD_SANDBOX=1 (set in session env) and
          # LIBVA_DRIVER_NAME=radeonsi (Mesa VA-API driver).
          # Source: research 2026-06-27-unsolved-and-battery-deep-dive §4 P1
          "media.hardware-video-decoding.enabled" = true;
          "media.ffmpeg.vaapi.enabled" = true;
          "media.rdd-ffmpeg.enabled" = true;
          "media.av1.enabled" = true;
          "gfx.webrender.all" = true;
          # Reduce session store disk writes (15s → 60s default)
          "browser.sessionstore.interval" = 60000;
        };

      # Arkenfox-style extra user.js preferences. Only settings that
      # cannot be expressed via the typed `settings` attribute (e.g.
      # JSON-typed values) live here.
      extraConfig = ''
        // Force sanitize.pending to NOT clear cookiesAndStorage on shutdown
        // This overrides any stale migration state in prefs.js
        user_pref("privacy.sanitize.pending", '[{"id":"shutdown","itemsToClear":["cache","formdata","browsingHistoryAndDownloads"],"options":{}},{"id":"newtab-container","itemsToClear":[],"options":{}}]');
      '';
    };
  };
}
