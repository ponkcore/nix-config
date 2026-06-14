#!/usr/bin/env python3
"""mcp-bridge — one-shot MCP tool caller for stdio or remote HTTP/SSE servers.

Letta Code (local backend) is intentionally NOT an MCP client. As Letta's own
built-in skill recommends, MCP servers are reached by bridging them. This is a
dependency-free (python3 stdlib only) one-shot bridge: connect to a server, do
the JSON-RPC handshake, call one tool, print the text result, exit.

Usage:
  mcp-bridge --server '<cmd> [args...]' --tool <name> [--args '<json>']
  mcp-bridge --server '<cmd> [args...]' --list
  mcp-bridge --url '<mcp-url>' --header-env 'X-API-Key=ENV_VAR' --list
  mcp-bridge --url '<mcp-url>' --header-env 'X-API-Key=ENV_VAR' --tool <name> --args '<json>'

Notes:
- --server is a shell-style command string (split with shlex). Prefer an
  on-PATH binary (packaged via nix) over uvx to avoid runtime resolution.
- --url targets Streamable HTTP or legacy SSE MCP servers. URLs ending in /sse
  use the legacy GET-SSE + POST-message-endpoint flow.
- Pass secrets through the environment with --header-env; never put secrets on
  the command line. Child stdio servers inherit the environment.
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
import urllib.error
import urllib.parse
import urllib.request

PROTOCOL_VERSION = "2025-06-18"


class StdioServer:
    def __init__(self, cmd, timeout):
        self.timeout = timeout
        self.proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            bufsize=0,
            env=os.environ.copy(),
        )
        self._q = queue.Queue()
        self._reader = threading.Thread(target=self._read_lines, daemon=True)
        self._reader.start()

    def _read_lines(self):
        try:
            for raw in self.proc.stdout:
                self._q.put(raw)
        except Exception:
            pass
        finally:
            self._q.put(None)

    def send(self, msg):
        self.proc.stdin.write((json.dumps(msg) + "\n").encode())
        self.proc.stdin.flush()

    def _next_json(self, deadline):
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("timed out waiting for MCP server response")
            try:
                raw = self._q.get(timeout=min(remaining, 1.0))
            except queue.Empty:
                if self.proc.poll() is not None:
                    raise RuntimeError(
                        f"MCP server exited (code {self.proc.returncode})"
                    )
                continue
            if raw is None:
                raise RuntimeError("MCP server closed stdout")
            line = raw.strip()
            if not line:
                continue
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue

    def request(self, _id, method, params=None):
        self.send(
            {"jsonrpc": "2.0", "id": _id, "method": method, "params": params or {}}
        )
        deadline = time.monotonic() + self.timeout
        while True:
            msg = self._next_json(deadline)
            if msg.get("id") == _id:
                if "error" in msg:
                    raise RuntimeError(f"{method} error: {json.dumps(msg['error'])}")
                return msg.get("result", {})

    def notify(self, method, params=None):
        self.send({"jsonrpc": "2.0", "method": method, "params": params or {}})

    def close(self):
        try:
            self.proc.stdin.close()
            self.proc.terminate()
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()


class StreamableHttpServer:
    def __init__(self, url, headers, timeout):
        self.url = url
        self.headers = headers
        self.timeout = timeout
        self.session_id = None

    def _parse_sse_response(self, text):
        data_parts = []
        for line in text.splitlines():
            if line.startswith("data: "):
                data_parts.append(line[6:])
        for data in reversed(data_parts):
            if not data:
                continue
            try:
                parsed = json.loads(data)
            except json.JSONDecodeError:
                continue
            if isinstance(parsed, dict) and parsed.get("jsonrpc") == "2.0":
                return parsed
        raise RuntimeError("no valid JSON-RPC response found in SSE stream")

    def _raw_request(self, msg):
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            **self.headers,
        }
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id

        request = urllib.request.Request(
            self.url,
            data=json.dumps(msg).encode(),
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                body = response.read().decode()
                content_type = response.headers.get("content-type", "")
                new_session = response.headers.get("Mcp-Session-Id")
        except urllib.error.HTTPError as error:
            body = error.read().decode(errors="replace")
            if error.code in (401, 403):
                raise RuntimeError("authentication failed for MCP HTTP server")
            try:
                parsed = json.loads(body)
            except json.JSONDecodeError as exc:
                raise RuntimeError(f"HTTP {error.code}: {error.reason}: {body}") from exc
            return parsed
        except urllib.error.URLError as error:
            raise RuntimeError(f"cannot connect to MCP HTTP server: {error.reason}")

        if new_session:
            self.session_id = new_session

        if not body.strip():
            return {}
        if "application/json" in content_type:
            return json.loads(body)
        if "text/event-stream" in content_type:
            return self._parse_sse_response(body)
        raise RuntimeError(f"unexpected content type from MCP HTTP server: {content_type}")

    def request(self, _id, method, params=None):
        msg = {"jsonrpc": "2.0", "id": _id, "method": method, "params": params or {}}
        response = self._raw_request(msg)
        if "error" in response:
            raise RuntimeError(f"{method} error: {json.dumps(response['error'])}")
        if response.get("id") not in (None, _id):
            raise RuntimeError(f"unexpected JSON-RPC response id: {response.get('id')}")
        return response.get("result", {})

    def notify(self, method, params=None):
        self._raw_request({"jsonrpc": "2.0", "method": method, "params": params or {}})

    def close(self):
        pass


class LegacySseServer:
    def __init__(self, url, headers, timeout):
        self.url = url
        self.headers = headers
        self.timeout = timeout
        self.endpoint_url = None
        self._endpoint_q = queue.Queue()
        self._msg_q = queue.Queue()
        self._response = None
        self._reader = threading.Thread(target=self._read_stream, daemon=True)
        self._reader.start()
        self.endpoint_url = self._wait_for_endpoint()

    def _read_stream(self):
        headers = {"Accept": "text/event-stream", **self.headers}
        request = urllib.request.Request(self.url, headers=headers, method="GET")
        try:
            self._response = urllib.request.urlopen(request, timeout=self.timeout)
            event_name = "message"
            data_lines = []
            for raw in self._response:
                line = raw.decode(errors="replace").rstrip("\r\n")
                if not line:
                    self._dispatch_event(event_name, "\n".join(data_lines))
                    event_name = "message"
                    data_lines = []
                    continue
                if line.startswith(":"):
                    continue
                if line.startswith("event:"):
                    event_name = line[6:].strip() or "message"
                    continue
                if line.startswith("data:"):
                    data_lines.append(line[5:].lstrip())
        except Exception as exc:
            self._endpoint_q.put(exc)
            self._msg_q.put(exc)

    def _dispatch_event(self, event_name, data):
        if not data:
            return
        if event_name == "endpoint":
            self._endpoint_q.put(data)
            return
        try:
            parsed = json.loads(data)
        except json.JSONDecodeError:
            return
        if isinstance(parsed, dict) and parsed.get("jsonrpc") == "2.0":
            self._msg_q.put(parsed)

    def _wait_for_endpoint(self):
        deadline = time.monotonic() + self.timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("timed out waiting for MCP SSE endpoint")
            item = self._endpoint_q.get(timeout=min(remaining, 1.0))
            if isinstance(item, Exception):
                raise RuntimeError(f"cannot connect to MCP SSE server: {item}")
            parsed = urllib.parse.urlparse(self.url)
            origin = urllib.parse.urlunparse(
                (parsed.scheme, parsed.netloc, "", "", "", "")
            )
            return urllib.parse.urljoin(origin, item)

    def _post(self, msg):
        headers = {
            "Content-Type": "application/json",
            **self.headers,
        }
        request = urllib.request.Request(
            self.endpoint_url,
            data=json.dumps(msg).encode(),
            headers=headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                response.read()
        except urllib.error.HTTPError as error:
            body = error.read().decode(errors="replace")
            if error.code in (401, 403):
                raise RuntimeError("authentication failed for MCP SSE server")
            raise RuntimeError(f"HTTP {error.code}: {error.reason}: {body}")
        except urllib.error.URLError as error:
            raise RuntimeError(f"cannot post to MCP SSE endpoint: {error.reason}")

    def request(self, _id, method, params=None):
        self._post(
            {"jsonrpc": "2.0", "id": _id, "method": method, "params": params or {}}
        )
        deadline = time.monotonic() + self.timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("timed out waiting for MCP SSE response")
            item = self._msg_q.get(timeout=min(remaining, 1.0))
            if isinstance(item, Exception):
                raise RuntimeError(f"MCP SSE stream failed: {item}")
            if item.get("id") == _id:
                if "error" in item:
                    raise RuntimeError(f"{method} error: {json.dumps(item['error'])}")
                return item.get("result", {})

    def notify(self, method, params=None):
        self._post({"jsonrpc": "2.0", "method": method, "params": params or {}})

    def close(self):
        if self._response:
            self._response.close()


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


def parse_headers(header_args, header_env_args):
    headers = {}
    for value in header_args or []:
        if ":" not in value:
            raise ValueError("--header must use 'Name: value' syntax")
        key, header_value = value.split(":", 1)
        headers[key.strip()] = header_value.strip()
    for value in header_env_args or []:
        if "=" not in value:
            raise ValueError("--header-env must use 'Header-Name=ENV_VAR' syntax")
        key, env_name = value.split("=", 1)
        env_value = os.environ.get(env_name)
        if not env_value:
            raise ValueError(f"environment variable {env_name} is not set")
        headers[key.strip()] = env_value
    return headers


def main():
    ap = argparse.ArgumentParser(description="One-shot MCP tool caller.")
    target = ap.add_mutually_exclusive_group(required=True)
    target.add_argument("--server", help="stdio server command, e.g. 'mcp-nixos'")
    target.add_argument("--url", help="HTTP/SSE MCP server URL")
    ap.add_argument(
        "--transport",
        choices=["auto", "http", "sse"],
        default="auto",
        help="remote transport for --url (default: auto)",
    )
    ap.add_argument("--header", action="append", help="HTTP header, 'Name: value'")
    ap.add_argument(
        "--header-env",
        action="append",
        help="HTTP header from env, 'Name=ENV_VAR'",
    )
    ap.add_argument("--tool", help="tool name to call")
    ap.add_argument("--args", default="{}", help="JSON object of tool arguments")
    ap.add_argument("--list", action="store_true", help="list tools and exit")
    ap.add_argument("--timeout", type=float, default=60.0)
    a = ap.parse_args()

    try:
        headers = parse_headers(a.header, a.header_env)
    except ValueError as e:
        print(str(e), file=sys.stderr)
        return 2

    if a.server:
        srv = StdioServer(shlex.split(a.server), a.timeout)
    else:
        use_sse = a.transport == "sse" or (
            a.transport == "auto" and urllib.parse.urlparse(a.url).path.rstrip("/").endswith("/sse")
        )
        srv = LegacySseServer(a.url, headers, a.timeout) if use_sse else StreamableHttpServer(a.url, headers, a.timeout)

    try:
        srv.request(
            1,
            "initialize",
            {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": {"name": "mcp-bridge", "version": "1.1"},
            },
        )
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
