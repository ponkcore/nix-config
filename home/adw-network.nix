# adw-network.nix — GNOME-inspired NetworkManager frontend.
#
# Pure GTK4 / libadwaita panel that talks to NetworkManager over D-Bus.
# Replaces nm-applet / nm-connection-editor for graphical Wi-Fi /
# hotspot / profile management. Mirror of the adw-bluetooth pattern.
#
# Pulled from our local pkgs overlay (see pkgs/adw-network) — the
# upstream is not in nixpkgs as of Feb 2026.
#
# `xdg.configFile` declaratively pins the module-layout settings.
# Without this the app's first-run heuristic in window.rs hides the
# Wi-Fi tab whenever an Ethernet interface is *present* (regardless
# of state); on lecoo eno1 is always visible to NM, so we end up with
# only Ethernet/Profiles tabs by default. Pinning customized=true and
# show_wifi_module=true gives a stable Wi-Fi-first layout with text
# labels (icons-only mode hides what the tabs even are).
{pkgs, ...}: {
  home.packages = [pkgs.adw-network];

  xdg.configFile."adw-network/settings.json".text = builtins.toJSON {
    color_scheme = "system";
    auto_scan = true;
    expand_connected_details = false;
    icons_only_navigation = false;
    # Enum values are kebab-cased on the Rust side (serde rename_all);
    # passing the variant name verbatim makes the parser fall back to
    # all defaults silently. See lessons/0003-… for the analogous
    # serde-format trap.
    hotspot_password_storage = "keyring";
    hotspot_quota_reset_policy = "never";
    plain_json_debug_opt_in = false;
    module_layout_customized = true;
    show_wifi_module = true;
    show_ethernet_module = true;
    show_hotspot_module = false;
    show_devices_module = false;
    show_profiles_module = true;
    module_order = ["Wi-Fi" "Ethernet" "Hotspot" "Devices" "Profiles"];
  };
}
