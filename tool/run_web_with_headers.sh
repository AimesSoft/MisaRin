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

RUST_TOOLCHAIN="${RUST_TOOLCHAIN:-nightly}"
if command -v rustup >/dev/null 2>&1; then
  if ! rustup toolchain list | grep -q "^${RUST_TOOLCHAIN}"; then
    echo "Rust toolchain ${RUST_TOOLCHAIN} is not installed. Run:" >&2
    echo "  rustup toolchain install ${RUST_TOOLCHAIN}" >&2
    exit 1
  fi
  if ! rustup target list --installed --toolchain "${RUST_TOOLCHAIN}" | grep -q "^${WASM_TARGET}$"; then
    echo "Rust target ${WASM_TARGET} is not installed. Run:" >&2
    echo "  rustup target add ${WASM_TARGET} --toolchain ${RUST_TOOLCHAIN}" >&2
    exit 1
  fi
fi

echo "Building Rust (wasm)..."
export RUSTFLAGS="${RUSTFLAGS:-} -C target-feature=+atomics,+bulk-memory,+mutable-globals -C link-arg=--shared-memory -C link-arg=--max-memory=1073741824 -C link-arg=--import-memory -C link-arg=--export=__wasm_init_tls -C link-arg=--export=__tls_base -C link-arg=--export=__tls_size -C link-arg=--export=__tls_align"
cargo +${RUST_TOOLCHAIN} build -Z build-std=std,panic_abort --manifest-path "${ROOT_DIR}/rust/Cargo.toml" --target "${WASM_TARGET}" --release

WASM_PATH="${ROOT_DIR}/rust/target/${WASM_TARGET}/release/rust_lib_misa_rin.wasm"
OUT_DIR="${ROOT_DIR}/web/pkg"
mkdir -p "${OUT_DIR}"
echo "Checking shared memory flag..."
export WASM_PATH
python3 - <<'PY'
import os
import sys
path = os.environ.get("WASM_PATH")
if not path:
    print("WASM_PATH not set", file=sys.stderr)
    sys.exit(1)
data = open(path, "rb").read()
if data[:4] != b"\0asm":
    print("Invalid wasm: missing magic header", file=sys.stderr)
    sys.exit(1)
def read_leb(i):
    result = 0
    shift = 0
    while True:
        b = data[i]
        i += 1
        result |= (b & 0x7f) << shift
        if b < 0x80:
            break
        shift += 7
    return result, i
idx = 8
shared = None
max_pages = None
def read_name(i):
    ln, i = read_leb(i)
    return data[i:i+ln].decode("utf-8", "replace"), i + ln

def skip_limits(i):
    flags, i = read_leb(i)
    _min, i = read_leb(i)
    if flags & 1:
        _max, i = read_leb(i)
    return i

while idx < len(data):
    sec_id = data[idx]
    idx += 1
    size, idx = read_leb(idx)
    sec_end = idx + size
    if sec_id == 2:
        # import section
        count, idx = read_leb(idx)
        for _ in range(count):
            _, idx = read_name(idx)  # module
            _, idx = read_name(idx)  # name
            kind = data[idx]
            idx += 1
            if kind == 2:  # memory
                flags, idx = read_leb(idx)
                _min, idx = read_leb(idx)
                if flags & 1:
                    max_pages, idx = read_leb(idx)
                shared = bool(flags & 2) if shared is None else (shared or bool(flags & 2))
            elif kind == 0:  # func
                _, idx = read_leb(idx)
            elif kind == 1:  # table
                idx += 1  # element type
                idx = skip_limits(idx)
            elif kind == 3:  # global
                idx += 2  # valtype + mutability
            elif kind == 4:  # tag
                _, idx = read_leb(idx)  # attribute
                _, idx = read_leb(idx)  # type index
            else:
                idx = sec_end
                break
    elif sec_id == 5:
        # memory section
        count, idx = read_leb(idx)
        if count:
            flags, idx = read_leb(idx)
            _min, idx = read_leb(idx)
            if flags & 1:
                max_pages, idx = read_leb(idx)
            shared = bool(flags & 2) if shared is None else (shared or bool(flags & 2))
    idx = sec_end

if shared is not True:
    print("WASM memory is NOT shared; Web Workers will fail (DataCloneError).", file=sys.stderr)
    print("RUSTFLAGS must include --shared-memory and --max-memory.", file=sys.stderr)
    sys.exit(2)
print(f"WASM shared memory OK (max_pages={max_pages}).")
PY
echo "Running wasm-bindgen..."
wasm-bindgen --target no-modules --no-typescript --out-dir "${OUT_DIR}" "${WASM_PATH}"

FLUTTER_WEB_MODE="${FLUTTER_WEB_MODE:-release}"
echo "Building Flutter web (${FLUTTER_WEB_MODE})..."
flutter build web "--${FLUTTER_WEB_MODE}"

echo "Starting web server with COOP/COEP headers..."
python3 "${ROOT_DIR}/tool/web_server_with_headers.py" --dir "${ROOT_DIR}/build/web" --port "${PORT}" &
echo $! > "${PID_FILE}"
echo "Web server PID: $(cat "${PID_FILE}")"
echo "Open: http://127.0.0.1:${PORT}"
