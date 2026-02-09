#[cfg(target_family = "wasm")]
pub(crate) fn wasm_post_log(message: &str) {
    use wasm_bindgen::JsCast;
    use wasm_bindgen::JsValue;
    let global = js_sys::global();
    let fetch = js_sys::Reflect::get(&global, &JsValue::from_str("fetch"));
    if let Ok(fetch) = fetch {
        if let Ok(fetch_fn) = fetch.dyn_into::<js_sys::Function>() {
            let init = js_sys::Object::new();
            let _ = js_sys::Reflect::set(
                &init,
                &JsValue::from_str("method"),
                &JsValue::from_str("POST"),
            );
            let _ = js_sys::Reflect::set(
                &init,
                &JsValue::from_str("body"),
                &JsValue::from_str(message),
            );
            let init_val = JsValue::from(init);
            let _ = fetch_fn.call2(
                &JsValue::NULL,
                &JsValue::from_str("/__log"),
                &init_val,
            );
        }
    }
}

#[cfg(not(target_family = "wasm"))]
pub(crate) fn wasm_post_log(_message: &str) {}
