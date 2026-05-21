# cleanup.nix — periodic Home Manager hygiene.
#
# `home-manager.backupFileExtension = "hm-backup"` (set in lib/mkHost.nix)
# protects pre-existing non-symlink files during activation by renaming
# them to `<name>.hm-backup`. Without periodic cleanup these accumulate
# forever. This timer removes any stale `.hm-backup` weekly (>14 days).
{pkgs, ...}: {
  systemd.user.services.hm-backup-cleanup = {
    Unit = {
      Description = "Remove stale .hm-backup files older than 14 days";
    };
    Service = {
      Type = "oneshot";
      ExecStart = let
        cleanup = pkgs.writeShellScript "hm-backup-cleanup" ''
          set -u
          # Search common HM-managed roots. Limit depth to avoid traversing
          # huge cache trees. Quiet — only emit on actual deletions.
          for root in "$HOME/.config" "$HOME/.local/share" "$HOME"; do
            [ -d "$root" ] || continue
            ${pkgs.findutils}/bin/find "$root" \
              -maxdepth 4 \
              -type f \
              -name '*.hm-backup' \
              -mtime +14 \
              -print -delete 2>/dev/null || true
          done
        '';
      in "${cleanup}";
    };
  };

  systemd.user.timers.hm-backup-cleanup = {
    Unit = {
      Description = "Weekly trigger for HM backup cleanup";
    };
    Timer = {
      OnCalendar = "weekly";
      Persistent = true;
      AccuracySec = "1h";
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };
}
