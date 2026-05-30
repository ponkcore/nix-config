# home/firefox/arkenfox.nix — privacy hardening preferences.
#
# Arkenfox-leaning preference set, extracted from the main firefox
# module so an upstream user.js refresh produces a single isolated
# diff rather than churn across the whole module. Source of truth:
# https://github.com/arkenfox/user.js
#
# Returned as a plain attribute set so the firefox profile can splice
# it into `profiles.<name>.settings`. Re-importing this file directly
# makes the merge explicit at the call site.
{config}: {
  # ── Startup ──
  "browser.startup.page" = 3; # Resume previous session
  "browser.startup.homepage" = "about:blank";

  # ── Geography ──
  "browser.search.region" = "RU";
  "browser.search.isUS" = false;
  "browser.search.suggest.enabled" = false;
  "browser.search.suggest.enabled.private" = false;

  # ── Quiet fox ──
  "app.normandy.enabled" = false;
  "app.normandy.api_url" = "";
  "app.shield.optoutstudies.enabled" = false;
  "app.update.auto" = false;
  "browser.discovery.enabled" = false;
  "browser.newtabpage.activity-stream.feeds.telemetry" = false;
  "browser.newtabpage.activity-stream.telemetry" = false;
  "browser.newtabpage.activity-stream.feeds.snippets" = false;
  "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
  "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
  "browser.newtabpage.activity-stream.showSponsored" = false;
  "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
  "browser.newtabpage.pinned" = false;
  "browser.urlbar.suggest.quicksuggest.sponsored" = false;
  "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
  "datareporting.healthreport.service.enabled" = false;
  "datareporting.healthreport.uploadEnabled" = false;
  "datareporting.policy.dataSubmissionEnabled" = false;
  "datareporting.studies.enabled" = false;
  "toolkit.telemetry.enabled" = false;
  "toolkit.telemetry.unified" = false;
  "toolkit.telemetry.archive.enabled" = false;
  "toolkit.telemetry.newProfilePing.enabled" = false;
  "toolkit.telemetry.shutdownPingSender.enabled" = false;
  "toolkit.telemetry.updatePing.enabled" = false;
  "toolkit.telemetry.bhrPing.enabled" = false;
  "toolkit.telemetry.firstShutdownPing.enabled" = false;

  # ── Security ──
  "dom.security.https_only_mode" = true;
  "dom.security.https_only_mode_ever_enabled" = true;
  "security.ssl.treat_unsafe_negotiation_as_broken" = true;
  "security.ssl.require_safe_negotiation" = true;
  "browser.download.useDownloadDir" = false;
  "browser.download.dir" = "${config.xdg.userDirs.download}";
  "browser.download.folderList" = 2;
  "browser.download.always_ask_before_handling_new_types" = true;
  "pdfjs.disabled" = false;

  # ── Fingerprinting ──
  # RFP (resistFingerprinting) is intentionally DISABLED. It standardises
  # JS APIs (canvas, screen size, fonts, timezone, prefers-color-scheme)
  # to a Tor-style baseline. Two reasons we keep it off:
  #   1. It spoofs prefers-color-scheme to "light" for everyone, which
  #      breaks every site's dark-theme adaptation (Google, GitHub …).
  #   2. The threat model it addresses (someone fingerprinting *us* via
  #      JS APIs on a first-party page) is largely covered by uBlock
  #      Origin (cuts the trackers that would do the fingerprinting)
  #      plus tracking protection + Total Cookie Protection below.
  # If the threat model changes (Tor-style anonymity required), flip
  # both flags back to true and apply the FPP overrides via
  # `privacy.fingerprintingProtection.overrides` to keep the dark-theme
  # signal exempt:
  #     "+AllTargets,-CSSPrefersColorScheme"
  "privacy.resistFingerprinting" = false;
  "privacy.resistFingerprinting.letterboxing" = false;

  # ── Privacy: Tracking ──
  "privacy.trackingprotection.enabled" = true;
  "privacy.trackingprotection.socialtracking.enabled" = true;
  "privacy.trackingprotection.cryptomining.enabled" = true;
  "privacy.trackingprotection.fingerprinting.enabled" = true;
  "privacy.annotate_channels.strict_list.enabled" = true;
  "privacy.donottrackheader.enabled" = true;
  "privacy.donottrackheader.value" = 1;
  # Cookie behavior: 5 = Total Cookie Protection with partitioning
  # (allows SSO logins like Google/Gemini while blocking cross-site
  # trackers).
  "network.cookie.cookieBehavior" = 5;
  # Third-party cookies must persist across sessions for SSO (e.g.
  # Google → Gemini) to work.
  "network.cookie.thirdparty.sessionOnly" = false;
  "network.cookie.thirdparty.nonsecureSessionOnly" = false;
  "network.cookie.sameSite.noneRequiresHsts" = true;
  "dom.storage.same_site.lax_by_default" = true;
  "dom.storage.same_site_none_requires_secure" = true;
  "dom.security.https_first_schemeless" = true;

  # ── Session ──
  "browser.sessionstore.privacy_level" = 1;
  "browser.formfill.enable" = false;

  # ── Password manager ──
  # Built-in password manager fully off — passwords live in KeePassXC,
  # auto-fill is delegated to the keepassxc-browser extension via the
  # native-messaging host wired in home/firefox/default.nix.
  # `rememberSignons = false` is the canonical kill-switch for the
  # "Would you like to save this login?" doorhanger; `autofillForms`
  # and the capture/generation knobs are belt-and-braces against
  # firmware bugs that re-enable the doorhanger from a partial pref.
  "signon.rememberSignons" = false;
  "signon.autofillForms" = false;
  "signon.formlessCapture.enabled" = false;
  "signon.generation.enabled" = false;
  "signon.management.page.breach-alerts.enabled" = false;
  "signon.firefoxRelay.feature" = "disabled";

  # ── Cleanup ──
  # Firefox 150 uses a v3 migration system: v1/v2 prefs are consolidated
  # into privacy.sanitize.pending. We must keep v1 and v2 prefs FULLY
  # CONSISTENT to prevent the migration from producing wrong results.
  # Key insight: v2.cookiesAndStorage bundles cookies + sessions +
  # offlineApps. If ANY of those v1 prefs is true, migration might set
  # cookiesAndStorage=true, which would clear ALL of them (including
  # cookies we want to keep).
  "privacy.sanitize.sanitizeOnShutdown" = true;
  # v1 prefs — must be consistent with v2 below
  "privacy.clearOnShutdown.cache" = true;
  "privacy.clearOnShutdown.cookies" = false;
  "privacy.clearOnShutdown.downloads" = true;
  "privacy.clearOnShutdown.formdata" = true;
  "privacy.clearOnShutdown.history" = true;
  # offlineApps MUST be false: it's bundled into cookiesAndStorage in
  # v2, and we need cookiesAndStorage=false to preserve login cookies.
  "privacy.clearOnShutdown.offlineApps" = false;
  "privacy.clearOnShutdown.sessions" = false;
  "privacy.clearOnShutdown.siteSettings" = false;
  "privacy.clearOnShutdown.openWindows" = false;
  # v2 prefs (FF128+) — these are authoritative after migration
  "privacy.clearOnShutdown_v2.cache" = true;
  # cookiesAndStorage = cookies + sessions + offlineApps. Keep false to
  # preserve logins.
  "privacy.clearOnShutdown_v2.cookiesAndStorage" = false;
  # historyFormDataAndDownloads = true matches v1 history=true +
  # formdata=true.
  "privacy.clearOnShutdown_v2.historyFormDataAndDownloads" = true;
  "privacy.clearOnShutdown_v2.browsingHistoryAndDownloads" = true;
  "privacy.clearOnShutdown_v2.formdata" = true;
  # Reset migration flag so Firefox re-migrates from our corrected
  # prefs on every start.
  "privacy.sanitize.clearOnShutdown.hasMigratedToNewPrefs3" = false;

  # ── Misc ──
  "browser.eme.ui.enabled" = true;
  "browser.uitour.enabled" = false;
  "permissions.manager.defaultsUrl" = "";
  "webchannel.allowObjectUrlWhitelist" = "";
  "network.IDN_show_punycode" = true;
  "network.manage-offline-status" = false;
  "browser.display.use_system_colors" = false;
  "extensions.enabledScopes" = 5;
  "extensions.autoDisableScopes" = 15;
  "extensions.postDownloadThirdPartyPrompt" = false;

  # ── Dev ──
  "devtools.debugger.remote-enabled" = false;

  # ── UI preferences ──
  "browser.tabs.closeWindowWithLastTab" = false;
  "browser.tabs.warnOnClose" = false;
  "browser.ctrlTab.recentlyUsedOrder" = true;
  "browser.compactmode.show" = true;
  "browser.uidensity" = 1;
  "browser.theme.dark-private-windows" = true;
  "layout.css.prefers-color-scheme.content-override" = 0;
  "media.videocontrols.picture-in-picture.enabled" = true;
  "media.videocontrols.picture-in-picture.video-toggle.enabled" = true;
  "ui.systemContextMenu.darkTheme" = true;
}
