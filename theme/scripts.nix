# scripts.nix — universal, session-agnostic helper scripts.
#
# Only scripts that hold across any compositor and any host live here.
# Session-specific scripts (toggles that drive `hyprctl`) live in
# home/desktop/sessions/<name>/scripts.nix; host-specific scripts (Lecoo
# EC charge mode) live in hosts/<name>/home/scripts.nix.
#
# Adding a new universal script: define here, expose via _module.args
# so consumer modules can embed the absolute /nix/store path without
# re-deriving it.
{pkgs, ...}: let
  # ── Notification (mako) ─────────────────────────────────────────────
  notification-toggle = pkgs.writeShellScriptBin "notification-toggle" ''
    current=$(${pkgs.mako}/bin/makoctl mode 2>/dev/null || echo "default")
    if [ "$current" = "do-not-disturb" ]; then
      ${pkgs.mako}/bin/makoctl mode default
      printf '{"text":"ON","class":"default","tooltip":"Notifications: ON"}\n'
    else
      ${pkgs.mako}/bin/makoctl mode -a do-not-disturb
      printf '{"text":"DND","class":"dnd","tooltip":"Notifications: OFF (DND)"}\n'
    fi
  '';

  notification-status = pkgs.writeShellScriptBin "notification-status" ''
    current=$(${pkgs.mako}/bin/makoctl mode 2>/dev/null || echo "default")
    if [ "$current" = "do-not-disturb" ]; then
      printf '{"text":"DND","class":"dnd","tooltip":"Notifications: OFF (DND)"}\n'
    else
      printf '{"text":"ON","class":"default","tooltip":"Notifications: ON"}\n'
    fi
  '';

  # ── NixOS update check ─────────────────────────────────────────────
  # Compares locked rev against latest nixpkgs remote.
  # Caches result for 1 hour to avoid expensive repeated network calls.
  update-check = pkgs.writeShellScriptBin "update-check" ''
    cache_file="/tmp/nixos-update-check"
    cache_ttl=3600

    if [ -f "$cache_file" ]; then
        cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
        if [ "$cache_age" -lt "$cache_ttl" ]; then
            cat "$cache_file"
            exit 0
        fi
    fi

    locked=$(${pkgs.nix}/bin/nix flake metadata /etc/nixos --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.locks.nodes.nixpkgs.locked.rev' 2>/dev/null || echo "")
    latest=$(${pkgs.nix}/bin/nix flake metadata github:NixOS/nixpkgs/nixos-26.05 --json 2>/dev/null | ${pkgs.jq}/bin/jq -r '.revision' 2>/dev/null || echo "")

    if [ -n "$locked" ] && [ -n "$latest" ] && [ "$locked" != "$latest" ]; then
        result='{"text":"upd","class":"has-updates","tooltip":"NixOS update available"}'
    else
        result='{"text":"","class":"updated","tooltip":"System is up to date"}'
    fi

    echo "$result" > "$cache_file"
    echo "$result"
  '';
in {
  # Expose universal scripts as function args to other theme modules.
  _module.args = {
    inherit
      notification-toggle
      notification-status
      update-check
      ;
  };

  home.packages = [
    notification-toggle
    notification-status
    update-check
  ];
}
