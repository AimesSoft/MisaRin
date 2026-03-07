#![allow(non_snake_case)]

#[cfg(target_os = "android")]
use crate::canvas_engine::ffi::{
    engine_attach_present_surface, engine_create, engine_dispose, engine_reset_canvas_with_layers,
    engine_resize_canvas, engine_set_log_level,
};
#[cfg(target_os = "android")]
use jni_sys::{jboolean, jclass, jint, jlong, jobject, JNIEnv, JNI_FALSE, JNI_TRUE};
#[cfg(target_os = "android")]
use ndk_sys::ANativeWindow;
#[cfg(target_os = "android")]
use std::ffi::c_void;

#[cfg(target_os = "android")]
#[link(name = "android")]
extern "C" {
    fn ANativeWindow_fromSurface(env: *mut JNIEnv, surface: jobject) -> *mut ANativeWindow;
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_rust_1lib_1misa_1rin_RustLibMisaRinPlugin_nativeEngineCreate(
    _env: *mut JNIEnv,
    _class: jclass,
    width: jint,
    height: jint,
) -> jlong {
    engine_create(width as u32, height as u32) as jlong
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_rust_1lib_1misa_1rin_RustLibMisaRinPlugin_nativeEngineResize(
    _env: *mut JNIEnv,
    _class: jclass,
    handle: jlong,
    width: jint,
    height: jint,
    layer_count: jint,
    background_color_argb: jint,
) -> jboolean {
    if handle == 0 || width <= 0 || height <= 0 {
        return JNI_FALSE;
    }
    let ok = engine_resize_canvas(
        handle as u64,
        width as u32,
        height as u32,
        layer_count.max(1) as u32,
        background_color_argb as u32,
    );
    if ok != 0 {
        JNI_TRUE
    } else {
        JNI_FALSE
    }
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_rust_1lib_1misa_1rin_RustLibMisaRinPlugin_nativeEngineResetCanvasWithLayers(
    _env: *mut JNIEnv,
    _class: jclass,
    handle: jlong,
    layer_count: jint,
    background_color_argb: jint,
) {
    if handle == 0 {
        return;
    }
    engine_reset_canvas_with_layers(
        handle as u64,
        layer_count.max(1) as u32,
        background_color_argb as u32,
    );
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_rust_1lib_1misa_1rin_RustLibMisaRinPlugin_nativeEngineDispose(
    _env: *mut JNIEnv,
    _class: jclass,
    handle: jlong,
) {
    if handle == 0 {
        return;
    }
    engine_dispose(handle as u64);
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_rust_1lib_1misa_1rin_RustLibMisaRinPlugin_nativeEngineAttachSurface(
    env: *mut JNIEnv,
    _class: jclass,
    handle: jlong,
    surface: jobject,
    width: jint,
    height: jint,
) -> jboolean {
    if handle == 0 || surface.is_null() || width <= 0 || height <= 0 {
        return JNI_FALSE;
    }
    let window = unsafe { ANativeWindow_fromSurface(env, surface) };
    if window.is_null() {
        return JNI_FALSE;
    }
    engine_attach_present_surface(
        handle as u64,
        window as *mut c_void,
        width as u32,
        height as u32,
    );
    JNI_TRUE
}

#[cfg(target_os = "android")]
#[no_mangle]
pub extern "system" fn Java_com_flutter_1rust_1bridge_rust_1lib_1misa_1rin_RustLibMisaRinPlugin_nativeEngineSetLogLevel(
    _env: *mut JNIEnv,
    _class: jclass,
    level: jint,
) {
    if level < 0 {
        return;
    }
    engine_set_log_level(level as u32);
}
