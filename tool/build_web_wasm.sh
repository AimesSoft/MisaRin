#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_DIR="$ROOT_DIR/rust"
OUT_DIR="$ROOT_DIR/web/pkg"
CRATE_NAME="rust_lib_misa_rin"
# Default to single-threaded wasm for stability; override with WASM_THREADS=1.
WASM_THREADS="${WASM_THREADS:-0}"

mkdir -p "$OUT_DIR"

USE_THREADS=0
CARGO_CMD=(cargo)
BUILD_STD_FLAGS=()
EXTRA_RUSTFLAGS=""

if [[ "$WASM_THREADS" == "0" ]]; then
  echo "==> wasm threads: disabled (WASM_THREADS=0)"
else
  if ! command -v rustup >/dev/null 2>&1; then
    echo "WASM threads require rustup + nightly." >&2
    echo "Install rustup or set WASM_THREADS=0." >&2
    exit 1
  fi
  if ! rustup run nightly rustc -V >/dev/null 2>&1; then
    echo "WASM threads require the nightly toolchain." >&2
    echo "Install it with: rustup toolchain install nightly" >&2
    exit 1
  fi
  SYSROOT="$(rustup run nightly rustc --print sysroot 2>/dev/null || true)"
  if [[ -z "${SYSROOT}" || ! -d "${SYSROOT}/lib/rustlib/src/rust/library" ]]; then
    echo "WASM threads require rust-src for nightly." >&2
    echo "Install it with: rustup component add rust-src --toolchain nightly" >&2
    exit 1
  fi
  USE_THREADS=1
  CARGO_CMD=(rustup run nightly cargo)
  EXTRA_RUSTFLAGS="-C target-feature=+atomics,+bulk-memory,+mutable-globals \
  -C link-arg=--shared-memory \
  -C link-arg=--import-memory \
  -C link-arg=--max-memory=2147483648 \
  -C link-arg=--export=__wasm_init_tls \
  -C link-arg=--export=__tls_size \
  -C link-arg=--export=__tls_align \
  -C link-arg=--export=__tls_base"
  BUILD_STD_FLAGS=(-Z build-std=std,panic_abort)
  echo "==> wasm threads: enabled"
fi

if [[ -n "${EXTRA_RUSTFLAGS}" ]]; then
  if [[ -n "${RUSTFLAGS:-}" ]]; then
    export RUSTFLAGS="${RUSTFLAGS} ${EXTRA_RUSTFLAGS}"
  else
    export RUSTFLAGS="${EXTRA_RUSTFLAGS}"
  fi
fi

build_cmd=("${CARGO_CMD[@]}" build)
if [[ "${#BUILD_STD_FLAGS[@]}" -gt 0 ]]; then
  build_cmd+=("${BUILD_STD_FLAGS[@]}")
fi
build_cmd+=(
  --manifest-path "$RUST_DIR/Cargo.toml"
  --target wasm32-unknown-unknown
  --release
)
"${build_cmd[@]}"

wasm-bindgen \
  "$RUST_DIR/target/wasm32-unknown-unknown/release/${CRATE_NAME}.wasm" \
  --out-dir "$OUT_DIR" \
  --no-typescript \
  --target no-modules \
  --out-name "$CRATE_NAME"

if [[ "$USE_THREADS" == "1" ]]; then
  THREAD_STACK_SIZE="${WASM_THREAD_STACK_SIZE:-33554432}"
  MEMORY_INITIAL_PAGES="${WASM_MEMORY_INITIAL_PAGES:-4096}"
  MEMORY_MAX_PAGES="${WASM_MEMORY_MAX_PAGES:-32768}"
  OUT_DIR="$OUT_DIR" CRATE_NAME="$CRATE_NAME" THREAD_STACK_SIZE="$THREAD_STACK_SIZE" \
  MEMORY_INITIAL_PAGES="$MEMORY_INITIAL_PAGES" MEMORY_MAX_PAGES="$MEMORY_MAX_PAGES" python3 - <<'PY'
import pathlib
import re
import os
import math

path = pathlib.Path(os.environ["OUT_DIR"]) / f"{os.environ['CRATE_NAME']}.js"
text = path.read_text(encoding="utf-8")

thread_stack_size = int(os.environ.get("THREAD_STACK_SIZE", "33554432"))
memory_initial_pages = int(os.environ.get("MEMORY_INITIAL_PAGES", "4096"))
memory_max_pages = int(os.environ.get("MEMORY_MAX_PAGES", "32768"))
stack_pages = math.ceil(thread_stack_size / 65536)
min_initial_pages = stack_pages + 16
if memory_initial_pages < min_initial_pages:
    memory_initial_pages = min_initial_pages
if memory_max_pages < memory_initial_pages:
    memory_max_pages = memory_initial_pages
snippet = (
    "\n        if (typeof thread_stack_size === 'undefined') {\n"
    f"            thread_stack_size = {thread_stack_size};\n"
    "        }\n"
)

if "typeof thread_stack_size === 'undefined'" not in text:
    marker = "\n        const imports = __wbg_get_imports(memory);\n"
    text = text.replace(marker, snippet + marker, 2)

text = re.sub(
    r"new WebAssembly\\.Memory\\(\\{initial:\\s*\\d+,\\s*maximum:\\s*\\d+,\\s*shared:true\\}\\)",
    f"new WebAssembly.Memory({{initial:{memory_initial_pages},maximum:{memory_max_pages},shared:true}})",
    text,
    count=1,
)

path.write_text(text, encoding="utf-8")
PY
fi
