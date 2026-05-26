# event-logger.nix — diagnostic logger for Hyprland floating-window
# drift on this multi-monitor mixed-scale (eDP-1 @2 + HDMI-A-1 @1)
# setup. Captures the full .socket2.sock event stream plus a periodic
# floating-window snapshot, so the post-drift log can be correlated
# event-by-event with when window `at` coordinates fall out of their
# monitor's logical rectangle.
#
# Not autostart. Start manually before walking away from the box:
#   systemctl --user start talos-hypr-eventlog
# Stop when done:
#   systemctl --user stop talos-hypr-eventlog
# Log file: ~/.local/share/talos/hypr-events.log
{
  config,
  pkgs,
  ...
}: let
  logger =
    pkgs.writers.writePython3Bin "talos-hypr-eventlog" {
      flakeIgnore = ["E501" "E302" "E305"];
    } ''
      """Tail Hyprland's .socket2.sock and dump floating-window snapshots."""
      import datetime
      import json
      import os
      import socket
      import subprocess
      import sys
      import threading

      LOG_PATH = os.path.expanduser("~/.local/share/talos/hypr-events.log")
      SNAPSHOT_INTERVAL = 60  # seconds

      def stamp() -> str:
          return datetime.datetime.now().isoformat(timespec="seconds")

      def find_socket() -> str:
          sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
          runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
          candidates = []
          if sig:
              candidates.append(os.path.join(runtime, "hypr", sig, ".socket2.sock"))
          hypr_root = os.path.join(runtime, "hypr")
          if os.path.isdir(hypr_root):
              for entry in os.listdir(hypr_root):
                  candidates.append(
                      os.path.join(hypr_root, entry, ".socket2.sock")
                  )
          for path in candidates:
              if os.path.exists(path):
                  return path
          raise SystemExit(
              "could not locate .socket2.sock under $XDG_RUNTIME_DIR/hypr"
          )

      def write_line(fh, text: str) -> None:
          fh.write(f"[{stamp()}] {text}\n")
          fh.flush()

      def snapshot(fh) -> None:
          try:
              clients = subprocess.check_output(
                  ["hyprctl", "clients", "-j"], text=True, timeout=5
              )
              monitors = subprocess.check_output(
                  ["hyprctl", "monitors", "-j"], text=True, timeout=5
              )
          except Exception as exc:
              write_line(fh, f"SNAPSHOT-ERROR {exc}")
              return
          try:
              mons = json.loads(monitors)
              cls = json.loads(clients)
          except json.JSONDecodeError as exc:
              write_line(fh, f"SNAPSHOT-PARSE-ERROR {exc}")
              return

          mon_lines = []
          for m in mons:
              mon_lines.append(
                  f"{m['name']} at=({m['x']},{m['y']}) "
                  f"size={m['width']}x{m['height']} scale={m['scale']} "
                  f"dpms={m.get('dpmsStatus')} "
                  f"active_ws={m['activeWorkspace']['id']}"
              )
          write_line(fh, "MONITORS " + " | ".join(mon_lines))

          for c in cls:
              if not c.get("floating"):
                  continue
              write_line(
                  fh,
                  "FLOAT addr=%s class=%s ws=%s at=(%d,%d) size=%dx%d mon=%s"
                  % (
                      c["address"],
                      c.get("class", ""),
                      c["workspace"]["id"],
                      c["at"][0],
                      c["at"][1],
                      c["size"][0],
                      c["size"][1],
                      c.get("monitor"),
                  ),
              )

      def snapshot_loop(fh, stop: threading.Event) -> None:
          while not stop.is_set():
              snapshot(fh)
              stop.wait(SNAPSHOT_INTERVAL)

      def main() -> None:
          os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
          sock_path = find_socket()
          with open(LOG_PATH, "a", buffering=1) as fh:
              write_line(
                  fh, f"=== logger start, socket={sock_path} pid={os.getpid()}"
              )
              snapshot(fh)  # baseline

              stop = threading.Event()
              t = threading.Thread(
                  target=snapshot_loop, args=(fh, stop), daemon=True
              )
              t.start()

              sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
              try:
                  sock.connect(sock_path)
              except OSError as exc:
                  write_line(fh, f"CONNECT-ERROR {exc}")
                  raise

              buf = b""
              try:
                  while True:
                      chunk = sock.recv(8192)
                      if not chunk:
                          write_line(fh, "EOF on .socket2.sock")
                          break
                      buf += chunk
                      while b"\n" in buf:
                          line, buf = buf.split(b"\n", 1)
                          write_line(
                              fh, "EVENT " + line.decode("utf-8", "replace")
                          )
              except KeyboardInterrupt:
                  pass
              finally:
                  stop.set()
                  sock.close()
                  write_line(fh, "=== logger stop")

      if __name__ == "__main__":
          try:
              main()
          except SystemExit:
              raise
          except Exception as exc:
              print(f"fatal: {exc}", file=sys.stderr)
              sys.exit(1)
    '';
in {
  home.packages = [logger];

  # User-level systemd service. Not autostart; operator runs
  # `systemctl --user start talos-hypr-eventlog` before stepping away.
  systemd.user.services.talos-hypr-eventlog = {
    Unit = {
      Description = "talos diagnostic logger for Hyprland event drift";
      Documentation = "see /etc/nixos/home/desktop/sessions/hyprland/event-logger.nix";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${logger}/bin/talos-hypr-eventlog";
      Restart = "on-failure";
      RestartSec = 5;
    };
    # Deliberately NO Install section -> no autostart, manual only.
  };
}
