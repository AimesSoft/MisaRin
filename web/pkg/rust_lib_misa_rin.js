let wasm_bindgen;
(function() {
    const __exports = {};
    let script_src;
    if (typeof document !== 'undefined' && document.currentScript !== null) {
        script_src = new URL(document.currentScript.src, location.href).toString();
    }
    let wasm = undefined;

    function addToExternrefTable0(obj) {
        const idx = wasm.__externref_table_alloc();
        wasm.__wbindgen_externrefs.set(idx, obj);
        return idx;
    }

    const CLOSURE_DTORS = (typeof FinalizationRegistry === 'undefined')
        ? { register: () => {}, unregister: () => {} }
        : new FinalizationRegistry(state => state.dtor(state.a, state.b));

    function debugString(val) {
        // primitive types
        const type = typeof val;
        if (type == 'number' || type == 'boolean' || val == null) {
            return  `${val}`;
        }
        if (type == 'string') {
            return `"${val}"`;
        }
        if (type == 'symbol') {
            const description = val.description;
            if (description == null) {
                return 'Symbol';
            } else {
                return `Symbol(${description})`;
            }
        }
        if (type == 'function') {
            const name = val.name;
            if (typeof name == 'string' && name.length > 0) {
                return `Function(${name})`;
            } else {
                return 'Function';
            }
        }
        // objects
        if (Array.isArray(val)) {
            const length = val.length;
            let debug = '[';
            if (length > 0) {
                debug += debugString(val[0]);
            }
            for(let i = 1; i < length; i++) {
                debug += ', ' + debugString(val[i]);
            }
            debug += ']';
            return debug;
        }
        // Test for built-in
        const builtInMatches = /\[object ([^\]]+)\]/.exec(toString.call(val));
        let className;
        if (builtInMatches && builtInMatches.length > 1) {
            className = builtInMatches[1];
        } else {
            // Failed to match the standard '[object ClassName]'
            return toString.call(val);
        }
        if (className == 'Object') {
            // we're a user defined class or Object
            // JSON.stringify avoids problems with cycles, and is generally much
            // easier than looping through ownProperties of `val`.
            try {
                return 'Object(' + JSON.stringify(val) + ')';
            } catch (_) {
                return 'Object';
            }
        }
        // errors
        if (val instanceof Error) {
            return `${val.name}: ${val.message}\n${val.stack}`;
        }
        // TODO we could test for more things here, like `Set`s and `Map`s.
        return className;
    }

    function getArrayU32FromWasm0(ptr, len) {
        ptr = ptr >>> 0;
        return getUint32ArrayMemory0().subarray(ptr / 4, ptr / 4 + len);
    }

    function getArrayU8FromWasm0(ptr, len) {
        ptr = ptr >>> 0;
        return getUint8ArrayMemory0().subarray(ptr / 1, ptr / 1 + len);
    }

    let cachedDataViewMemory0 = null;
    function getDataViewMemory0() {
        if (cachedDataViewMemory0 === null || cachedDataViewMemory0.buffer.detached === true || (cachedDataViewMemory0.buffer.detached === undefined && cachedDataViewMemory0.buffer !== wasm.memory.buffer)) {
            cachedDataViewMemory0 = new DataView(wasm.memory.buffer);
        }
        return cachedDataViewMemory0;
    }

    function getStringFromWasm0(ptr, len) {
        ptr = ptr >>> 0;
        return decodeText(ptr, len);
    }

    let cachedUint32ArrayMemory0 = null;
    function getUint32ArrayMemory0() {
        if (cachedUint32ArrayMemory0 === null || cachedUint32ArrayMemory0.byteLength === 0) {
            cachedUint32ArrayMemory0 = new Uint32Array(wasm.memory.buffer);
        }
        return cachedUint32ArrayMemory0;
    }

    let cachedUint8ArrayMemory0 = null;
    function getUint8ArrayMemory0() {
        if (cachedUint8ArrayMemory0 === null || cachedUint8ArrayMemory0.byteLength === 0) {
            cachedUint8ArrayMemory0 = new Uint8Array(wasm.memory.buffer);
        }
        return cachedUint8ArrayMemory0;
    }

    function handleError(f, args) {
        try {
            return f.apply(this, args);
        } catch (e) {
            const idx = addToExternrefTable0(e);
            wasm.__wbindgen_exn_store(idx);
        }
    }

    function isLikeNone(x) {
        return x === undefined || x === null;
    }

    function makeMutClosure(arg0, arg1, dtor, f) {
        const state = { a: arg0, b: arg1, cnt: 1, dtor };
        const real = (...args) => {

            // First up with a closure we increment the internal reference
            // count. This ensures that the Rust closure environment won't
            // be deallocated while we're invoking it.
            state.cnt++;
            const a = state.a;
            state.a = 0;
            try {
                return f(a, state.b, ...args);
            } finally {
                state.a = a;
                real._wbg_cb_unref();
            }
        };
        real._wbg_cb_unref = () => {
            if (--state.cnt === 0) {
                state.dtor(state.a, state.b);
                state.a = 0;
                CLOSURE_DTORS.unregister(state);
            }
        };
        CLOSURE_DTORS.register(real, state, state);
        return real;
    }

    function passArrayJsValueToWasm0(array, malloc) {
        const ptr = malloc(array.length * 4, 4) >>> 0;
        for (let i = 0; i < array.length; i++) {
            const add = addToExternrefTable0(array[i]);
            getDataViewMemory0().setUint32(ptr + 4 * i, add, true);
        }
        WASM_VECTOR_LEN = array.length;
        return ptr;
    }

    function passStringToWasm0(arg, malloc, realloc) {
        if (realloc === undefined) {
            const buf = cachedTextEncoder.encode(arg);
            const ptr = malloc(buf.length, 1) >>> 0;
            getUint8ArrayMemory0().subarray(ptr, ptr + buf.length).set(buf);
            WASM_VECTOR_LEN = buf.length;
            return ptr;
        }

        let len = arg.length;
        let ptr = malloc(len, 1) >>> 0;

        const mem = getUint8ArrayMemory0();

        let offset = 0;

        for (; offset < len; offset++) {
            const code = arg.charCodeAt(offset);
            if (code > 0x7F) break;
            mem[ptr + offset] = code;
        }
        if (offset !== len) {
            if (offset !== 0) {
                arg = arg.slice(offset);
            }
            ptr = realloc(ptr, len, len = offset + arg.length * 3, 1) >>> 0;
            const view = getUint8ArrayMemory0().subarray(ptr + offset, ptr + len);
            const ret = cachedTextEncoder.encodeInto(arg, view);

            offset += ret.written;
            ptr = realloc(ptr, len, offset, 1) >>> 0;
        }

        WASM_VECTOR_LEN = offset;
        return ptr;
    }

    function takeFromExternrefTable0(idx) {
        const value = wasm.__wbindgen_externrefs.get(idx);
        wasm.__externref_table_dealloc(idx);
        return value;
    }

    let cachedTextDecoder = new TextDecoder('utf-8', { ignoreBOM: true, fatal: true });
    cachedTextDecoder.decode();
    function decodeText(ptr, len) {
        return cachedTextDecoder.decode(getUint8ArrayMemory0().subarray(ptr, ptr + len));
    }

    const cachedTextEncoder = new TextEncoder();

    if (!('encodeInto' in cachedTextEncoder)) {
        cachedTextEncoder.encodeInto = function (arg, view) {
            const buf = cachedTextEncoder.encode(arg);
            view.set(buf);
            return {
                read: arg.length,
                written: buf.length
            };
        }
    }

    let WASM_VECTOR_LEN = 0;

    function wasm_bindgen__convert__closures_____invoke__h119c2947e629332d(arg0, arg1, arg2) {
        wasm.wasm_bindgen__convert__closures_____invoke__h119c2947e629332d(arg0, arg1, arg2);
    }

    function wasm_bindgen__convert__closures_____invoke__h4d8af106a31f3a7a(arg0, arg1, arg2) {
        wasm.wasm_bindgen__convert__closures_____invoke__h4d8af106a31f3a7a(arg0, arg1, arg2);
    }

    function wasm_bindgen__convert__closures_____invoke__h35f7619b45dfaf2b(arg0, arg1, arg2) {
        wasm.wasm_bindgen__convert__closures_____invoke__h35f7619b45dfaf2b(arg0, arg1, arg2);
    }

    const __wbindgen_enum_GpuErrorFilter = ["validation", "out-of-memory", "internal"];

    const __wbindgen_enum_GpuIndexFormat = ["uint16", "uint32"];

    const __wbindgen_enum_GpuTextureFormat = ["r8unorm", "r8snorm", "r8uint", "r8sint", "r16uint", "r16sint", "r16float", "rg8unorm", "rg8snorm", "rg8uint", "rg8sint", "r32uint", "r32sint", "r32float", "rg16uint", "rg16sint", "rg16float", "rgba8unorm", "rgba8unorm-srgb", "rgba8snorm", "rgba8uint", "rgba8sint", "bgra8unorm", "bgra8unorm-srgb", "rgb9e5ufloat", "rgb10a2unorm", "rg11b10ufloat", "rg32uint", "rg32sint", "rg32float", "rgba16uint", "rgba16sint", "rgba16float", "rgba32uint", "rgba32sint", "rgba32float", "stencil8", "depth16unorm", "depth24plus", "depth24plus-stencil8", "depth32float", "depth32float-stencil8", "bc1-rgba-unorm", "bc1-rgba-unorm-srgb", "bc2-rgba-unorm", "bc2-rgba-unorm-srgb", "bc3-rgba-unorm", "bc3-rgba-unorm-srgb", "bc4-r-unorm", "bc4-r-snorm", "bc5-rg-unorm", "bc5-rg-snorm", "bc6h-rgb-ufloat", "bc6h-rgb-float", "bc7-rgba-unorm", "bc7-rgba-unorm-srgb", "etc2-rgb8unorm", "etc2-rgb8unorm-srgb", "etc2-rgb8a1unorm", "etc2-rgb8a1unorm-srgb", "etc2-rgba8unorm", "etc2-rgba8unorm-srgb", "eac-r11unorm", "eac-r11snorm", "eac-rg11unorm", "eac-rg11snorm", "astc-4x4-unorm", "astc-4x4-unorm-srgb", "astc-5x4-unorm", "astc-5x4-unorm-srgb", "astc-5x5-unorm", "astc-5x5-unorm-srgb", "astc-6x5-unorm", "astc-6x5-unorm-srgb", "astc-6x6-unorm", "astc-6x6-unorm-srgb", "astc-8x5-unorm", "astc-8x5-unorm-srgb", "astc-8x6-unorm", "astc-8x6-unorm-srgb", "astc-8x8-unorm", "astc-8x8-unorm-srgb", "astc-10x5-unorm", "astc-10x5-unorm-srgb", "astc-10x6-unorm", "astc-10x6-unorm-srgb", "astc-10x8-unorm", "astc-10x8-unorm-srgb", "astc-10x10-unorm", "astc-10x10-unorm-srgb", "astc-12x10-unorm", "astc-12x10-unorm-srgb", "astc-12x12-unorm", "astc-12x12-unorm-srgb"];

    const WorkerPoolFinalization = (typeof FinalizationRegistry === 'undefined')
        ? { register: () => {}, unregister: () => {} }
        : new FinalizationRegistry(ptr => wasm.__wbg_workerpool_free(ptr >>> 0, 1));

    class WorkerPool {
        static __wrap(ptr) {
            ptr = ptr >>> 0;
            const obj = Object.create(WorkerPool.prototype);
            obj.__wbg_ptr = ptr;
            WorkerPoolFinalization.register(obj, obj.__wbg_ptr, obj);
            return obj;
        }
        __destroy_into_raw() {
            const ptr = this.__wbg_ptr;
            this.__wbg_ptr = 0;
            WorkerPoolFinalization.unregister(this);
            return ptr;
        }
        free() {
            const ptr = this.__destroy_into_raw();
            wasm.__wbg_workerpool_free(ptr, 0);
        }
        /**
         * @param {number | null} [initial]
         * @param {string | null} [script_src]
         * @param {string | null} [worker_js_preamble]
         * @returns {WorkerPool}
         */
        static new(initial, script_src, worker_js_preamble) {
            var ptr0 = isLikeNone(script_src) ? 0 : passStringToWasm0(script_src, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
            var len0 = WASM_VECTOR_LEN;
            var ptr1 = isLikeNone(worker_js_preamble) ? 0 : passStringToWasm0(worker_js_preamble, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
            var len1 = WASM_VECTOR_LEN;
            const ret = wasm.workerpool_new(isLikeNone(initial) ? 0x100000001 : (initial) >>> 0, ptr0, len0, ptr1, len1);
            if (ret[2]) {
                throw takeFromExternrefTable0(ret[1]);
            }
            return WorkerPool.__wrap(ret[0]);
        }
        /**
         * Creates a new `WorkerPool` which immediately creates `initial` workers.
         *
         * The pool created here can be used over a long period of time, and it
         * will be initially primed with `initial` workers. Currently workers are
         * never released or gc'd until the whole pool is destroyed.
         *
         * # Errors
         *
         * Returns any error that may happen while a JS web worker is created and a
         * message is sent to it.
         * @param {number} initial
         * @param {string} script_src
         * @param {string} worker_js_preamble
         */
        constructor(initial, script_src, worker_js_preamble) {
            const ptr0 = passStringToWasm0(script_src, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
            const len0 = WASM_VECTOR_LEN;
            const ptr1 = passStringToWasm0(worker_js_preamble, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
            const len1 = WASM_VECTOR_LEN;
            const ret = wasm.workerpool_new_raw(initial, ptr0, len0, ptr1, len1);
            if (ret[2]) {
                throw takeFromExternrefTable0(ret[1]);
            }
            this.__wbg_ptr = ret[0] >>> 0;
            WorkerPoolFinalization.register(this, this.__wbg_ptr, this);
            return this;
        }
    }
    if (Symbol.dispose) WorkerPool.prototype[Symbol.dispose] = WorkerPool.prototype.free;
    __exports.WorkerPool = WorkerPool;

    /**
     * @param {number} call_id
     * @param {any} ptr_
     * @param {number} rust_vec_len_
     * @param {number} data_len_
     */
    function frb_dart_fn_deliver_output(call_id, ptr_, rust_vec_len_, data_len_) {
        wasm.frb_dart_fn_deliver_output(call_id, ptr_, rust_vec_len_, data_len_);
    }
    __exports.frb_dart_fn_deliver_output = frb_dart_fn_deliver_output;

    /**
     * # Safety
     *
     * This should never be called manually.
     * @param {any} handle
     * @param {any} dart_handler_port
     * @returns {number}
     */
    function frb_dart_opaque_dart2rust_encode(handle, dart_handler_port) {
        const ret = wasm.frb_dart_opaque_dart2rust_encode(handle, dart_handler_port);
        return ret >>> 0;
    }
    __exports.frb_dart_opaque_dart2rust_encode = frb_dart_opaque_dart2rust_encode;

    /**
     * @param {number} ptr
     */
    function frb_dart_opaque_drop_thread_box_persistent_handle(ptr) {
        wasm.frb_dart_opaque_drop_thread_box_persistent_handle(ptr);
    }
    __exports.frb_dart_opaque_drop_thread_box_persistent_handle = frb_dart_opaque_drop_thread_box_persistent_handle;

    /**
     * @param {number} ptr
     * @returns {any}
     */
    function frb_dart_opaque_rust2dart_decode(ptr) {
        const ret = wasm.frb_dart_opaque_rust2dart_decode(ptr);
        return ret;
    }
    __exports.frb_dart_opaque_rust2dart_decode = frb_dart_opaque_rust2dart_decode;

    /**
     * @returns {number}
     */
    function frb_get_rust_content_hash() {
        const ret = wasm.frb_get_rust_content_hash();
        return ret;
    }
    __exports.frb_get_rust_content_hash = frb_get_rust_content_hash;

    /**
     * @param {number} func_id
     * @param {any} port_
     * @param {any} ptr_
     * @param {number} rust_vec_len_
     * @param {number} data_len_
     */
    function frb_pde_ffi_dispatcher_primary(func_id, port_, ptr_, rust_vec_len_, data_len_) {
        wasm.frb_pde_ffi_dispatcher_primary(func_id, port_, ptr_, rust_vec_len_, data_len_);
    }
    __exports.frb_pde_ffi_dispatcher_primary = frb_pde_ffi_dispatcher_primary;

    /**
     * @param {number} func_id
     * @param {any} ptr_
     * @param {number} rust_vec_len_
     * @param {number} data_len_
     * @returns {any}
     */
    function frb_pde_ffi_dispatcher_sync(func_id, ptr_, rust_vec_len_, data_len_) {
        const ret = wasm.frb_pde_ffi_dispatcher_sync(func_id, ptr_, rust_vec_len_, data_len_);
        return ret;
    }
    __exports.frb_pde_ffi_dispatcher_sync = frb_pde_ffi_dispatcher_sync;

    /**
     * ## Safety
     * This function reclaims a raw pointer created by [`TransferClosure`], and therefore
     * should **only** be used in conjunction with it.
     * Furthermore, the WASM module in the worker must have been initialized with the shared
     * memory from the host JS scope.
     * @param {number} payload
     * @param {any[]} transfer
     */
    function receive_transfer_closure(payload, transfer) {
        const ptr0 = passArrayJsValueToWasm0(transfer, wasm.__wbindgen_malloc);
        const len0 = WASM_VECTOR_LEN;
        const ret = wasm.receive_transfer_closure(payload, ptr0, len0);
        if (ret[1]) {
            throw takeFromExternrefTable0(ret[0]);
        }
    }
    __exports.receive_transfer_closure = receive_transfer_closure;

    function wasm_start_callback() {
        wasm.wasm_start_callback();
    }
    __exports.wasm_start_callback = wasm_start_callback;

    const EXPECTED_RESPONSE_TYPES = new Set(['basic', 'cors', 'default']);

    async function __wbg_load(module, imports) {
        if (typeof Response === 'function' && module instanceof Response) {
            if (typeof WebAssembly.instantiateStreaming === 'function') {
                try {
                    return await WebAssembly.instantiateStreaming(module, imports);
                } catch (e) {
                    const validResponse = module.ok && EXPECTED_RESPONSE_TYPES.has(module.type);

                    if (validResponse && module.headers.get('Content-Type') !== 'application/wasm') {
                        console.warn("`WebAssembly.instantiateStreaming` failed because your server does not serve Wasm with `application/wasm` MIME type. Falling back to `WebAssembly.instantiate` which is slower. Original error:\n", e);

                    } else {
                        throw e;
                    }
                }
            }

            const bytes = await module.arrayBuffer();
            return await WebAssembly.instantiate(bytes, imports);
        } else {
            const instance = await WebAssembly.instantiate(module, imports);

            if (instance instanceof WebAssembly.Instance) {
                return { instance, module };
            } else {
                return instance;
            }
        }
    }

    function __wbg_get_imports() {
        const imports = {};
        imports.wbg = {};
        imports.wbg.__wbg_Window_09685c5b35e4318e = function(arg0) {
            const ret = arg0.Window;
            return ret;
        };
        imports.wbg.__wbg_WorkerGlobalScope_86dadc234326361b = function(arg0) {
            const ret = arg0.WorkerGlobalScope;
            return ret;
        };
        imports.wbg.__wbg___wbindgen_debug_string_adfb662ae34724b6 = function(arg0, arg1) {
            const ret = debugString(arg1);
            const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
            const len1 = WASM_VECTOR_LEN;
            getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
            getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
        };
        imports.wbg.__wbg___wbindgen_is_function_8d400b8b1af978cd = function(arg0) {
            const ret = typeof(arg0) === 'function';
            return ret;
        };
        imports.wbg.__wbg___wbindgen_is_object_ce774f3490692386 = function(arg0) {
            const val = arg0;
            const ret = typeof(val) === 'object' && val !== null;
            return ret;
        };
        imports.wbg.__wbg___wbindgen_is_undefined_f6b95eab589e0269 = function(arg0) {
            const ret = arg0 === undefined;
            return ret;
        };
        imports.wbg.__wbg___wbindgen_jsval_eq_b6101cc9cef1fe36 = function(arg0, arg1) {
            const ret = arg0 === arg1;
            return ret;
        };
        imports.wbg.__wbg___wbindgen_memory_a342e963fbcabd68 = function() {
            const ret = wasm.memory;
            return ret;
        };
        imports.wbg.__wbg___wbindgen_module_967adef62ea6cbf8 = function() {
            const ret = __wbg_init.__wbindgen_wasm_module;
            return ret;
        };
        imports.wbg.__wbg___wbindgen_number_get_9619185a74197f95 = function(arg0, arg1) {
            const obj = arg1;
            const ret = typeof(obj) === 'number' ? obj : undefined;
            getDataViewMemory0().setFloat64(arg0 + 8 * 1, isLikeNone(ret) ? 0 : ret, true);
            getDataViewMemory0().setInt32(arg0 + 4 * 0, !isLikeNone(ret), true);
        };
        imports.wbg.__wbg___wbindgen_string_get_a2a31e16edf96e42 = function(arg0, arg1) {
            const obj = arg1;
            const ret = typeof(obj) === 'string' ? obj : undefined;
            var ptr1 = isLikeNone(ret) ? 0 : passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
            var len1 = WASM_VECTOR_LEN;
            getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
            getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
        };
        imports.wbg.__wbg___wbindgen_throw_dd24417ed36fc46e = function(arg0, arg1) {
            throw new Error(getStringFromWasm0(arg0, arg1));
        };
        imports.wbg.__wbg__wbg_cb_unref_87dfb5aaa0cbcea7 = function(arg0) {
            arg0._wbg_cb_unref();
        };
        imports.wbg.__wbg_beginComputePass_1887a662b16709f1 = function(arg0, arg1) {
            const ret = arg0.beginComputePass(arg1);
            return ret;
        };
        imports.wbg.__wbg_beginRenderPass_9179e8717d25fdb0 = function(arg0, arg1) {
            const ret = arg0.beginRenderPass(arg1);
            return ret;
        };
        imports.wbg.__wbg_buffer_6cb2fecb1f253d71 = function(arg0) {
            const ret = arg0.buffer;
            return ret;
        };
        imports.wbg.__wbg_call_abb4ff46ce38be40 = function() { return handleError(function (arg0, arg1) {
            const ret = arg0.call(arg1);
            return ret;
        }, arguments) };
        imports.wbg.__wbg_call_c8baa5c5e72d274e = function() { return handleError(function (arg0, arg1, arg2, arg3) {
            const ret = arg0.call(arg1, arg2, arg3);
            return ret;
        }, arguments) };
        imports.wbg.__wbg_clearBuffer_3cb299d33f9c17aa = function(arg0, arg1, arg2, arg3) {
            arg0.clearBuffer(arg1, arg2, arg3);
        };
        imports.wbg.__wbg_clearBuffer_d1bbfb575de500c2 = function(arg0, arg1, arg2) {
            arg0.clearBuffer(arg1, arg2);
        };
        imports.wbg.__wbg_configure_3545afac230e1d5e = function(arg0, arg1) {
            arg0.configure(arg1);
        };
        imports.wbg.__wbg_copyBufferToBuffer_1339da3175db86a8 = function(arg0, arg1, arg2, arg3, arg4, arg5) {
            arg0.copyBufferToBuffer(arg1, arg2, arg3, arg4, arg5);
        };
        imports.wbg.__wbg_copyBufferToTexture_7fa23729d3a09bc4 = function(arg0, arg1, arg2, arg3) {
            arg0.copyBufferToTexture(arg1, arg2, arg3);
        };
        imports.wbg.__wbg_copyExternalImageToTexture_a7d15aeaa14817c3 = function(arg0, arg1, arg2, arg3) {
            arg0.copyExternalImageToTexture(arg1, arg2, arg3);
        };
        imports.wbg.__wbg_copyTextureToBuffer_10eda2ea3e01a012 = function(arg0, arg1, arg2, arg3) {
            arg0.copyTextureToBuffer(arg1, arg2, arg3);
        };
        imports.wbg.__wbg_copyTextureToTexture_0f32dca08a58f47f = function(arg0, arg1, arg2, arg3) {
            arg0.copyTextureToTexture(arg1, arg2, arg3);
        };
        imports.wbg.__wbg_createBindGroupLayout_274e16d30c603078 = function(arg0, arg1) {
            const ret = arg0.createBindGroupLayout(arg1);
            return ret;
        };
        imports.wbg.__wbg_createBindGroup_a36c90bdc3f5eb88 = function(arg0, arg1) {
            const ret = arg0.createBindGroup(arg1);
            return ret;
        };
        imports.wbg.__wbg_createBuffer_d1ac34725e5cf041 = function(arg0, arg1) {
            const ret = arg0.createBuffer(arg1);
            return ret;
        };
        imports.wbg.__wbg_createCommandEncoder_513a786f096a5637 = function(arg0, arg1) {
            const ret = arg0.createCommandEncoder(arg1);
            return ret;
        };
        imports.wbg.__wbg_createComputePipeline_4bf93ff2c10c2333 = function(arg0, arg1) {
            const ret = arg0.createComputePipeline(arg1);
            return ret;
        };
        imports.wbg.__wbg_createObjectURL_7d9f7f8f41373850 = function() { return handleError(function (arg0, arg1) {
            const ret = URL.createObjectURL(arg1);
            const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
            const len1 = WASM_VECTOR_LEN;
            getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
            getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
        }, arguments) };
        imports.wbg.__wbg_createPipelineLayout_669f14789cde7273 = function(arg0, arg1) {
            const ret = arg0.createPipelineLayout(arg1);
            return ret;
        };
        imports.wbg.__wbg_createQuerySet_7a0251b6c175935a = function(arg0, arg1) {
            const ret = arg0.createQuerySet(arg1);
            return ret;
        };
        imports.wbg.__wbg_createRenderBundleEncoder_2e2d7a61c14a077b = function(arg0, arg1) {
            const ret = arg0.createRenderBundleEncoder(arg1);
            return ret;
        };
        imports.wbg.__wbg_createRenderPipeline_d206a6a989f60069 = function(arg0, arg1) {
            const ret = arg0.createRenderPipeline(arg1);
            return ret;
        };
        imports.wbg.__wbg_createSampler_21641deec0b72234 = function(arg0, arg1) {
            const ret = arg0.createSampler(arg1);
            return ret;
        };
        imports.wbg.__wbg_createShaderModule_6a4726ff8937a4fc = function(arg0, arg1) {
            const ret = arg0.createShaderModule(arg1);
            return ret;
        };
        imports.wbg.__wbg_createTexture_b4736ca67c208a7d = function(arg0, arg1) {
            const ret = arg0.createTexture(arg1);
            return ret;
        };
        imports.wbg.__wbg_createView_28f72f1fbf41c53a = function(arg0, arg1) {
            const ret = arg0.createView(arg1);
            return ret;
        };
        imports.wbg.__wbg_data_8bf4ae669a78a688 = function(arg0) {
            const ret = arg0.data;
            return ret;
        };
        imports.wbg.__wbg_destroy_24dc0325ca73bcdd = function(arg0) {
            arg0.destroy();
        };
        imports.wbg.__wbg_destroy_35ef3fac72adebbd = function(arg0) {
            arg0.destroy();
        };
        imports.wbg.__wbg_destroy_6ca164ec39708c30 = function(arg0) {
            arg0.destroy();
        };
        imports.wbg.__wbg_dispatchWorkgroupsIndirect_5b70aa0ec2dd76d4 = function(arg0, arg1, arg2) {
            arg0.dispatchWorkgroupsIndirect(arg1, arg2);
        };
        imports.wbg.__wbg_dispatchWorkgroups_eec2b1c97a77f008 = function(arg0, arg1, arg2, arg3) {
            arg0.dispatchWorkgroups(arg1 >>> 0, arg2 >>> 0, arg3 >>> 0);
        };
        imports.wbg.__wbg_document_5b745e82ba551ca5 = function(arg0) {
            const ret = arg0.document;
            return isLikeNone(ret) ? 0 : addToExternrefTable0(ret);
        };
        imports.wbg.__wbg_drawIndexedIndirect_7195bed12006fc7e = function(arg0, arg1, arg2) {
            arg0.drawIndexedIndirect(arg1, arg2);
        };
        imports.wbg.__wbg_drawIndexedIndirect_cb0d6da766bd5105 = function(arg0, arg1, arg2) {
            arg0.drawIndexedIndirect(arg1, arg2);
        };
        imports.wbg.__wbg_drawIndexed_6d903b1382862f81 = function(arg0, arg1, arg2, arg3, arg4, arg5) {
            arg0.drawIndexed(arg1 >>> 0, arg2 >>> 0, arg3 >>> 0, arg4, arg5 >>> 0);
        };
        imports.wbg.__wbg_drawIndexed_c122c36f03fe07a5 = function(arg0, arg1, arg2, arg3, arg4, arg5) {
            arg0.drawIndexed(arg1 >>> 0, arg2 >>> 0, arg3 >>> 0, arg4, arg5 >>> 0);
        };
        imports.wbg.__wbg_drawIndirect_9aab8bee6f6f1c22 = function(arg0, arg1, arg2) {
            arg0.drawIndirect(arg1, arg2);
        };
        imports.wbg.__wbg_drawIndirect_d531975704a856b7 = function(arg0, arg1, arg2) {
            arg0.drawIndirect(arg1, arg2);
        };
        imports.wbg.__wbg_draw_19d537d9832d985d = function(arg0, arg1, arg2, arg3, arg4) {
            arg0.draw(arg1 >>> 0, arg2 >>> 0, arg3 >>> 0, arg4 >>> 0);
        };
        imports.wbg.__wbg_draw_5beb2c11da5429ce = function(arg0, arg1, arg2, arg3, arg4) {
            arg0.draw(arg1 >>> 0, arg2 >>> 0, arg3 >>> 0, arg4 >>> 0);
        };
        imports.wbg.__wbg_end_2dc6d7fdcbfc2a0c = function(arg0) {
            arg0.end();
        };
        imports.wbg.__wbg_end_9cc33f189e27f3fd = function(arg0) {
            arg0.end();
        };
        imports.wbg.__wbg_error_076d4beefd7cfd14 = function(arg0, arg1) {
            console.error(getStringFromWasm0(arg0, arg1));
        };
        imports.wbg.__wbg_error_15b28e2be7953dc9 = function(arg0) {
            const ret = arg0.error;
            return ret;
        };
        imports.wbg.__wbg_error_7534b8e9a36f1ab4 = function(arg0, arg1) {
            let deferred0_0;
            let deferred0_1;
            try {
                deferred0_0 = arg0;
                deferred0_1 = arg1;
                console.error(getStringFromWasm0(arg0, arg1));
            } finally {
                wasm.__wbindgen_free(deferred0_0, deferred0_1, 1);
            }
        };
        imports.wbg.__wbg_eval_aa18aa048f37d16d = function() { return handleError(function (arg0, arg1) {
            const ret = eval(getStringFromWasm0(arg0, arg1));
            return ret;
        }, arguments) };
        imports.wbg.__wbg_executeBundles_db3c31afbf86979f = function(arg0, arg1) {
            arg0.executeBundles(arg1);
        };
        imports.wbg.__wbg_features_89059e3112366930 = function(arg0) {
            const ret = arg0.features;
            return ret;
        };
        imports.wbg.__wbg_features_e8442c6e37f8191e = function(arg0) {
            const ret = arg0.features;
            return ret;
        };
        imports.wbg.__wbg_finish_53e6ed746110a5e5 = function(arg0) {
            const ret = arg0.finish();
            return ret;
        };
        imports.wbg.__wbg_finish_566e5beaeaeefc34 = function(arg0, arg1) {
            const ret = arg0.finish(arg1);
            return ret;
        };
        imports.wbg.__wbg_finish_a9c9f3133e6e4514 = function(arg0, arg1) {
            const ret = arg0.finish(arg1);
            return ret;
        };
        imports.wbg.__wbg_finish_e2465079e2b30a5a = function(arg0) {
            const ret = arg0.finish();
            return ret;
        };
        imports.wbg.__wbg_getBindGroupLayout_06526a0d3d5b4c6a = function(arg0, arg1) {
            const ret = arg0.getBindGroupLayout(arg1 >>> 0);
            return ret;
        };
        imports.wbg.__wbg_getBindGroupLayout_0f99651172cbcabf = function(arg0, arg1) {
            const ret = arg0.getBindGroupLayout(arg1 >>> 0);
            return ret;
        };
        imports.wbg.__wbg_getContext_01f42b234e833f0a = function() { return handleError(function (arg0, arg1, arg2) {
            const ret = arg0.getContext(getStringFromWasm0(arg1, arg2));
            return isLikeNone(ret) ? 0 : addToExternrefTable0(ret);
        }, arguments) };
        imports.wbg.__wbg_getContext_2f210d0a58d43d95 = function() { return handleError(function (arg0, arg1, arg2) {
            const ret = arg0.getContext(getStringFromWasm0(arg1, arg2));
            return isLikeNone(ret) ? 0 : addToExternrefTable0(ret);
        }, arguments) };
        imports.wbg.__wbg_getCurrentTexture_f578d59f0860dcc9 = function(arg0) {
            const ret = arg0.getCurrentTexture();
            return ret;
        };
        imports.wbg.__wbg_getMappedRange_1a67a729fca25c5c = function(arg0, arg1, arg2) {
            const ret = arg0.getMappedRange(arg1, arg2);
            return ret;
        };
        imports.wbg.__wbg_getPreferredCanvasFormat_b4306c1470f3a2be = function(arg0) {
            const ret = arg0.getPreferredCanvasFormat();
            return (__wbindgen_enum_GpuTextureFormat.indexOf(ret) + 1 || 95) - 1;
        };
        imports.wbg.__wbg_get_af9dab7e9603ea93 = function() { return handleError(function (arg0, arg1) {
            const ret = Reflect.get(arg0, arg1);
            return ret;
        }, arguments) };
        imports.wbg.__wbg_get_c53d381635aa3929 = function(arg0, arg1) {
            const ret = arg0[arg1 >>> 0];
            return isLikeNone(ret) ? 0 : addToExternrefTable0(ret);
        };
        imports.wbg.__wbg_gpu_cd94e3ed1a24e829 = function(arg0) {
            const ret = arg0.gpu;
            return ret;
        };
        imports.wbg.__wbg_has_8d7562409899ab08 = function(arg0, arg1, arg2) {
            const ret = arg0.has(getStringFromWasm0(arg1, arg2));
            return ret;
        };
        imports.wbg.__wbg_instanceof_BroadcastChannel_20b7abd1aa1b1ce9 = function(arg0) {
            let result;
            try {
                result = arg0 instanceof BroadcastChannel;
            } catch (_) {
                result = false;
            }
            const ret = result;
            return ret;
        };
        imports.wbg.__wbg_instanceof_ErrorEvent_395a0232f8587b08 = function(arg0) {
            let result;
            try {
                result = arg0 instanceof ErrorEvent;
            } catch (_) {
                result = false;
            }
            const ret = result;
            return ret;
        };
        imports.wbg.__wbg_instanceof_GpuAdapter_812393144f747a28 = function(arg0) {
            let result;
            try {
                result = arg0 instanceof GPUAdapter;
            } catch (_) {
                result = false;
            }
            const ret = result;
            return ret;
        };
        imports.wbg.__wbg_instanceof_GpuCanvasContext_7d8c2aee896960ef = function(arg0) {
            let result;
            try {
                result = arg0 instanceof GPUCanvasContext;
            } catch (_) {
                result = false;
            }
            const ret = result;
            return ret;
        };
        imports.wbg.__wbg_instanceof_GpuOutOfMemoryError_5661073b28c982a3 = function(arg0) {
            let result;
            try {
                result = arg0 instanceof GPUOutOfMemoryError;
            } catch (_) {
                result = false;
            }
            const ret = result;
            return ret;
        };
        imports.wbg.__wbg_instanceof_GpuValidationError_b2b2abc70da536b4 = function(arg0) {
            let result;
            try {
                result = arg0 instanceof GPUValidationError;
            } catch (_) {
                result = false;
            }
            const ret = result;
            return ret;
        };
        imports.wbg.__wbg_instanceof_MessageEvent_41de26e7cb8539ce = function(arg0) {
            let result;
            try {
                result = arg0 instanceof MessageEvent;
            } catch (_) {
                result = false;
            }
            const ret = result;
            return ret;
        };
        imports.wbg.__wbg_instanceof_MessagePort_c6d647a8cffdd1a6 = function(arg0) {
            let result;
            try {
                result = arg0 instanceof MessagePort;
            } catch (_) {
                result = false;
            }
            const ret = result;
            return ret;
        };
        imports.wbg.__wbg_instanceof_Object_577e21051f7bcb79 = function(arg0) {
            let result;
            try {
                result = arg0 instanceof Object;
            } catch (_) {
                result = false;
            }
            const ret = result;
            return ret;
        };
        imports.wbg.__wbg_instanceof_Window_b5cf7783caa68180 = function(arg0) {
            let result;
            try {
                result = arg0 instanceof Window;
            } catch (_) {
                result = false;
            }
            const ret = result;
            return ret;
        };
        imports.wbg.__wbg_label_ddec9d5dff390794 = function(arg0, arg1) {
            const ret = arg1.label;
            const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
            const len1 = WASM_VECTOR_LEN;
            getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
            getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
        };
        imports.wbg.__wbg_length_22ac23eaec9d8053 = function(arg0) {
            const ret = arg0.length;
            return ret;
        };
        imports.wbg.__wbg_limits_100c065725b263d3 = function(arg0) {
            const ret = arg0.limits;
            return ret;
        };
        imports.wbg.__wbg_limits_adf0926aa155a224 = function(arg0) {
            const ret = arg0.limits;
            return ret;
        };
        imports.wbg.__wbg_log_026e3009324431bf = function(arg0, arg1) {
            console.log(getStringFromWasm0(arg0, arg1));
        };
        imports.wbg.__wbg_mapAsync_9cae92e6e45c9c69 = function(arg0, arg1, arg2, arg3) {
            const ret = arg0.mapAsync(arg1 >>> 0, arg2, arg3);
            return ret;
        };
        imports.wbg.__wbg_maxBindGroups_6f2433803f32568b = function(arg0) {
            const ret = arg0.maxBindGroups;
            return ret;
        };
        imports.wbg.__wbg_maxBindingsPerBindGroup_7663f800ee6c1c4d = function(arg0) {
            const ret = arg0.maxBindingsPerBindGroup;
            return ret;
        };
        imports.wbg.__wbg_maxBufferSize_7c2e7941b31faeb3 = function(arg0) {
            const ret = arg0.maxBufferSize;
            return ret;
        };
        imports.wbg.__wbg_maxComputeInvocationsPerWorkgroup_7706224e284389bb = function(arg0) {
            const ret = arg0.maxComputeInvocationsPerWorkgroup;
            return ret;
        };
        imports.wbg.__wbg_maxComputeWorkgroupSizeX_7c0caad69a9b0dd3 = function(arg0) {
            const ret = arg0.maxComputeWorkgroupSizeX;
            return ret;
        };
        imports.wbg.__wbg_maxComputeWorkgroupSizeY_add60ae79eceba95 = function(arg0) {
            const ret = arg0.maxComputeWorkgroupSizeY;
            return ret;
        };
        imports.wbg.__wbg_maxComputeWorkgroupSizeZ_b0d9e8bb90139e66 = function(arg0) {
            const ret = arg0.maxComputeWorkgroupSizeZ;
            return ret;
        };
        imports.wbg.__wbg_maxComputeWorkgroupStorageSize_bcc6c568b706b004 = function(arg0) {
            const ret = arg0.maxComputeWorkgroupStorageSize;
            return ret;
        };
        imports.wbg.__wbg_maxComputeWorkgroupsPerDimension_05c9e479d4805640 = function(arg0) {
            const ret = arg0.maxComputeWorkgroupsPerDimension;
            return ret;
        };
        imports.wbg.__wbg_maxDynamicStorageBuffersPerPipelineLayout_4017c7b096806162 = function(arg0) {
            const ret = arg0.maxDynamicStorageBuffersPerPipelineLayout;
            return ret;
        };
        imports.wbg.__wbg_maxDynamicUniformBuffersPerPipelineLayout_1d359f3196df8904 = function(arg0) {
            const ret = arg0.maxDynamicUniformBuffersPerPipelineLayout;
            return ret;
        };
        imports.wbg.__wbg_maxInterStageShaderComponents_d0d88326cf30e5cc = function(arg0) {
            const ret = arg0.maxInterStageShaderComponents;
            return ret;
        };
        imports.wbg.__wbg_maxSampledTexturesPerShaderStage_5ad571f210127408 = function(arg0) {
            const ret = arg0.maxSampledTexturesPerShaderStage;
            return ret;
        };
        imports.wbg.__wbg_maxSamplersPerShaderStage_c2ccff8d0f9ec6fd = function(arg0) {
            const ret = arg0.maxSamplersPerShaderStage;
            return ret;
        };
        imports.wbg.__wbg_maxStorageBufferBindingSize_7c16519c2edc067a = function(arg0) {
            const ret = arg0.maxStorageBufferBindingSize;
            return ret;
        };
        imports.wbg.__wbg_maxStorageBuffersPerShaderStage_e8eff366756ea9b4 = function(arg0) {
            const ret = arg0.maxStorageBuffersPerShaderStage;
            return ret;
        };
        imports.wbg.__wbg_maxStorageTexturesPerShaderStage_4e1d793c1e5c72a2 = function(arg0) {
            const ret = arg0.maxStorageTexturesPerShaderStage;
            return ret;
        };
        imports.wbg.__wbg_maxTextureArrayLayers_185872b43f6c8c34 = function(arg0) {
            const ret = arg0.maxTextureArrayLayers;
            return ret;
        };
        imports.wbg.__wbg_maxTextureDimension1D_bfa55b0304281516 = function(arg0) {
            const ret = arg0.maxTextureDimension1D;
            return ret;
        };
        imports.wbg.__wbg_maxTextureDimension2D_ffea95d029cf185b = function(arg0) {
            const ret = arg0.maxTextureDimension2D;
            return ret;
        };
        imports.wbg.__wbg_maxTextureDimension3D_bdfbc27d985f367d = function(arg0) {
            const ret = arg0.maxTextureDimension3D;
            return ret;
        };
        imports.wbg.__wbg_maxUniformBufferBindingSize_01703051a2b68aaa = function(arg0) {
            const ret = arg0.maxUniformBufferBindingSize;
            return ret;
        };
        imports.wbg.__wbg_maxUniformBuffersPerShaderStage_9f2d18a988fa37a0 = function(arg0) {
            const ret = arg0.maxUniformBuffersPerShaderStage;
            return ret;
        };
        imports.wbg.__wbg_maxVertexAttributes_268db19855a9a8bf = function(arg0) {
            const ret = arg0.maxVertexAttributes;
            return ret;
        };
        imports.wbg.__wbg_maxVertexBufferArrayStride_cace98777fdc5a4c = function(arg0) {
            const ret = arg0.maxVertexBufferArrayStride;
            return ret;
        };
        imports.wbg.__wbg_maxVertexBuffers_a8169305364fd125 = function(arg0) {
            const ret = arg0.maxVertexBuffers;
            return ret;
        };
        imports.wbg.__wbg_message_0ff7f09380783844 = function(arg0, arg1) {
            const ret = arg1.message;
            const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
            const len1 = WASM_VECTOR_LEN;
            getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
            getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
        };
        imports.wbg.__wbg_message_d8f5eb4a85362e32 = function(arg0, arg1) {
            const ret = arg1.message;
            const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
            const len1 = WASM_VECTOR_LEN;
            getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
            getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
        };
        imports.wbg.__wbg_minStorageBufferOffsetAlignment_b9763b1a342987b2 = function(arg0) {
            const ret = arg0.minStorageBufferOffsetAlignment;
            return ret;
        };
        imports.wbg.__wbg_minUniformBufferOffsetAlignment_dc9a10adad690d13 = function(arg0) {
            const ret = arg0.minUniformBufferOffsetAlignment;
            return ret;
        };
        imports.wbg.__wbg_name_5ac7feee5b67b1f9 = function(arg0, arg1) {
            const ret = arg1.name;
            const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
            const len1 = WASM_VECTOR_LEN;
            getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
            getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
        };
        imports.wbg.__wbg_navigator_11b7299bb7886507 = function(arg0) {
            const ret = arg0.navigator;
            return ret;
        };
        imports.wbg.__wbg_navigator_b49edef831236138 = function(arg0) {
            const ret = arg0.navigator;
            return ret;
        };
        imports.wbg.__wbg_new_1ba21ce319a06297 = function() {
            const ret = new Object();
            return ret;
        };
        imports.wbg.__wbg_new_25f239778d6112b9 = function() {
            const ret = new Array();
            return ret;
        };
        imports.wbg.__wbg_new_53cb1e86c1ef5d2a = function() { return handleError(function (arg0, arg1) {
            const ret = new Worker(getStringFromWasm0(arg0, arg1));
            return ret;
        }, arguments) };
        imports.wbg.__wbg_new_6421f6084cc5bc5a = function(arg0) {
            const ret = new Uint8Array(arg0);
            return ret;
        };
        imports.wbg.__wbg_new_8a6f238a6ece86ea = function() {
            const ret = new Error();
            return ret;
        };
        imports.wbg.__wbg_new_b3dd747604c3c93e = function() { return handleError(function (arg0, arg1) {
            const ret = new BroadcastChannel(getStringFromWasm0(arg0, arg1));
            return ret;
        }, arguments) };
        imports.wbg.__wbg_new_from_slice_f9c22b9153b26992 = function(arg0, arg1) {
            const ret = new Uint8Array(getArrayU8FromWasm0(arg0, arg1));
            return ret;
        };
        imports.wbg.__wbg_new_no_args_cb138f77cf6151ee = function(arg0, arg1) {
            const ret = new Function(getStringFromWasm0(arg0, arg1));
            return ret;
        };
        imports.wbg.__wbg_new_with_blob_sequence_and_options_effa70dbbcafea53 = function() { return handleError(function (arg0, arg1) {
            const ret = new Blob(arg0, arg1);
            return ret;
        }, arguments) };
        imports.wbg.__wbg_new_with_byte_offset_and_length_d85c3da1fd8df149 = function(arg0, arg1, arg2) {
            const ret = new Uint8Array(arg0, arg1 >>> 0, arg2 >>> 0);
            return ret;
        };
        imports.wbg.__wbg_popErrorScope_8a0d0d31c4ddc243 = function(arg0) {
            const ret = arg0.popErrorScope();
            return ret;
        };
        imports.wbg.__wbg_postMessage_07504dbe15265d5c = function() { return handleError(function (arg0, arg1) {
            arg0.postMessage(arg1);
        }, arguments) };
        imports.wbg.__wbg_postMessage_33814d4dc32c2dcf = function() { return handleError(function (arg0, arg1) {
            arg0.postMessage(arg1);
        }, arguments) };
        imports.wbg.__wbg_postMessage_7243f814e0cfb266 = function() { return handleError(function (arg0, arg1) {
            arg0.postMessage(arg1);
        }, arguments) };
        imports.wbg.__wbg_prototypesetcall_dfe9b766cdc1f1fd = function(arg0, arg1, arg2) {
            Uint8Array.prototype.set.call(getArrayU8FromWasm0(arg0, arg1), arg2);
        };
        imports.wbg.__wbg_pushErrorScope_dc8386c8142593b6 = function(arg0, arg1) {
            arg0.pushErrorScope(__wbindgen_enum_GpuErrorFilter[arg1]);
        };
        imports.wbg.__wbg_push_7d9be8f38fc13975 = function(arg0, arg1) {
            const ret = arg0.push(arg1);
            return ret;
        };
        imports.wbg.__wbg_querySelectorAll_aa1048eae18f6f1a = function() { return handleError(function (arg0, arg1, arg2) {
            const ret = arg0.querySelectorAll(getStringFromWasm0(arg1, arg2));
            return ret;
        }, arguments) };
        imports.wbg.__wbg_queueMicrotask_9b549dfce8865860 = function(arg0) {
            const ret = arg0.queueMicrotask;
            return ret;
        };
        imports.wbg.__wbg_queueMicrotask_fca69f5bfad613a5 = function(arg0) {
            queueMicrotask(arg0);
        };
        imports.wbg.__wbg_queue_d083905208ed0dcd = function(arg0) {
            const ret = arg0.queue;
            return ret;
        };
        imports.wbg.__wbg_requestAdapter_629f003011778ce0 = function(arg0, arg1) {
            const ret = arg0.requestAdapter(arg1);
            return ret;
        };
        imports.wbg.__wbg_requestDevice_a420ce594b90ac7c = function(arg0, arg1) {
            const ret = arg0.requestDevice(arg1);
            return ret;
        };
        imports.wbg.__wbg_resolveQuerySet_2fea0e7835fc7df1 = function(arg0, arg1, arg2, arg3, arg4, arg5) {
            arg0.resolveQuerySet(arg1, arg2 >>> 0, arg3 >>> 0, arg4, arg5 >>> 0);
        };
        imports.wbg.__wbg_resolve_fd5bfbaa4ce36e1e = function(arg0) {
            const ret = Promise.resolve(arg0);
            return ret;
        };
        imports.wbg.__wbg_setBindGroup_10139726fa3dd1ea = function(arg0, arg1, arg2) {
            arg0.setBindGroup(arg1 >>> 0, arg2);
        };
        imports.wbg.__wbg_setBindGroup_241675b4c4b8f5ee = function(arg0, arg1, arg2) {
            arg0.setBindGroup(arg1 >>> 0, arg2);
        };
        imports.wbg.__wbg_setBindGroup_9ae27be0638391c7 = function(arg0, arg1, arg2, arg3, arg4, arg5, arg6) {
            arg0.setBindGroup(arg1 >>> 0, arg2, getArrayU32FromWasm0(arg3, arg4), arg5, arg6 >>> 0);
        };
        imports.wbg.__wbg_setBindGroup_a539eeaa822b1981 = function(arg0, arg1, arg2) {
            arg0.setBindGroup(arg1 >>> 0, arg2);
        };
        imports.wbg.__wbg_setBindGroup_db89ccc18c604dc2 = function(arg0, arg1, arg2, arg3, arg4, arg5, arg6) {
            arg0.setBindGroup(arg1 >>> 0, arg2, getArrayU32FromWasm0(arg3, arg4), arg5, arg6 >>> 0);
        };
        imports.wbg.__wbg_setBindGroup_eea1f72247b40846 = function(arg0, arg1, arg2, arg3, arg4, arg5, arg6) {
            arg0.setBindGroup(arg1 >>> 0, arg2, getArrayU32FromWasm0(arg3, arg4), arg5, arg6 >>> 0);
        };
        imports.wbg.__wbg_setBlendConstant_898c0ee36fd7f3d6 = function(arg0, arg1) {
            arg0.setBlendConstant(arg1);
        };
        imports.wbg.__wbg_setIndexBuffer_02484628e4be6ccf = function(arg0, arg1, arg2, arg3) {
            arg0.setIndexBuffer(arg1, __wbindgen_enum_GpuIndexFormat[arg2], arg3);
        };
        imports.wbg.__wbg_setIndexBuffer_4179c9df498ed24f = function(arg0, arg1, arg2, arg3, arg4) {
            arg0.setIndexBuffer(arg1, __wbindgen_enum_GpuIndexFormat[arg2], arg3, arg4);
        };
        imports.wbg.__wbg_setIndexBuffer_6241c40136dfd59c = function(arg0, arg1, arg2, arg3) {
            arg0.setIndexBuffer(arg1, __wbindgen_enum_GpuIndexFormat[arg2], arg3);
        };
        imports.wbg.__wbg_setIndexBuffer_cac1cc97b362a161 = function(arg0, arg1, arg2, arg3, arg4) {
            arg0.setIndexBuffer(arg1, __wbindgen_enum_GpuIndexFormat[arg2], arg3, arg4);
        };
        imports.wbg.__wbg_setPipeline_065423750bbc2601 = function(arg0, arg1) {
            arg0.setPipeline(arg1);
        };
        imports.wbg.__wbg_setPipeline_73d2200820a1b6d7 = function(arg0, arg1) {
            arg0.setPipeline(arg1);
        };
        imports.wbg.__wbg_setPipeline_c41eba60986fbffb = function(arg0, arg1) {
            arg0.setPipeline(arg1);
        };
        imports.wbg.__wbg_setScissorRect_7ad09034bda2ad64 = function(arg0, arg1, arg2, arg3, arg4) {
            arg0.setScissorRect(arg1 >>> 0, arg2 >>> 0, arg3 >>> 0, arg4 >>> 0);
        };
        imports.wbg.__wbg_setStencilReference_2d44258a2b1549df = function(arg0, arg1) {
            arg0.setStencilReference(arg1 >>> 0);
        };
        imports.wbg.__wbg_setVertexBuffer_086ad8f1d3a3528b = function(arg0, arg1, arg2, arg3) {
            arg0.setVertexBuffer(arg1 >>> 0, arg2, arg3);
        };
        imports.wbg.__wbg_setVertexBuffer_130b7f747b752e5d = function(arg0, arg1, arg2, arg3, arg4) {
            arg0.setVertexBuffer(arg1 >>> 0, arg2, arg3, arg4);
        };
        imports.wbg.__wbg_setVertexBuffer_1a126bb7aa133940 = function(arg0, arg1, arg2, arg3, arg4) {
            arg0.setVertexBuffer(arg1 >>> 0, arg2, arg3, arg4);
        };
        imports.wbg.__wbg_setVertexBuffer_56163ae020ef8343 = function(arg0, arg1, arg2, arg3) {
            arg0.setVertexBuffer(arg1 >>> 0, arg2, arg3);
        };
        imports.wbg.__wbg_setViewport_0c26f0a54b53d7e3 = function(arg0, arg1, arg2, arg3, arg4, arg5, arg6) {
            arg0.setViewport(arg1, arg2, arg3, arg4, arg5, arg6);
        };
        imports.wbg.__wbg_set_781438a03c0c3c81 = function() { return handleError(function (arg0, arg1, arg2) {
            const ret = Reflect.set(arg0, arg1, arg2);
            return ret;
        }, arguments) };
        imports.wbg.__wbg_set_bc3a432bdcd60886 = function(arg0, arg1, arg2) {
            arg0.set(arg1, arg2 >>> 0);
        };
        imports.wbg.__wbg_set_height_6f8f8ef4cb40e496 = function(arg0, arg1) {
            arg0.height = arg1 >>> 0;
        };
        imports.wbg.__wbg_set_height_afe09c24165867f7 = function(arg0, arg1) {
            arg0.height = arg1 >>> 0;
        };
        imports.wbg.__wbg_set_onerror_d5671da43c08b208 = function(arg0, arg1) {
            arg0.onerror = arg1;
        };
        imports.wbg.__wbg_set_onmessage_deb94985de696ac7 = function(arg0, arg1) {
            arg0.onmessage = arg1;
        };
        imports.wbg.__wbg_set_onuncapturederror_daf12032b2ca712a = function(arg0, arg1) {
            arg0.onuncapturederror = arg1;
        };
        imports.wbg.__wbg_set_type_7ce650670a34c68f = function(arg0, arg1, arg2) {
            arg0.type = getStringFromWasm0(arg1, arg2);
        };
        imports.wbg.__wbg_set_width_0a22c810f06a5152 = function(arg0, arg1) {
            arg0.width = arg1 >>> 0;
        };
        imports.wbg.__wbg_set_width_7ff7a22c6e9f423e = function(arg0, arg1) {
            arg0.width = arg1 >>> 0;
        };
        imports.wbg.__wbg_size_45c769c019ee354e = function(arg0) {
            const ret = arg0.size;
            return ret;
        };
        imports.wbg.__wbg_stack_0ed75d68575b0f3c = function(arg0, arg1) {
            const ret = arg1.stack;
            const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
            const len1 = WASM_VECTOR_LEN;
            getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
            getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
        };
        imports.wbg.__wbg_static_accessor_GLOBAL_769e6b65d6557335 = function() {
            const ret = typeof global === 'undefined' ? null : global;
            return isLikeNone(ret) ? 0 : addToExternrefTable0(ret);
        };
        imports.wbg.__wbg_static_accessor_GLOBAL_THIS_60cf02db4de8e1c1 = function() {
            const ret = typeof globalThis === 'undefined' ? null : globalThis;
            return isLikeNone(ret) ? 0 : addToExternrefTable0(ret);
        };
        imports.wbg.__wbg_static_accessor_SELF_08f5a74c69739274 = function() {
            const ret = typeof self === 'undefined' ? null : self;
            return isLikeNone(ret) ? 0 : addToExternrefTable0(ret);
        };
        imports.wbg.__wbg_static_accessor_WINDOW_a8924b26aa92d024 = function() {
            const ret = typeof window === 'undefined' ? null : window;
            return isLikeNone(ret) ? 0 : addToExternrefTable0(ret);
        };
        imports.wbg.__wbg_stringify_655a6390e1f5eb6b = function() { return handleError(function (arg0) {
            const ret = JSON.stringify(arg0);
            return ret;
        }, arguments) };
        imports.wbg.__wbg_submit_75592557e0c2141c = function(arg0, arg1) {
            arg0.submit(arg1);
        };
        imports.wbg.__wbg_then_429f7caf1026411d = function(arg0, arg1, arg2) {
            const ret = arg0.then(arg1, arg2);
            return ret;
        };
        imports.wbg.__wbg_then_4f95312d68691235 = function(arg0, arg1) {
            const ret = arg0.then(arg1);
            return ret;
        };
        imports.wbg.__wbg_unmap_662f1210575affe8 = function(arg0) {
            arg0.unmap();
        };
        imports.wbg.__wbg_usage_000523533bad5f06 = function(arg0) {
            const ret = arg0.usage;
            return ret;
        };
        imports.wbg.__wbg_valueOf_663ea9f1ad0d6eda = function(arg0) {
            const ret = arg0.valueOf();
            return ret;
        };
        imports.wbg.__wbg_writeBuffer_c78696d1629b48de = function(arg0, arg1, arg2, arg3, arg4, arg5) {
            arg0.writeBuffer(arg1, arg2, arg3, arg4, arg5);
        };
        imports.wbg.__wbg_writeTexture_91ff88a4044f669a = function(arg0, arg1, arg2, arg3, arg4) {
            arg0.writeTexture(arg1, arg2, arg3, arg4);
        };
        imports.wbg.__wbg_writeTimestamp_a8766c734d6aa8d6 = function(arg0, arg1, arg2) {
            arg0.writeTimestamp(arg1, arg2 >>> 0);
        };
        imports.wbg.__wbindgen_cast_0cb2730462a9d33a = function(arg0, arg1) {
            // Cast intrinsic for `Closure(Closure { dtor_idx: 160, function: Function { arguments: [NamedExternref("Event")], shim_idx: 161, ret: Unit, inner_ret: Some(Unit) }, mutable: true }) -> Externref`.
            const ret = makeMutClosure(arg0, arg1, wasm.wasm_bindgen__closure__destroy__h19f8e30846f9348b, wasm_bindgen__convert__closures_____invoke__h4d8af106a31f3a7a);
            return ret;
        };
        imports.wbg.__wbindgen_cast_2241b6af4c4b2941 = function(arg0, arg1) {
            // Cast intrinsic for `Ref(String) -> Externref`.
            const ret = getStringFromWasm0(arg0, arg1);
            return ret;
        };
        imports.wbg.__wbindgen_cast_4992e0f004b2258f = function(arg0, arg1) {
            // Cast intrinsic for `Closure(Closure { dtor_idx: 401, function: Function { arguments: [Externref], shim_idx: 402, ret: Unit, inner_ret: Some(Unit) }, mutable: true }) -> Externref`.
            const ret = makeMutClosure(arg0, arg1, wasm.wasm_bindgen__closure__destroy__h17587f0b0730f8ea, wasm_bindgen__convert__closures_____invoke__h119c2947e629332d);
            return ret;
        };
        imports.wbg.__wbindgen_cast_cb9088102bce6b30 = function(arg0, arg1) {
            // Cast intrinsic for `Ref(Slice(U8)) -> NamedExternref("Uint8Array")`.
            const ret = getArrayU8FromWasm0(arg0, arg1);
            return ret;
        };
        imports.wbg.__wbindgen_cast_d6cd19b81560fd6e = function(arg0) {
            // Cast intrinsic for `F64 -> Externref`.
            const ret = arg0;
            return ret;
        };
        imports.wbg.__wbindgen_cast_d907915c5f1fa90a = function(arg0, arg1) {
            // Cast intrinsic for `Closure(Closure { dtor_idx: 392, function: Function { arguments: [NamedExternref("GPUUncapturedErrorEvent")], shim_idx: 393, ret: Unit, inner_ret: Some(Unit) }, mutable: true }) -> Externref`.
            const ret = makeMutClosure(arg0, arg1, wasm.wasm_bindgen__closure__destroy__h5c593ebc081e4306, wasm_bindgen__convert__closures_____invoke__h35f7619b45dfaf2b);
            return ret;
        };
        imports.wbg.__wbindgen_init_externref_table = function() {
            const table = wasm.__wbindgen_externrefs;
            const offset = table.grow(4);
            table.set(0, undefined);
            table.set(offset + 0, undefined);
            table.set(offset + 1, null);
            table.set(offset + 2, true);
            table.set(offset + 3, false);
        };

        return imports;
    }

    function __wbg_finalize_init(instance, module) {
        wasm = instance.exports;
        __wbg_init.__wbindgen_wasm_module = module;
        cachedDataViewMemory0 = null;
        cachedUint32ArrayMemory0 = null;
        cachedUint8ArrayMemory0 = null;


        wasm.__wbindgen_start();
        return wasm;
    }

    function initSync(module) {
        if (wasm !== undefined) return wasm;


        if (typeof module !== 'undefined') {
            if (Object.getPrototypeOf(module) === Object.prototype) {
                ({module} = module)
            } else {
                console.warn('using deprecated parameters for `initSync()`; pass a single object instead')
            }
        }

        const imports = __wbg_get_imports();
        if (!(module instanceof WebAssembly.Module)) {
            module = new WebAssembly.Module(module);
        }
        const instance = new WebAssembly.Instance(module, imports);
        return __wbg_finalize_init(instance, module);
    }

    async function __wbg_init(module_or_path) {
        if (wasm !== undefined) return wasm;


        if (typeof module_or_path !== 'undefined') {
            if (Object.getPrototypeOf(module_or_path) === Object.prototype) {
                ({module_or_path} = module_or_path)
            } else {
                console.warn('using deprecated parameters for the initialization function; pass a single object instead')
            }
        }

        if (typeof module_or_path === 'undefined' && typeof script_src !== 'undefined') {
            module_or_path = script_src.replace(/\.js$/, '_bg.wasm');
        }
        const imports = __wbg_get_imports();

        if (typeof module_or_path === 'string' || (typeof Request === 'function' && module_or_path instanceof Request) || (typeof URL === 'function' && module_or_path instanceof URL)) {
            module_or_path = fetch(module_or_path);
        }

        const { instance, module } = await __wbg_load(await module_or_path, imports);

        return __wbg_finalize_init(instance, module);
    }

    wasm_bindgen = Object.assign(__wbg_init, { initSync }, __exports);
})();
