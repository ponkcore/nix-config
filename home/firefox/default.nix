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

  # Firefox extensions from NUR (rycee's firefox-addons)
  extensions = with pkgs.nur.repos.rycee.firefox-addons; [
    ublock-origin
    sidebery
    vimium-c
  ];
in {
  programs.firefox = {
    enable = true;

    profiles.default = {
      id = 0;
      isDefault = true;

      extensions.packages = extensions;

      settings = arkenfox;

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
