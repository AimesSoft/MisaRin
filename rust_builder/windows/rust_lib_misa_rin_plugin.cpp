#include "rust_lib_misa_rin/rust_lib_misa_rin_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter_texture_registrar.h>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <debugapi.h>

#include <dwmapi.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <iostream>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

void SysLog(const std::string& msg) {
  auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
                 std::chrono::steady_clock::now().time_since_epoch())
                 .count();
  std::string full_msg = "[MisaRin-Sys][" + std::to_string(now) + "] " + msg + "\n";
  OutputDebugStringA(full_msg.c_str());
  std::cerr << full_msg << std::flush;
}

extern "C" {
uint64_t engine_create(uint32_t width, uint32_t height);
void engine_dispose(uint64_t handle);
void* engine_create_present_dxgi_surface(uint64_t handle,
                                         uint32_t width,
                                         uint32_t height);
uint8_t engine_resize_canvas(uint64_t handle,
                             uint32_t width,
                             uint32_t height,
                             uint32_t layer_count,
                             uint32_t background_color_argb);
void engine_reset_canvas_with_layers(uint64_t handle,
                                     uint32_t layer_count,
                                     uint32_t background_color_argb);
bool engine_poll_frame_ready(uint64_t handle);
}

namespace rust_lib_misa_rin {

namespace {

constexpr char kChannelName[] = "misarin/rust_canvas_texture";
constexpr int kFallbackSize = 512;
constexpr int kFallbackLayerCount = 1;
constexpr uint32_t kFallbackBackground = 0xFFFFFFFF;
constexpr int kMaxDimension = 16384;
constexpr int kMaxLayerCount = 1024;
constexpr int64_t kFallbackIntervalUs = 8000;
constexpr int64_t kMinIntervalUs = 4000;
constexpr int64_t kMaxIntervalUs = 33333;

std::optional<int64_t> GetIntValue(const flutter::EncodableValue& value) {
  if (const auto* int32_value = std::get_if<int32_t>(&value)) return *int32_value;
  if (const auto* int64_value = std::get_if<int64_t>(&value)) return *int64_value;
  if (const auto* double_value = std::get_if<double>(&value)) return static_cast<int64_t>(*double_value);
  return std::nullopt;
}

int GetClampedInt(const flutter::EncodableMap& args, const char* key, int fallback, int min_v, int max_v) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) return std::clamp(fallback, min_v, max_v);
  const auto val = GetIntValue(it->second);
  if (!val.has_value()) return std::clamp(fallback, min_v, max_v);
  return std::clamp(static_cast<int>(*val), min_v, max_v);
}

uint32_t GetBackgroundColor(const flutter::EncodableMap& args) {
  const auto it = args.find(flutter::EncodableValue("backgroundColorArgb"));
  if (it == args.end()) return kFallbackBackground;
  const auto val = GetIntValue(it->second);
  return val.has_value() ? static_cast<uint32_t>(*val) : kFallbackBackground;
}

std::string GetSurfaceId(const flutter::EncodableMap& args) {
  const auto it = args.find(flutter::EncodableValue("surfaceId"));
  if (it == args.end()) return "default";
  if (const auto* str = std::get_if<std::string>(&it->second)) return str->empty() ? "default" : *str;
  if (const auto val = GetIntValue(it->second); val.has_value()) return std::to_string(*val);
  return "default";
}

struct GpuSurfaceBinding {
  explicit GpuSurfaceBinding(void* handle, size_t w, size_t h) : shared_handle(handle) { Update(handle, w, h); }
  void Update(void* h, size_t w, size_t height) {
    shared_handle = h;
    descriptor.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
    descriptor.handle = h;
    descriptor.width = w;
    descriptor.height = height;
    descriptor.visible_width = w;
    descriptor.visible_height = height;
    descriptor.format = kFlutterDesktopPixelFormatBGRA8888;
    descriptor.release_callback = nullptr;
    descriptor.release_context = nullptr;
  }
  const FlutterDesktopGpuSurfaceDescriptor* GetDescriptor() const { return &descriptor; }
  static const FlutterDesktopGpuSurfaceDescriptor* Callback(size_t, size_t, void* data) {
    const auto* b = static_cast<GpuSurfaceBinding*>(data);
    return b ? b->GetDescriptor() : nullptr;
  }
  void* shared_handle;
  FlutterDesktopGpuSurfaceDescriptor descriptor{};
};

void ReleaseBinding(void* data) { delete static_cast<std::shared_ptr<GpuSurfaceBinding>*>(data); }

int64_t QueryRefreshIntervalUs() {
  DWM_TIMING_INFO info{};
  info.cbSize = sizeof(info);
  if (SUCCEEDED(DwmGetCompositionTimingInfo(nullptr, &info))) {
    if (info.rateRefresh.uiNumerator > 0 && info.rateRefresh.uiDenominator > 0) {
      double hz = static_cast<double>(info.rateRefresh.uiNumerator) / info.rateRefresh.uiDenominator;
      if (hz > 1.0) return std::clamp(static_cast<int64_t>(1'000'000.0 / hz), kMinIntervalUs, kMaxIntervalUs);
    }
  }
  return kFallbackIntervalUs;
}

int64_t NowMs() { return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count(); }

} // namespace

class RustLibMisaRinPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar, FlutterDesktopPluginRegistrarRef raw_registrar);
  explicit RustLibMisaRinPlugin(FlutterDesktopTextureRegistrarRef texture_registrar);
  ~RustLibMisaRinPlugin() override;
  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

struct RustLibMisaRinPlugin::Impl {
  struct TextureSlot {
    int64_t texture_id = -1;
    std::shared_ptr<GpuSurfaceBinding> binding;
  };

  struct SurfaceState {
    std::string surface_id;
    int width = 0, height = 0, layer_count = kFallbackLayerCount;
    uint32_t background_color_argb = kFallbackBackground;
    uint64_t engine_handle = 0;
    int64_t texture_id = -1;
    std::shared_ptr<GpuSurfaceBinding> binding;
    std::mutex mutex;
    bool waiting_first_frame = false;
    int64_t first_frame_start_ms = 0;

    int64_t RefreshFrame() {
      std::lock_guard<std::mutex> lock(mutex);
      if (engine_handle == 0 || texture_id < 0) return -1;
      if (engine_poll_frame_ready(engine_handle)) {
        if (waiting_first_frame) {
          SysLog("First frame ready sid=" + surface_id + " tid=" + std::to_string(texture_id) + " ms=" + std::to_string(NowMs() - first_frame_start_ms));
          waiting_first_frame = false;
        }
        return texture_id;
      }
      return -1;
    }
  };

  explicit Impl(FlutterDesktopTextureRegistrarRef texture_registrar)
      : texture_registrar_(texture_registrar), running_(true) {
    SysLog("Plugin Impl starting...");
    PreRegisterTexture();
    PreRegisterTexture();
    frame_thread_ = std::thread([this]() { FrameLoop(); });
  }

  ~Impl() {
    running_.store(false);
    if (frame_thread_.joinable()) frame_thread_.join();
    DisposeAll();
    std::lock_guard<std::mutex> lock(pool_mutex_);
    for (const auto& slot : texture_pool_) {
      auto* keepalive = new std::shared_ptr<GpuSurfaceBinding>(slot.binding);
      FlutterDesktopTextureRegistrarUnregisterExternalTexture(texture_registrar_, slot.texture_id, ReleaseBinding, keepalive);
    }
  }

  void PreRegisterTexture() {
    auto binding = std::make_shared<GpuSurfaceBinding>(nullptr, 1, 1);
    FlutterDesktopTextureInfo info{};
    info.type = kFlutterDesktopGpuSurfaceTexture;
    info.gpu_surface_config.struct_size = sizeof(FlutterDesktopGpuSurfaceTextureConfig);
    info.gpu_surface_config.type = kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
    info.gpu_surface_config.callback = GpuSurfaceBinding::Callback;
    info.gpu_surface_config.user_data = binding.get();

    auto start = std::chrono::high_resolution_clock::now();
    int64_t tid = FlutterDesktopTextureRegistrarRegisterExternalTexture(texture_registrar_, &info);
    auto end = std::chrono::high_resolution_clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

    if (tid >= 0) {
      std::lock_guard<std::mutex> lock(pool_mutex_);
      texture_pool_.push_back({tid, std::move(binding)});
      SysLog("Warmup OK: id=" + std::to_string(tid) + " ms=" + std::to_string(ms));
    }
  }

  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& method_call, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    auto start_time = NowMs();
    const std::string& name = method_call.method_name();
    SysLog("Method call: " + name);

    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    flutter::EncodableMap empty_args;
    const auto& actual_args = args ? *args : empty_args;

    if (name == "getTextureInfo") {
      HandleGetTextureInfo(actual_args, std::move(result));
    } else if (name == "disposeTexture") {
      HandleDisposeTexture(actual_args, std::move(result));
    } else {
      result->NotImplemented();
    }
    SysLog("Method handle exit: " + name + " internal_ms=" + std::to_string(NowMs() - start_time));
  }

  void HandleGetTextureInfo(const flutter::EncodableMap& args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const std::string sid = GetSurfaceId(args);
    const int w = GetClampedInt(args, "width", kFallbackSize, 1, kMaxDimension);
    const int h = GetClampedInt(args, "height", kFallbackSize, 1, kMaxDimension);
    const int layers = GetClampedInt(args, "layerCount", kFallbackLayerCount, 1, kMaxLayerCount);
    const uint32_t bg = GetBackgroundColor(args);

    std::shared_ptr<SurfaceState> surface;
    {
      std::lock_guard<std::mutex> lock(surfaces_mutex_);
      auto it = surfaces_.find(sid);
      if (it != surfaces_.end()) {
        surface = it->second;
      } else {
        surface = std::make_shared<SurfaceState>();
        surface->surface_id = sid;
        surfaces_.emplace(sid, surface);
      }
    }

    std::lock_guard<std::mutex> lock(surface->mutex);
    bool needs_tex = (surface->texture_id < 0) || (surface->width != w || surface->height != h);
    bool layer_changed = surface->engine_handle != 0 && surface->layer_count != layers;

    if (surface->engine_handle != 0 && !needs_tex && !layer_changed) {
      result->Success(MakeResponse(surface, false));
      return;
    }

    bool engine_created = false;
    if (surface->engine_handle == 0) {
      auto e_start = NowMs();
      surface->engine_handle = engine_create(static_cast<uint32_t>(w), static_cast<uint32_t>(h));
      SysLog("engine_create ms=" + std::to_string(NowMs() - e_start));
      engine_created = true;
    } else if (surface->width != w || surface->height != h) {
      if (engine_resize_canvas(surface->engine_handle, w, h, layers, bg) == 0) {
        engine_dispose(surface->engine_handle);
        surface->engine_handle = engine_create(w, h);
        engine_created = true;
      }
    }

    surface->width = w; surface->height = h; surface->layer_count = layers; surface->background_color_argb = bg;

    if (needs_tex) {
      if (surface->texture_id >= 0) RecycleTextureLocked(surface);

      auto d_start = NowMs();
      void* sh = engine_create_present_dxgi_surface(surface->engine_handle, w, h);
      SysLog("dxgi_surface ms=" + std::to_string(NowMs() - d_start));

      if (!sh) { result->Error("dxgi_failed", "sh is null"); return; }

      int64_t pooled_id = -1;
      std::shared_ptr<GpuSurfaceBinding> binding;
      {
        std::lock_guard<std::mutex> pool_lock(pool_mutex_);
        if (!texture_pool_.empty()) {
          auto slot = texture_pool_.back();
          texture_pool_.pop_back();
          pooled_id = slot.texture_id;
          binding = slot.binding;
          SysLog("Reuse tid=" + std::to_string(pooled_id) + " for " + sid);
        }
      }

      if (pooled_id >= 0) {
        binding->Update(sh, w, h);
        surface->texture_id = pooled_id;
        surface->binding = std::move(binding);
      } else {
        SysLog("Registering new texture for " + sid);
        surface->binding = std::make_shared<GpuSurfaceBinding>(sh, w, h);
        FlutterDesktopTextureInfo info{};
        info.type = kFlutterDesktopGpuSurfaceTexture;
        info.gpu_surface_config.struct_size = sizeof(FlutterDesktopGpuSurfaceTextureConfig);
        info.gpu_surface_config.type = kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
        info.gpu_surface_config.callback = GpuSurfaceBinding::Callback;
        info.gpu_surface_config.user_data = surface->binding.get();
        surface->texture_id = FlutterDesktopTextureRegistrarRegisterExternalTexture(texture_registrar_, &info);
      }
      surface->waiting_first_frame = true;
      surface->first_frame_start_ms = NowMs();
    }

    if (engine_created || needs_tex || layer_changed) {
      engine_reset_canvas_with_layers(surface->engine_handle, layers, bg);
    }

    result->Success(MakeResponse(surface, engine_created));
  }

  flutter::EncodableValue MakeResponse(const std::shared_ptr<SurfaceState>& s, bool is_new) {
    flutter::EncodableMap resp;
    resp[flutter::EncodableValue("textureId")] = flutter::EncodableValue(s->texture_id);
    resp[flutter::EncodableValue("engineHandle")] = flutter::EncodableValue(static_cast<int64_t>(s->engine_handle));
    resp[flutter::EncodableValue("width")] = flutter::EncodableValue(s->width);
    resp[flutter::EncodableValue("height")] = flutter::EncodableValue(s->height);
    resp[flutter::EncodableValue("isNewEngine")] = flutter::EncodableValue(is_new);
    return flutter::EncodableValue(resp);
  }

  void HandleDisposeTexture(const flutter::EncodableMap& args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const std::string id = GetSurfaceId(args);
    std::shared_ptr<SurfaceState> surface;
    {
      std::lock_guard<std::mutex> lock(surfaces_mutex_);
      auto it = surfaces_.find(id);
      if (it != surfaces_.end()) {
        surface = it->second;
        surfaces_.erase(it);
      }
    }
    if (surface) {
      std::lock_guard<std::mutex> lock(surface->mutex);
      RecycleTextureLocked(surface);
      if (surface->engine_handle != 0) engine_dispose(surface->engine_handle);
    }
    result->Success();
  }

  void DisposeAll() {
    std::vector<std::shared_ptr<SurfaceState>> entries;
    {
      std::lock_guard<std::mutex> lock(surfaces_mutex_);
      for (const auto& e : surfaces_) entries.push_back(e.second);
      surfaces_.clear();
    }
    for (const auto& s : entries) {
      std::lock_guard<std::mutex> lock(s->mutex);
      RecycleTextureLocked(s);
      if (s->engine_handle != 0) engine_dispose(s->engine_handle);
    }
  }

  void FrameLoop() {
    int64_t interval = QueryRefreshIntervalUs();
    auto next_tick = std::chrono::steady_clock::now();
    while (running_.load()) {
      std::vector<std::shared_ptr<SurfaceState>> entries;
      {
        std::lock_guard<std::mutex> lock(surfaces_mutex_);
        for (const auto& e : surfaces_) entries.push_back(e.second);
      }
      for (const auto& s : entries) {
        const int64_t tid = s->RefreshFrame();
        if (tid >= 0) FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(texture_registrar_, tid);
      }
      next_tick += std::chrono::microseconds(interval);
      std::this_thread::sleep_until(next_tick);
    }
  }

  void RecycleTextureLocked(const std::shared_ptr<SurfaceState>& s) {
    if (s->texture_id >= 0 && s->binding) {
      std::lock_guard<std::mutex> lock(pool_mutex_);
      texture_pool_.push_back({s->texture_id, s->binding});
      SysLog("Recycled tid=" + std::to_string(s->texture_id));
    }
    s->texture_id = -1;
    s->binding = nullptr;
  }

  FlutterDesktopTextureRegistrarRef texture_registrar_;
  std::mutex surfaces_mutex_;
  std::unordered_map<std::string, std::shared_ptr<SurfaceState>> surfaces_;
  std::atomic<bool> running_;
  std::thread frame_thread_;
  std::mutex pool_mutex_;
  std::vector<TextureSlot> texture_pool_;
};

void RustLibMisaRinPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar, FlutterDesktopPluginRegistrarRef raw_registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(registrar->messenger(), kChannelName, &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<RustLibMisaRinPlugin>(FlutterDesktopRegistrarGetTextureRegistrar(raw_registrar));
  channel->SetMethodCallHandler([p = plugin.get()](const auto& call, auto res) { p->HandleMethodCall(call, std::move(res)); });
  registrar->AddPlugin(std::move(plugin));
}

RustLibMisaRinPlugin::RustLibMisaRinPlugin(FlutterDesktopTextureRegistrarRef texture_registrar) : impl_(std::make_unique<Impl>(texture_registrar)) {}
RustLibMisaRinPlugin::~RustLibMisaRinPlugin() = default;
void RustLibMisaRinPlugin::HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> res) { impl_->HandleMethodCall(call, std::move(res)); }

} // namespace rust_lib_misa_rin

void RustLibMisaRinPluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  rust_lib_misa_rin::RustLibMisaRinPlugin::RegisterWithRegistrar(flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar), registrar);
}
