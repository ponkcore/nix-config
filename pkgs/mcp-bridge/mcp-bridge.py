#!/usr/bin/env python3
"""mcp-bridge — call a stdio MCP server's tool as a one-shot CLI command.

Letta Code (local backend) is intentionally NOT an MCP client. As Letta's own
built-in skill recommends, MCP servers are reached by bridging them. This is a
dependency-free (python3 only — no node/npx/tsx) one-shot bridge: spawn the
server over stdio, do the JSON-RPC handshake, call one tool, print the text
result, exit. Faithful to the upstream servers (zero behavior drift).

Usage:
  mcp-bridge --server '<cmd> [args...]' --tool <name> [--args '<json>']
  mcp-bridge --server '<cmd> [args...]' --list          # list tools
  mcp-bridge --server 'mcp-nixos' --tool nixos_search --args '{"query":"firefox","type":"packages"}'

Notes:
- --server is a shell-style command string (split with shlex). Prefer an
  on-PATH binary (packaged via nix) over uvx to avoid runtime resolution.
- Pass secrets through the environment (e.g. CONTEXT7_API_KEY); they are
  inherited by the spawned server.
- Exit code 0 on success, 1 on tool error, 2 on bad args, 3 on protocol/timeout.
"""
import argparse
import json
import os
import queue
import shlex
import subprocess
import sys
import threading
import time

PROTOCOL_VERSION = "2025-06-18"


class Server:
    def __init__(self, cmd, timeout):
        self.timeout = timeout
        self.proc = subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, bufsize=0, env=os.environ.copy(),
        )
        self._q = queue.Queue()
        self._reader = threading.Thread(target=self._read_lines, daemon=True)
        self._reader.start()

    def _read_lines(self):
        # Dedicated reader thread: avoids select()/buffering pitfalls.
        try:
            for raw in self.proc.stdout:
                self._q.put(raw)
        except Exception:
            pass
        finally:
            self._q.put(None)  # EOF sentinel

    def send(self, msg):
        self.proc.stdin.write((json.dumps(msg) + "\n").encode())
        self.proc.stdin.flush()

    def _next_json(self, deadline):
        """Return the next JSON message, skipping non-JSON log lines."""
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("timed out waiting for MCP server response")
            try:
                raw = self._q.get(timeout=min(remaining, 1.0))
            except queue.Empty:
                if self.proc.poll() is not None:
                    raise RuntimeError(
                        f"MCP server exited (code {self.proc.returncode})")
                continue
            if raw is None:
                raise RuntimeError("MCP server closed stdout")
            line = raw.strip()
            if not line:
                continue
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue  # server log line on stdout; ignore

    def request(self, _id, method, params=None):
        self.send({"jsonrpc": "2.0", "id": _id, "method": method, "params": params or {}})
        deadline = time.monotonic() + self.timeout
        while True:
            msg = self._next_json(deadline)
            if msg.get("id") == _id:
                if "error" in msg:
                    raise RuntimeError(f"{method} error: {json.dumps(msg['error'])}")
                return msg.get("result", {})
            # ignore notifications / unrelated ids

    def notify(self, method, params=None):
        self.send({"jsonrpc": "2.0", "method": method, "params": params or {}})

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.terminate()
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()


def extract_text(result):
    content = result.get("content")
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                parts.append(item.get("text", ""))
            else:
                parts.append(json.dumps(item))
        return "\n".join(parts)
    return json.dumps(result, indent=2)


def main():
    ap = argparse.ArgumentParser(description="One-shot stdio MCP tool caller.")
    ap.add_argument("--server", required=True, help="server command, e.g. 'mcp-nixos'")
    ap.add_argument("--tool", help="tool name to call")
    ap.add_argument("--args", default="{}", help="JSON object of tool arguments")
    ap.add_argument("--list", action="store_true", help="list tools and exit")
    ap.add_argument("--timeout", type=float, default=60.0)
    a = ap.parse_args()

    srv = Server(shlex.split(a.server), a.timeout)
    try:
        srv.request(1, "initialize", {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {},
            "clientInfo": {"name": "mcp-bridge", "version": "1.0"},
        })
        srv.notify("notifications/initialized")

        if a.list or not a.tool:
            for t in srv.request(2, "tools/list").get("tools", []):
                desc = (t.get("description") or "").splitlines()
                print(f"{t.get('name')}\t{desc[0] if desc else ''}")
            return 0

        try:
            tool_args = json.loads(a.args)
        except json.JSONDecodeError as e:
            print(f"--args is not valid JSON: {e}", file=sys.stderr)
            return 2

        result = srv.request(3, "tools/call", {"name": a.tool, "arguments": tool_args})
        print(extract_text(result))
        return 1 if result.get("isError") else 0
    except (TimeoutError, RuntimeError) as e:
        print(f"mcp-bridge: {e}", file=sys.stderr)
        return 3
    finally:
        srv.close()


if __name__ == "__main__":
    sys.exit(main())
