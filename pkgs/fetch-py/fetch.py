#!/usr/bin/env python3
"""fetch.py — guarded web fetch for talos (replaces the mcp-server-fetch tool).

Letta's built-in web fetch is cloud-only and dead on the local backend, so this
is a dependency-free (python3 stdlib only) replacement that ENFORCES talos's §7
fetch guardrails:
  - http/https only
  - SSRF protection: refuse loopback / private / link-local / reserved IPs,
    re-validated on every redirect hop
  - custom User-Agent
  - hard 1 MiB response cap
  - HTML -> readable text (or --raw for unconverted body)
  - max_length truncation + start_index chunking (like the upstream fetch tool)

Usage:
  fetch.py <url> [--max-length N] [--start-index N] [--raw] [--timeout S]
"""
import argparse
import gzip
import io
import ipaddress
import socket
import sys
import urllib.request
from html.parser import HTMLParser
from urllib.parse import urlparse, urljoin

MAX_BYTES = 1024 * 1024  # 1 MiB hard cap
USER_AGENT = "talos-web-fetch/1.0 (+nixos; static-content only)"
MAX_REDIRECTS = 5


def _is_public_ip(ip_str):
    ip = ipaddress.ip_address(ip_str)
    return not (
        ip.is_private or ip.is_loopback or ip.is_link_local
        or ip.is_multicast or ip.is_reserved or ip.is_unspecified
    )


def _assert_safe_host(host):
    """Resolve host and ensure every address is a public/global IP (anti-SSRF)."""
    try:
        infos = socket.getaddrinfo(host, None)
    except socket.gaierror as e:
        raise ValueError(f"cannot resolve host {host!r}: {e}")
    addrs = {info[4][0] for info in infos}
    if not addrs:
        raise ValueError(f"no addresses for host {host!r}")
    for a in addrs:
        if not _is_public_ip(a):
            raise ValueError(f"refusing non-public address {a} for host {host!r}")


def _open_no_redirect(url, timeout):
    class _NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *a, **k):
            return None
    opener = urllib.request.build_opener(_NoRedirect)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT,
                                               "Accept-Encoding": "gzip"})
    return opener.open(req, timeout=timeout)


def fetch(url, timeout):
    """Fetch with manual, validated redirect handling. Returns (final_url, ctype, body_bytes)."""
    for _ in range(MAX_REDIRECTS + 1):
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https"):
            raise ValueError(f"only http/https allowed, got {parsed.scheme!r}")
        if not parsed.hostname:
            raise ValueError("URL has no host")
        _assert_safe_host(parsed.hostname)
        try:
            resp = _open_no_redirect(url, timeout)
        except urllib.error.HTTPError as e:
            if e.code in (301, 302, 303, 307, 308):
                resp = e
            else:
                raise
        status = getattr(resp, "status", None) or resp.getcode()
        if status in (301, 302, 303, 307, 308):
            loc = resp.headers.get("Location")
            if not loc:
                raise ValueError(f"redirect {status} without Location")
            url = urljoin(url, loc)
            resp.close()
            continue
        # 2xx: read with hard cap
        raw = resp.read(MAX_BYTES + 1)
        truncated_cap = len(raw) > MAX_BYTES
        raw = raw[:MAX_BYTES]
        if resp.headers.get("Content-Encoding", "").lower() == "gzip":
            try:
                raw = gzip.GzipFile(fileobj=io.BytesIO(raw)).read(MAX_BYTES)
            except OSError:
                pass
        ctype = resp.headers.get("Content-Type", "")
        return url, ctype, raw, truncated_cap
    raise ValueError("too many redirects")


class _TextExtractor(HTMLParser):
    SKIP = {"script", "style", "noscript", "head", "svg", "template"}
    BLOCK = {"p", "div", "section", "article", "br", "li", "tr", "h1", "h2",
             "h3", "h4", "h5", "h6", "header", "footer", "table", "ul", "ol"}

    def __init__(self):
        super().__init__()
        self.out = []
        self._skip = 0
        self.script_chars = 0

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP:
            self._skip += 1
        if tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
            self.out.append("\n\n# ")
        elif tag == "li":
            self.out.append("\n- ")
        elif tag in self.BLOCK:
            self.out.append("\n")

    def handle_endtag(self, tag):
        if tag in self.SKIP and self._skip:
            self._skip -= 1
        if tag in self.BLOCK:
            self.out.append("\n")

    def handle_data(self, data):
        if self._skip:
            self.script_chars += len(data)
            return
        text = data.strip()
        if text:
            self.out.append(text + " ")

    def text(self):
        raw = "".join(self.out)
        lines = [ln.strip() for ln in raw.splitlines()]
        cleaned, blanks = [], 0
        for ln in lines:
            if ln:
                cleaned.append(ln)
                blanks = 0
            else:
                blanks += 1
                if blanks <= 1:
                    cleaned.append("")
        return "\n".join(cleaned).strip()


def main():
    ap = argparse.ArgumentParser(description="Guarded web fetch (talos §7).")
    ap.add_argument("url")
    ap.add_argument("--max-length", type=int, default=5000)
    ap.add_argument("--start-index", type=int, default=0)
    ap.add_argument("--raw", action="store_true", help="return body unconverted")
    ap.add_argument("--timeout", type=float, default=20.0)
    a = ap.parse_args()

    try:
        final_url, ctype, body, capped = fetch(a.url, a.timeout)
    except Exception as e:
        print(f"fetch.py: {e}", file=sys.stderr)
        return 1

    is_html = "html" in ctype.lower() or (
        not ctype and body[:200].lstrip().lower().startswith(b"<"))
    if a.raw or not is_html:
        content = body.decode("utf-8", "replace")
        warn = ""
    else:
        p = _TextExtractor()
        try:
            p.feed(body.decode("utf-8", "replace"))
        except Exception:
            pass
        content = p.text()
        # SPA heuristic: lots of script, little text -> likely client-rendered.
        warn = ""
        if len(content) < 200 and p.script_chars > 2000:
            warn = ("[warn] very little static text vs. script — page is likely "
                    "a client-rendered SPA; content may be incomplete. Consider a "
                    "different source or the library's raw docs.]\n")

    total = len(content)
    chunk = content[a.start_index:a.start_index + a.max_length]
    more = a.start_index + a.max_length < total

    header = f"# {final_url}\n# {total} chars"
    if capped:
        header += " (response hit 1 MiB cap)"
    if more:
        header += (f" | showing [{a.start_index}:{a.start_index + a.max_length}] "
                   f"— next: --start-index {a.start_index + a.max_length}")
    print(header)
    if warn:
        print(warn)
    print(chunk)
    return 0


if __name__ == "__main__":
    sys.exit(main())
