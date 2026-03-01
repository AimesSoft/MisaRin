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
void* engine_create_present_dxgi_surface(uint64_t handle, uint32_t width, uint32_t height);
uint8_t engine_resize_canvas(uint64_t handle, uint32_t width, uint32_t height, uint32_t layer_count, uint32_t background_color_argb);
void engine_reset_canvas_with_layers(uint64_t handle, uint32_t layer_count, uint32_t background_color_argb);
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
}

struct GpuSurfaceBinding {
  std::mutex mutex;
  void* shared_handle = nullptr;
  FlutterDesktopGpuSurfaceDescriptor descriptor{};

  explicit GpuSurfaceBinding(void* h, size_t w, size_t height) { Update(h, w, height); }

  void Update(void* h, size_t w, size_t height) {
    std::lock_guard<std::mutex> lock(mutex);
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

  static const FlutterDesktopGpuSurfaceDescriptor* Callback(size_t, size_t, void* data) {
    auto* b = static_cast<GpuSurfaceBinding*>(data);
    if (!b) return nullptr;
    std::lock_guard<std::mutex> lock(b->mutex);
    return b->shared_handle ? &b->descriptor : nullptr;
  }
};

void ReleaseBinding(void* data) { delete static_cast<std::shared_ptr<GpuSurfaceBinding>*>(data); }

class RustLibMisaRinPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar, FlutterDesktopPluginRegistrarRef raw_registrar);
  explicit RustLibMisaRinPlugin(flutter::PluginRegistrarWindows* registrar, FlutterDesktopTextureRegistrarRef texture_registrar);
  ~RustLibMisaRinPlugin() override;
  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) override;
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
    std::string sid;
    int w = 0, h = 0, layers = 1;
    uint32_t bg = 0xFFFFFFFF;
    uint64_t handle = 0;
    int64_t tid = -1;
    std::shared_ptr<GpuSurfaceBinding> binding;
    std::mutex mutex;
    bool waiting_first_frame = false;
    int64_t start_ms = 0;

    int64_t RefreshFrame() {
      std::lock_guard<std::mutex> lock(mutex);
      if (handle == 0 || tid < 0) return -1;
      if (engine_poll_frame_ready(handle)) {
        if (waiting_first_frame) {
          SysLog("First frame for " + sid + " ms=" + std::to_string(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count() - start_ms));
          waiting_first_frame = false;
        }
        return tid;
      }
      return -1;
    }
  };

  flutter::PluginRegistrarWindows* registrar_;
  FlutterDesktopTextureRegistrarRef texture_registrar_;
  std::mutex surfaces_mutex_;
  std::unordered_map<std::string, std::shared_ptr<SurfaceState>> surfaces_;
  std::atomic<bool> running_;
  std::thread frame_thread_;
  std::mutex pool_mutex_;
  std::vector<TextureSlot> texture_pool_;

  explicit Impl(flutter::PluginRegistrarWindows* reg, FlutterDesktopTextureRegistrarRef tex_reg)
      : registrar_(reg), texture_registrar_(tex_reg), running_(true) {
    SysLog("Optimized Plugin Impl starting...");
    for (int i = 0; i < 2; ++i) PreRegisterTexture();
    frame_thread_ = std::thread([this]() { FrameLoop(); });
  }

  void PreRegisterTexture() {
    auto b = std::make_shared<GpuSurfaceBinding>(nullptr, 1, 1);
    FlutterDesktopTextureInfo info{};
    info.type = kFlutterDesktopGpuSurfaceTexture;
    info.gpu_surface_config.struct_size = sizeof(FlutterDesktopGpuSurfaceTextureConfig);
    info.gpu_surface_config.type = kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
    info.gpu_surface_config.callback = GpuSurfaceBinding::Callback;
    info.gpu_surface_config.user_data = b.get();
    int64_t tid = FlutterDesktopTextureRegistrarRegisterExternalTexture(texture_registrar_, &info);
    if (tid >= 0) {
      std::lock_guard<std::mutex> lock(pool_mutex_);
      texture_pool_.push_back({tid, std::move(b)});
    }
  }

  void HandleGetTextureInfo(const flutter::EncodableMap& args, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    auto sid = GetSid(args);
    int w = GetInt(args, "width", 512), h = GetInt(args, "height", 512);
    int layers = GetInt(args, "layerCount", 1);
    uint32_t bg = GetBg(args);

    std::shared_ptr<SurfaceState> s;
    {
      std::lock_guard<std::mutex> lock(surfaces_mutex_);
      if (surfaces_.count(sid)) s = surfaces_[sid];
      else surfaces_[sid] = s = std::make_shared<SurfaceState>(), s->sid = sid;
    }

    std::lock_guard<std::mutex> lock(s->mutex);
    if (s->handle != 0 && s->tid >= 0 && s->w == w && s->h == h && s->layers == layers) {
      result->Success(MakeResp(s, false)); return;
    }

    // REUSE TEXTURE IMMEDIATELY if available
    bool reused = false;
    if (s->tid < 0) {
      std::lock_guard<std::mutex> pool_lock(pool_mutex_);
      if (!texture_pool_.empty()) {
        auto slot = texture_pool_.back(); texture_pool_.pop_back();
        s->tid = slot.texture_id; s->binding = slot.binding;
        reused = true;
        SysLog("INSTANT POOL REUSE: " + std::to_string(s->tid));
      }
    }

    // Background the heavy GPU work to unblock UI thread
    std::thread([this, s, w, h, layers, bg, result = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result))]() mutable {
      bool engine_created = false;
      {
        std::lock_guard<std::mutex> lock(s->mutex);
        if (s->handle == 0) { s->handle = engine_create(w, h); engine_created = true; }
        else if (s->w != w || s->h != h) {
          if (!engine_resize_canvas(s->handle, w, h, layers, bg)) {
            engine_dispose(s->handle); s->handle = engine_create(w, h); engine_created = true;
          }
        }
      }

      if (s->handle == 0) { 
        this->registrar_->task_runner()->PostTask([result]() { result->Error("fail", "engine"); }); 
        return; 
      }

      void* sh = engine_create_present_dxgi_surface(s->handle, w, h);
      
      {
        std::lock_guard<std::mutex> lock(s->mutex);
        s->w = w; s->h = h; s->layers = layers; s->bg = bg;
        if (s->tid < 0) {
          s->binding = std::make_shared<GpuSurfaceBinding>(sh, w, h);
          FlutterDesktopTextureInfo info{};
          info.type = kFlutterDesktopGpuSurfaceTexture;
          info.gpu_surface_config.struct_size = sizeof(FlutterDesktopGpuSurfaceTextureConfig);
          info.gpu_surface_config.type = kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
          info.gpu_surface_config.callback = GpuSurfaceBinding::Callback;
          info.gpu_surface_config.user_data = s->binding.get();
          s->tid = FlutterDesktopTextureRegistrarRegisterExternalTexture(texture_registrar_, &info);
        } else {
          s->binding->Update(sh, w, h);
        }
        s->waiting_first_frame = true;
        s->start_ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
        engine_reset_canvas_with_layers(s->handle, layers, bg);
      }

      // Return result back on UI thread
      this->registrar_->task_runner()->PostTask([this, s, engine_created, result]() {
        result->Success(MakeResp(s, engine_created));
      });
    }).detach();
  }

  flutter::EncodableValue MakeResp(const std::shared_ptr<SurfaceState>& s, bool is_new) {
    flutter::EncodableMap resp;
    resp[flutter::EncodableValue("textureId")] = flutter::EncodableValue(s->tid);
    resp[flutter::EncodableValue("engineHandle")] = flutter::EncodableValue(static_cast<int64_t>(s->handle));
    resp[flutter::EncodableValue("width")] = flutter::EncodableValue(s->w);
    resp[flutter::EncodableValue("height")] = flutter::EncodableValue(s->h);
    resp[flutter::EncodableValue("isNewEngine")] = flutter::EncodableValue(is_new);
    return flutter::EncodableValue(resp);
  }

  void FrameLoop() {
    auto next_tick = std::chrono::steady_clock::now();
    while (running_.load()) {
      std::vector<std::shared_ptr<SurfaceState>> entries;
      { std::lock_guard<std::mutex> lock(surfaces_mutex_); for (const auto& e : surfaces_) entries.push_back(e.second); }
      for (const auto& s : entries) {
        int64_t tid = s->RefreshFrame();
        if (tid >= 0) FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(texture_registrar_, tid);
      }
      next_tick += std::chrono::microseconds(8000);
      std::this_thread::sleep_until(next_tick);
    }
  }

  void DisposeAll() {
    std::vector<std::shared_ptr<SurfaceState>> entries;
    { std::lock_guard<std::mutex> lock(surfaces_mutex_); for (const auto& e : surfaces_) entries.push_back(e.second); surfaces_.clear(); }
    for (const auto& s : entries) {
      if (s->tid >= 0 && s->binding) {
        std::lock_guard<std::mutex> pool_lock(pool_mutex_);
        texture_pool_.push_back({s->tid, s->binding});
      }
      if (s->handle != 0) engine_dispose(s->handle);
    }
  }

  std::string GetSid(const flutter::EncodableMap& args) {
    auto it = args.find(flutter::EncodableValue("surfaceId"));
    if (it == args.end()) return "default";
    if (const auto* s = std::get_if<std::string>(&it->second)) return *s;
    return "default";
  }
  int GetInt(const flutter::EncodableMap& args, const char* key, int def) {
    auto it = args.find(flutter::EncodableValue(key));
    if (it == args.end()) return def;
    if (const auto* i = std::get_if<int32_t>(&it->second)) return *i;
    if (const auto* i = std::get_if<int64_t>(&it->second)) return static_cast<int>(*i);
    return def;
  }
  uint32_t GetBg(const flutter::EncodableMap& args) {
    auto it = args.find(flutter::EncodableValue("backgroundColorArgb"));
    if (it == args.end()) return 0xFFFFFFFF;
    if (const auto* i = std::get_if<int64_t>(&it->second)) return static_cast<uint32_t>(*i);
    return 0xFFFFFFFF;
  }
};

RustLibMisaRinPlugin::RustLibMisaRinPlugin(flutter::PluginRegistrarWindows* registrar, FlutterDesktopTextureRegistrarRef texture_registrar)
    : impl_(std::make_unique<Impl>(registrar, texture_registrar)) {}
RustLibMisaRinPlugin::~RustLibMisaRinPlugin() = default;
void RustLibMisaRinPlugin::HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (call.method_name() == "getTextureInfo") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    impl_->HandleGetTextureInfo(args ? *args : flutter::EncodableMap{}, std::move(result));
  } else {
    result->NotImplemented();
  }
}

void RustLibMisaRinPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar, FlutterDesktopPluginRegistrarRef raw_registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(registrar->messenger(), kChannelName, &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<RustLibMisaRinPlugin>(registrar, FlutterDesktopRegistrarGetTextureRegistrar(raw_registrar));
  channel->SetMethodCallHandler([p = plugin.get()](const auto& call, auto res) { p->HandleMethodCall(call, std::move(res)); });
  registrar->AddPlugin(std::move(plugin));
}

} // namespace rust_lib_misa_rin

void RustLibMisaRinPluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  rust_lib_misa_rin::RustLibMisaRinPlugin::RegisterWithRegistrar(flutter::PluginRegistrarManager::GetInstance()->GetRegistrar<flutter::PluginRegistrarWindows>(registrar), registrar);
}
