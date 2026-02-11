#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${WEB_PORT:-53554}"
PID_FILE="${ROOT_DIR}/.web_server.pid"
WASM_TARGET="wasm32-unknown-unknown"

kill_existing_server() {
  if [ -f "$PID_FILE" ]; then
    local pid
    pid="$(cat "$PID_FILE" || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "Stopping existing web server (pid=$pid)"
      kill "$pid" || true
      for _ in {1..20}; do
        if ! kill -0 "$pid" 2>/dev/null; then
          break
        fi
        sleep 0.1
      done
      if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" || true
      fi
    fi
    rm -f "$PID_FILE"
  fi

  if command -v lsof >/dev/null 2>&1; then
    local port_pid
    port_pid="$(lsof -ti tcp:"$PORT" || true)"
    if [ -n "$port_pid" ]; then
      echo "Stopping process on port $PORT (pid=$port_pid)"
      kill "$port_pid" || true
    fi
  fi
}

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Missing command: $name" >&2
    exit 1
  fi
}

kill_existing_server

require_cmd cargo
require_cmd wasm-bindgen
require_cmd flutter
require_cmd python3

if command -v rustup >/dev/null 2>&1; then
  if ! rustup target list --installed | grep -q "^${WASM_TARGET}$"; then
    echo "Rust target ${WASM_TARGET} is not installed. Run:" >&2
    echo "  rustup target add ${WASM_TARGET}" >&2
    exit 1
  fi
fi

echo "Building Rust (wasm)..."
export RUSTFLAGS="${RUSTFLAGS:-} -C target-feature=+atomics,+bulk-memory,+mutable-globals"
cargo build --manifest-path "${ROOT_DIR}/rust/Cargo.toml" --target "${WASM_TARGET}" --release

WASM_PATH="${ROOT_DIR}/rust/target/${WASM_TARGET}/release/rust_lib_misa_rin.wasm"
OUT_DIR="${ROOT_DIR}/web/pkg"
mkdir -p "${OUT_DIR}"
echo "Running wasm-bindgen..."
wasm-bindgen --target web --no-typescript --out-dir "${OUT_DIR}" "${WASM_PATH}"

FLUTTER_WEB_MODE="${FLUTTER_WEB_MODE:-release}"
echo "Building Flutter web (${FLUTTER_WEB_MODE})..."
flutter build web "--${FLUTTER_WEB_MODE}"

echo "Starting web server with COOP/COEP headers..."
python3 "${ROOT_DIR}/tool/web_server_with_headers.py" --dir "${ROOT_DIR}/build/web" --port "${PORT}" &
echo $! > "${PID_FILE}"
echo "Web server PID: $(cat "${PID_FILE}")"
echo "Open: http://127.0.0.1:${PORT}"
