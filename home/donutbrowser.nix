# donutbrowser.nix — anti-detect Tauri browser + zombie-process reaper.
# Local derivation in pkgs/donutbrowser/ (license: AGPL-3.0). Default
# browser is unchanged — invoke via launcher or `donutbrowser`.
# The reaper user-timer kills idle `donut-proxy proxy-worker` processes —
# upstream donut-proxy never reaps workers on tab close.
{pkgs, ...}: {
  home.packages = [pkgs.donutbrowser];

  # ── donut-proxy reaper ────────────────────────────────────────────────
  # Donut Browser spawns a `donut-proxy proxy-worker` process per profile/tab
  # and never reaps them on tab close. Over a session they accumulate — the
  # audit found 58 instances holding ~1 GiB of RAM and 50+ open localhost
  # listening sockets after 6h uptime.
  #
  # Reaper heuristic: a worker that has lived >30 min but accumulated <10s
  # of CPU time is provably idle (active workers handling proxy traffic
  # accrue CPU at a much higher rate). We use ps's etimes/cputimes columns
  # so the math is in the kernel's bookkeeping, not our /proc parsing.
  #
  # Safe by design: kill -TERM only, never -KILL; donut-proxy handles SIGTERM
  # cleanly and the parent (donutbrowser) respawns workers on demand.
  systemd.user.services.donut-proxy-reaper = {
    Unit = {
      Description = "Reap stale donut-proxy worker processes";
    };
    Service = {
      Type = "oneshot";
      ExecStart = let
        reaper = pkgs.writeShellScript "donut-proxy-reaper" ''
          set -u
          # Tunables
          min_age_sec=1800   # 30 min
          max_cpu_sec=10     # workers accumulating less than this are idle

          # ps fields: pid, elapsed-seconds, cpu-seconds, command-args
          ${pkgs.procps}/bin/ps -eo pid=,etimes=,cputimes=,args= \
            | while read -r pid etimes cputimes args; do
                case "$args" in
                  *donut-proxy\ proxy-worker*) ;;
                  *) continue ;;
                esac
                if [ "$etimes" -gt "$min_age_sec" ] && [ "$cputimes" -lt "$max_cpu_sec" ]; then
                  ${pkgs.coreutils}/bin/echo "reaping donut-proxy pid=$pid etimes=$etimes cputimes=$cputimes"
                  ${pkgs.util-linux}/bin/kill -TERM "$pid" 2>/dev/null || true
                fi
              done
        '';
      in "${reaper}";
    };
  };

  systemd.user.timers.donut-proxy-reaper = {
    Unit = {
      Description = "Periodic donut-proxy reaper trigger";
    };
    Timer = {
      OnBootSec = "10min";
      OnUnitActiveSec = "15min";
      AccuracySec = "1min";
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };
}
