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

// Direct logging to stderr to ensure visibility in terminal
void SysLog(const std::string& msg) {
  std::string full_msg = "[MisaRin-Sys] " + msg + "\n";
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
  if (const auto* int32_value = std::get_if<int32_t>(&value)) {
    return *int32_value;
  }
  if (const auto* int64_value = std::get_if<int64_t>(&value)) {
    return *int64_value;
  }
  if (const auto* double_value = std::get_if<double>(&value)) {
    return static_cast<int64_t>(*double_value);
  }
  return std::nullopt;
}

int GetClampedInt(const flutter::EncodableMap& args,
                  const char* key,
                  int fallback,
                  int min_value,
                  int max_value) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return std::clamp(fallback, min_value, max_value);
  }
  const auto value = GetIntValue(it->second);
  if (!value.has_value()) {
    return std::clamp(fallback, min_value, max_value);
  }
  return std::clamp(static_cast<int>(*value), min_value, max_value);
}

uint32_t GetBackgroundColor(const flutter::EncodableMap& args) {
  const auto it = args.find(flutter::EncodableValue("backgroundColorArgb"));
  if (it == args.end()) {
    return kFallbackBackground;
  }
  const auto value = GetIntValue(it->second);
  if (!value.has_value()) {
    return kFallbackBackground;
  }
  return static_cast<uint32_t>(*value);
}

std::string GetSurfaceId(const flutter::EncodableMap& args) {
  const auto it = args.find(flutter::EncodableValue("surfaceId"));
  if (it == args.end()) {
    return "default";
  }
  if (const auto* str = std::get_if<std::string>(&it->second)) {
    if (!str->empty()) {
      return *str;
    }
  }
  if (const auto value = GetIntValue(it->second); value.has_value()) {
    return std::to_string(*value);
  }
  return "default";
}

struct GpuSurfaceBinding {
  explicit GpuSurfaceBinding(void* handle, size_t width, size_t height)
      : shared_handle(handle) {
    Update(handle, width, height);
  }

  void Update(void* handle, size_t width, size_t height) {
    shared_handle = handle;
    descriptor.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
    descriptor.handle = handle;
    descriptor.width = width;
    descriptor.height = height;
    descriptor.visible_width = width;
    descriptor.visible_height = height;
    descriptor.format = kFlutterDesktopPixelFormatBGRA8888;
    descriptor.release_callback = nullptr;
    descriptor.release_context = nullptr;
  }

  const FlutterDesktopGpuSurfaceDescriptor* GetDescriptor() const {
    return &descriptor;
  }

  static const FlutterDesktopGpuSurfaceDescriptor* Callback(size_t,
                                                            size_t,
                                                            void* user_data) {
    const auto* binding = static_cast<GpuSurfaceBinding*>(user_data);
    if (!binding) return nullptr;
    return binding->GetDescriptor();
  }

  void* shared_handle;
  FlutterDesktopGpuSurfaceDescriptor descriptor{};
};

void ReleaseBinding(void* user_data) {
  auto* keepalive = static_cast<std::shared_ptr<GpuSurfaceBinding>*>(user_data);
  delete keepalive;
}

int64_t ClampIntervalUs(int64_t value) {
  return std::clamp(value, kMinIntervalUs, kMaxIntervalUs);
}

int64_t QueryRefreshIntervalUs() {
  DWM_TIMING_INFO timing_info{};
  timing_info.cbSize = sizeof(timing_info);
  if (SUCCEEDED(DwmGetCompositionTimingInfo(nullptr, &timing_info))) {
    const uint32_t num = timing_info.rateRefresh.uiNumerator;
    const uint32_t den = timing_info.rateRefresh.uiDenominator;
    if (num > 0 && den > 0) {
      const double hz = static_cast<double>(num) / static_cast<double>(den);
      if (hz > 1.0) {
        return ClampIntervalUs(static_cast<int64_t>(1'000'000.0 / hz));
      }
    }
  }
  DEVMODE dev_mode{};
  dev_mode.dmSize = sizeof(dev_mode);
  if (EnumDisplaySettings(nullptr, ENUM_CURRENT_SETTINGS, &dev_mode)) {
    if (dev_mode.dmDisplayFrequency > 1) {
      return ClampIntervalUs(static_cast<int64_t>(1'000'000 / dev_mode.dmDisplayFrequency));
    }
  }
  return kFallbackIntervalUs;
}

int64_t NowMs() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now().time_since_epoch())
      .count();
}

bool IsPresentLogEnabled() {
  static const bool enabled = []() {
    char* raw = nullptr;
    size_t len = 0;
    if (_dupenv_s(&raw, &len, "MISA_RIN_WIN_PRESENT_LOG") != 0 || !raw) return false;
    const bool is_enabled = raw[0] != '\0' && raw[0] != '0';
    std::free(raw);
    return is_enabled;
  }();
  return enabled;
}

void PresentLog(const std::string& message) {
  if (!IsPresentLogEnabled()) return;
  SysLog("[present] " + message);
}

} // namespace

class RustLibMisaRinPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar,
      FlutterDesktopPluginRegistrarRef raw_registrar);

  explicit RustLibMisaRinPlugin(
      FlutterDesktopTextureRegistrarRef texture_registrar);

  ~RustLibMisaRinPlugin() override;

  RustLibMisaRinPlugin(const RustLibMisaRinPlugin&) = delete;
  RustLibMisaRinPlugin& operator=(const RustLibMisaRinPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

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
    int width = 0;
    int height = 0;
    int layer_count = kFallbackLayerCount;
    uint32_t background_color_argb = kFallbackBackground;
    uint64_t engine_handle = 0;
    int64_t texture_id = -1;
    std::shared_ptr<GpuSurfaceBinding> binding;
    std::mutex mutex;
    bool waiting_first_frame = false;
    int64_t first_frame_start_ms = 0;
    int64_t last_first_frame_log_ms = 0;
    uint32_t first_frame_poll_count = 0;

    int64_t RefreshFrame() {
      std::lock_guard<std::mutex> lock(mutex);
      if (engine_handle == 0 || texture_id < 0) return -1;
      const bool ready = engine_poll_frame_ready(engine_handle);
      if (waiting_first_frame) {
        first_frame_poll_count += 1;
        const int64_t now_ms = NowMs();
        if (ready) {
          SysLog("first frame ready surface=" + surface_id + " texture=" + std::to_string(texture_id) + " ms=" + std::to_string(now_ms - first_frame_start_ms));
          waiting_first_frame = false;
        } else if (now_ms - last_first_frame_log_ms >= 500) {
          last_first_frame_log_ms = now_ms;
          SysLog("waiting first frame surface=" + surface_id + " texture=" + std::to_string(texture_id) + " ms=" + std::to_string(now_ms - first_frame_start_ms));
        }
      }
      return ready ? texture_id : -1;
    }
  };

  explicit Impl(FlutterDesktopTextureRegistrarRef texture_registrar)
      : texture_registrar_(texture_registrar), running_(true) {
    // Warmup: register 2 textures immediately to avoid registration lag later
    SysLog("Initializing plugin, starting warmup...");
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
    texture_pool_.clear();
  }

  void PreRegisterTexture() {
    auto binding = std::make_shared<GpuSurfaceBinding>(nullptr, 1, 1);
    FlutterDesktopTextureInfo texture_info{};
    texture_info.type = kFlutterDesktopGpuSurfaceTexture;
    texture_info.gpu_surface_config.struct_size = sizeof(FlutterDesktopGpuSurfaceTextureConfig);
    texture_info.gpu_surface_config.type = kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
    texture_info.gpu_surface_config.callback = GpuSurfaceBinding::Callback;
    texture_info.gpu_surface_config.user_data = binding.get();

    auto start = std::chrono::high_resolution_clock::now();
    const int64_t texture_id = FlutterDesktopTextureRegistrarRegisterExternalTexture(texture_registrar_, &texture_info);
    auto end = std::chrono::high_resolution_clock::now();
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

    if (texture_id >= 0) {
      std::lock_guard<std::mutex> lock(pool_mutex_);
      texture_pool_.push_back({texture_id, std::move(binding)});
      SysLog("Warmup registration OK: id=" + std::to_string(texture_id) + " took " + std::to_string(ms) + "ms");
    } else {
      SysLog("Warmup registration FAILED");
    }
  }

  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& method_call, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    flutter::EncodableMap empty_args;
    if (method_call.method_name() == "getTextureInfo") {
      HandleGetTextureInfo(args ? *args : empty_args, std::move(result));
    } else if (method_call.method_name() == "disposeTexture") {
      HandleDisposeTexture(args ? *args : empty_args, std::move(result));
    } else {
      result->NotImplemented();
    }
  }

  void HandleGetTextureInfo(const flutter::EncodableMap& args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const std::string surface_id = GetSurfaceId(args);
    const int width = GetClampedInt(args, "width", kFallbackSize, 1, kMaxDimension);
    const int height = GetClampedInt(args, "height", kFallbackSize, 1, kMaxDimension);
    const int layer_count = GetClampedInt(args, "layerCount", kFallbackLayerCount, 1, kMaxLayerCount);
    const uint32_t background_color = GetBackgroundColor(args);

    std::shared_ptr<SurfaceState> surface;
    {
      std::lock_guard<std::mutex> lock(surfaces_mutex_);
      auto it = surfaces_.find(surface_id);
      if (it != surfaces_.end()) {
        surface = it->second;
      } else {
        surface = std::make_shared<SurfaceState>();
        surface->surface_id = surface_id;
        surfaces_.emplace(surface_id, surface);
      }
    }

    std::lock_guard<std::mutex> lock(surface->mutex);
    bool needs_recreate = (surface->texture_id < 0) || (surface->width != width || surface->height != height);
    bool layer_count_changed = surface->engine_handle != 0 && surface->layer_count != layer_count;

    if (surface->engine_handle != 0 && !needs_recreate && !layer_count_changed) {
      result->Success(MakeResponse(surface, false));
      return;
    }

    bool engine_created = false;
    if (surface->engine_handle == 0) {
      surface->engine_handle = engine_create(static_cast<uint32_t>(width), static_cast<uint32_t>(height));
      engine_created = true;
    } else if (surface->width != width || surface->height != height) {
      if (engine_resize_canvas(surface->engine_handle, width, height, layer_count, background_color) == 0) {
        engine_dispose(surface->engine_handle);
        surface->engine_handle = engine_create(width, height);
        engine_created = true;
      }
    }

    if (surface->engine_handle == 0) {
      result->Error("engine_create_failed", "Engine creation returned 0");
      return;
    }

    surface->width = width;
    surface->height = height;
    surface->layer_count = layer_count;
    surface->background_color_argb = background_color;

    if (needs_recreate) {
      if (surface->texture_id >= 0) RecycleTextureLocked(surface);

      void* shared_handle = engine_create_present_dxgi_surface(surface->engine_handle, width, height);
      if (!shared_handle) {
        result->Error("dxgi_failed", "engine_create_present_dxgi_surface returned null");
        return;
      }

      int64_t pooled_id = -1;
      std::shared_ptr<GpuSurfaceBinding> binding;
      {
        std::lock_guard<std::mutex> pool_lock(pool_mutex_);
        if (!texture_pool_.empty()) {
          auto slot = texture_pool_.back();
          texture_pool_.pop_back();
          pooled_id = slot.texture_id;
          binding = slot.binding;
          SysLog("Pool reuse: id=" + std::to_string(pooled_id) + " for " + surface_id);
        }
      }

      if (pooled_id >= 0) {
        binding->Update(shared_handle, width, height);
        surface->texture_id = pooled_id;
        surface->binding = std::move(binding);
      } else {
        SysLog("Pool empty, registering new texture for " + surface_id);
        surface->binding = std::make_shared<GpuSurfaceBinding>(shared_handle, width, height);
        FlutterDesktopTextureInfo texture_info{};
        texture_info.type = kFlutterDesktopGpuSurfaceTexture;
        texture_info.gpu_surface_config.struct_size = sizeof(FlutterDesktopGpuSurfaceTextureConfig);
        texture_info.gpu_surface_config.type = kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
        texture_info.gpu_surface_config.callback = GpuSurfaceBinding::Callback;
        texture_info.gpu_surface_config.user_data = surface->binding.get();
        surface->texture_id = FlutterDesktopTextureRegistrarRegisterExternalTexture(texture_registrar_, &texture_info);
      }
      surface->waiting_first_frame = true;
      surface->first_frame_start_ms = NowMs();
    }

    if (engine_created || needs_recreate || layer_count_changed) {
      engine_reset_canvas_with_layers(surface->engine_handle, layer_count, background_color);
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
    auto next_check = std::chrono::steady_clock::now();
    auto next_tick = std::chrono::steady_clock::now() + std::chrono::microseconds(interval);
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
      auto now = std::chrono::steady_clock::now();
      if (now >= next_check) {
        interval = QueryRefreshIntervalUs();
        next_check = now + std::chrono::seconds(1);
      }
      if (next_tick <= now) next_tick = now + std::chrono::microseconds(interval);
      std::this_thread::sleep_until(next_tick);
      next_tick += std::chrono::microseconds(interval);
    }
  }

  void RecycleTextureLocked(const std::shared_ptr<SurfaceState>& s) {
    if (s->texture_id >= 0 && s->binding) {
      std::lock_guard<std::mutex> lock(pool_mutex_);
      texture_pool_.push_back({s->texture_id, s->binding});
      SysLog("Recycled texture: id=" + std::to_string(s->texture_id));
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
