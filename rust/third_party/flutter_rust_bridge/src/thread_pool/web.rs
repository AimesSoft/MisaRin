pub use crate::third_party::wasm_bindgen::worker_pool::WorkerPool as SimpleThreadPool;
use crate::web_transfer::transfer_closure::TransferClosure;
use std::thread::LocalKey;
use wasm_bindgen::JsValue;

pub trait BaseThreadPool {
    fn execute(&self, closure: TransferClosure<JsValue>);
}

impl BaseThreadPool for &'static LocalKey<SimpleThreadPool> {
    fn execute(&self, closure: TransferClosure<JsValue>) {
        #[cfg(target_feature = "atomics")]
        {
            self.with(|inner| inner.execute(closure)).unwrap()
        }
        #[cfg(not(target_feature = "atomics"))]
        {
            let TransferClosure { data, closure, .. } = closure;
            (closure)(&data);
        }
    }
}
