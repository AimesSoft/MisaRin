#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8000}"
SERVE="${SERVE:-1}"
AUTO_KILL="${AUTO_KILL:-1}"
AUTO_PORT="${AUTO_PORT:-0}"
KILL_PORT="${KILL_PORT:-1}"
PID_FILE="${PID_FILE:-$ROOT_DIR/.web_server.pid}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found in PATH" >&2
  exit 1
fi

if ! command -v wasm-bindgen >/dev/null 2>&1; then
  echo "wasm-bindgen not found in PATH (try: cargo install wasm-bindgen-cli)" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found in PATH" >&2
  exit 1
fi

echo "==> Build Rust wasm"
"$ROOT_DIR/tool/build_web_wasm.sh"

echo "==> flutter build web"
flutter build web

if [[ "$SERVE" != "1" ]]; then
  echo "==> Build complete. Skipping server (SERVE=$SERVE)."
  exit 0
fi

if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    if [[ "$AUTO_KILL" == "1" ]]; then
      echo "==> Stopping previous server (pid $OLD_PID)"
      kill "$OLD_PID" || true
    else
      echo "==> Previous server still running (pid $OLD_PID)."
      echo "   Set AUTO_KILL=1 or delete $PID_FILE and stop it manually."
      exit 1
    fi
  fi
  rm -f "$PID_FILE"
fi

if command -v lsof >/dev/null 2>&1; then
  PORT_PIDS="$(lsof -tiTCP:${PORT} -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$PORT_PIDS" ]]; then
    if [[ "$KILL_PORT" == "1" ]]; then
      echo "==> Port ${PORT} in use, stopping: ${PORT_PIDS}"
      kill ${PORT_PIDS} || true
      for _ in {1..10}; do
        sleep 0.2
        if [[ -z "$(lsof -tiTCP:${PORT} -sTCP:LISTEN 2>/dev/null || true)" ]]; then
          break
        fi
      done
      STILL_PIDS="$(lsof -tiTCP:${PORT} -sTCP:LISTEN 2>/dev/null || true)"
      if [[ -n "$STILL_PIDS" ]]; then
        echo "==> Port ${PORT} still busy, forcing stop: ${STILL_PIDS}"
        kill -9 ${STILL_PIDS} || true
        for _ in {1..10}; do
          sleep 0.2
          if [[ -z "$(lsof -tiTCP:${PORT} -sTCP:LISTEN 2>/dev/null || true)" ]]; then
            break
          fi
        done
      fi
    fi
  fi
  if [[ -n "$(lsof -tiTCP:${PORT} -sTCP:LISTEN 2>/dev/null || true)" ]]; then
    if [[ "$AUTO_PORT" == "1" ]]; then
      NEW_PORT="$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
_, port = s.getsockname()
s.close()
print(port)
PY
)"
      echo "==> Port ${PORT} still busy, switching to ${NEW_PORT}"
      PORT="${NEW_PORT}"
    else
      echo "==> Port ${PORT} still in use."
      echo "   Stop the process or set PORT=xxxx / AUTO_PORT=1 / KILL_PORT=1."
      exit 1
    fi
  fi
fi

echo "==> Serving build/web with COOP/COEP at http://${HOST}:${PORT}"

ROOT_DIR="$ROOT_DIR" HOST="$HOST" PORT="$PORT" PID_FILE="$PID_FILE" python3 - <<'PY'
import os
import atexit
import signal
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

root = os.path.join(os.environ["ROOT_DIR"], "build", "web")
host = os.environ.get("HOST", "127.0.0.1")
port = int(os.environ.get("PORT", "8000"))
pid_file = os.environ.get("PID_FILE")

os.chdir(root)

class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
    def do_POST(self):
        if self.path != "/__log":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length") or "0")
        data = self.rfile.read(length) if length > 0 else b""
        text = data.decode("utf-8", "replace")
        print(f"[web-log] {text}")
        self.send_response(204)
        self.end_headers()

class ReuseTCPServer(ThreadingHTTPServer):
    allow_reuse_address = True

httpd = ReuseTCPServer((host, port), Handler)
if pid_file:
    with open(pid_file, "w", encoding="utf-8") as f:
        f.write(str(os.getpid()))
    def _cleanup():
        try:
            os.remove(pid_file)
        except FileNotFoundError:
            pass
    atexit.register(_cleanup)

def _handle_exit(_signum, _frame):
    sys.exit(0)

signal.signal(signal.SIGTERM, _handle_exit)
print(f"Serving {root} at http://{host}:{port}")
httpd.serve_forever()
PY
