#!/usr/bin/env python3
"""A stand-in Anthropic API that always answers 429.

Point the real Claude Code binary at this with ANTHROPIC_BASE_URL and it takes
the genuine rate-limit path — its own error handling, its own transcript
writing. That is the one thing a stubbed `claude` cannot prove: that detection
matches what the real client actually records.

Costs nothing and burns no quota, unlike waiting for a real 5-hour window.

  python3 test/mock-api.py [port]      # prints the port, serves until killed
"""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

RESETS_AT = int(time.time()) + 3600


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, payload, headers=None):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        length = int(self.headers.get("content-length") or 0)
        if length:
            self.rfile.read(length)

        # Shaped after a real rate-limit response: 429, the documented
        # retry/reset headers, and an error body of type rate_limit_error.
        self._send(
            429,
            {"type": "error",
             "error": {"type": "rate_limit_error",
                       "message": "You've hit your usage limit."}},
            {"retry-after": "3600",
             "anthropic-ratelimit-unified-status": "rejected",
             "anthropic-ratelimit-unified-reset": str(RESETS_AT),
             "anthropic-ratelimit-unified-fallback-available": "false"},
        )

    def do_GET(self):
        self._send(200, {"ok": True})

    def log_message(self, *_):
        pass            # keep the test output readable


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    server = HTTPServer(("127.0.0.1", port), Handler)
    print(f"port={server.server_port} resetsAt={RESETS_AT}", flush=True)
    server.serve_forever()
