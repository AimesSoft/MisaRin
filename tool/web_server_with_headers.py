#!/usr/bin/env python3
from __future__ import annotations

import argparse
import functools
import http.server
import socketserver
import sys
from pathlib import Path


class HeaderRequestHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
    }

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        super().end_headers()


class ThreadingWebServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Serve Flutter web build with COOP/COEP headers.")
    parser.add_argument("--dir", default="build/web", help="Directory to serve.")
    parser.add_argument("--port", type=int, default=53554, help="Port to listen on.")
    args = parser.parse_args(argv)

    directory = Path(args.dir).resolve()
    if not directory.is_dir():
        print(f"Directory does not exist: {directory}", file=sys.stderr)
        return 2

    handler = functools.partial(HeaderRequestHandler, directory=str(directory))
    with ThreadingWebServer(("", args.port), handler) as httpd:
        print(f"Serving {directory} on http://127.0.0.1:{args.port}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
