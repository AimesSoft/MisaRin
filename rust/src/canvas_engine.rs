pub mod ffi;
mod types;

#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios", target_os = "android"))]
mod engine;
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios", target_os = "android"))]
mod layers;
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios", target_os = "android"))]
mod present;
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios", target_os = "android"))]
mod preview;
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios", target_os = "android"))]
mod stroke;
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios", target_os = "android"))]
mod transform;
#[cfg(any(target_os = "macos", target_os = "windows", target_os = "ios", target_os = "android"))]
mod undo;
