#![cfg_attr(target_family = "wasm", feature(thread_local))]

pub mod api;
mod canvas_engine;
mod frb_generated;
mod gpu;
#[cfg(target_family = "wasm")]
mod wasm_tls;
