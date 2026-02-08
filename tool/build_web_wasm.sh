#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_DIR="$ROOT_DIR/rust"
OUT_DIR="$ROOT_DIR/web/pkg"
CRATE_NAME="rust_lib_misa_rin"

mkdir -p "$OUT_DIR"

export RUSTFLAGS="${RUSTFLAGS:--C target-feature=+atomics,+bulk-memory,+mutable-globals}"

cargo build \
  --manifest-path "$RUST_DIR/Cargo.toml" \
  --target wasm32-unknown-unknown \
  --release

wasm-bindgen \
  "$RUST_DIR/target/wasm32-unknown-unknown/release/${CRATE_NAME}.wasm" \
  --out-dir "$OUT_DIR" \
  --no-typescript \
  --target no-modules \
  --out-name "$CRATE_NAME"
