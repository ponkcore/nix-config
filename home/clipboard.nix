# clipboard.nix — cliphist clipboard manager.
# Persists clipboard history (max 100 dedup entries) so it survives the
# source app closing. Picker bound to SUPER+C in
# home/desktop/sessions/hyprland/session.nix.
_: {
  services.cliphist = {
    enable = true;
    extraOptions = ["-max-dedup-cache-size" "100"];
  };
}
