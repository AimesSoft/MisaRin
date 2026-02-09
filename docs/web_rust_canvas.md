# Web Rust 画布构建与部署

## 1) 生成 Web wasm 产物
在项目根目录运行：

```bash
tool/build_web_wasm.sh
```

产物会生成到 `web/pkg/`：
- `rust_lib_misa_rin.js`
- `rust_lib_misa_rin_bg.wasm`

Web 端会由 flutter_rust_bridge 运行时自动加载 `web/pkg/rust_lib_misa_rin.js`，
不需要手动在 `web/index.html` 引入，但请确保部署时该文件可被访问。

默认启用 wasm 线程（需要 nightly + build-std）。可通过环境变量控制：

```bash
# 关闭 wasm 线程（不使用 shared-memory）
WASM_THREADS=0 tool/build_web_wasm.sh
```

如需调整 wasm 线程栈大小（默认 32MB），可设置：

```bash
WASM_THREAD_STACK_SIZE=33554432 tool/build_web_wasm.sh
```

如需增大共享内存初始大小（默认 4096 pages = 256MB），可设置：

```bash
WASM_MEMORY_INITIAL_PAGES=4096 tool/build_web_wasm.sh
```

如果你想一键构建并启动本地服务器（自动带 COOP/COEP 响应头）：

```bash
tool/run_web_with_headers.sh
```

可通过环境变量修改端口/地址：

```bash
PORT=9000 HOST=127.0.0.1 tool/run_web_with_headers.sh
```

## 2) 启用线程时必须开启 COOP/COEP
Web 端需要跨源隔离（crossOriginIsolated）才能启用 wasm 线程：

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

已提供示例配置文件：
- `web/_headers`（Netlify）
- `web/headers.json`（Firebase Hosting）

请确保你的部署服务实际下发上述响应头。
