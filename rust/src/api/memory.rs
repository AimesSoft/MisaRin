#[flutter_rust_bridge::frb(sync)]
pub fn allocate_pixel_buffer(size: i32) -> usize {
    if size <= 0 {
        return 0;
    }
    let len: usize = match usize::try_from(size) {
        Ok(v) => v,
        Err(_) => return 0,
    };

    let mut pixels: Vec<u32> = Vec::new();
    if pixels.try_reserve_exact(len).is_err() {
        return 0;
    }
    pixels.resize(len, 0);

    let boxed: Box<[u32]> = pixels.into_boxed_slice();
    let ptr = Box::into_raw(boxed) as *mut u32;
    ptr as usize
}

#[flutter_rust_bridge::frb(sync)]
pub fn free_pixel_buffer(ptr: usize, size: i32) {
    if ptr == 0 || size <= 0 {
        return;
    }
    let len: usize = match usize::try_from(size) {
        Ok(v) => v,
        Err(_) => return,
    };

    unsafe {
        let slice_ptr = std::ptr::slice_from_raw_parts_mut(ptr as *mut u32, len);
        drop(Box::from_raw(slice_ptr));
    }
}

#[flutter_rust_bridge::frb(ignore)]
#[no_mangle]
pub extern "C" fn misarin_alloc_pixel_buffer(len: usize) -> *mut u32 {
    if len == 0 {
        return std::ptr::null_mut();
    }
    let mut pixels: Vec<u32> = Vec::new();
    if pixels.try_reserve_exact(len).is_err() {
        return std::ptr::null_mut();
    }
    pixels.resize(len, 0);
    let boxed: Box<[u32]> = pixels.into_boxed_slice();
    Box::into_raw(boxed) as *mut u32
}

#[flutter_rust_bridge::frb(ignore)]
#[no_mangle]
pub extern "C" fn misarin_free_pixel_buffer(ptr: *mut u32, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    unsafe {
        let slice_ptr = std::ptr::slice_from_raw_parts_mut(ptr, len);
        drop(Box::from_raw(slice_ptr));
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn read_pixel_at(ptr: usize, index: i32) -> u32 {
    if ptr == 0 || index < 0 {
        return 0;
    }
    unsafe { *(ptr as *const u32).add(index as usize) }
}
