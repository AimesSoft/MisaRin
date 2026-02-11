mod ffi;
mod types;

#[cfg(any(target_os = "macos", target_os = "windows", target_family = "wasm"))]
mod engine;
#[cfg(any(target_os = "macos", target_os = "windows", target_family = "wasm"))]
mod layers;
#[cfg(any(target_os = "macos", target_os = "windows", target_family = "wasm"))]
mod present;
#[cfg(any(target_os = "macos", target_os = "windows", target_family = "wasm"))]
mod preview;
#[cfg(any(target_os = "macos", target_os = "windows", target_family = "wasm"))]
mod stroke;
#[cfg(any(target_os = "macos", target_os = "windows", target_family = "wasm"))]
mod transform;
#[cfg(any(target_os = "macos", target_os = "windows", target_family = "wasm"))]
mod undo;

#[cfg(target_family = "wasm")]
mod web;
