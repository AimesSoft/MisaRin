#include "include/rust_lib_misa_rin/rust_lib_misa_rin_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter_plugin_registrar.h>
#include <flutter_texture_registrar.h>

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <dwmapi.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstdint>
#include <functional>
#include <iostream>
#include <limits>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

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
}  // extern "C"

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
constexpr int64_t kFirstFrameForceAfterMs = 120;
constexpr int64_t kFirstFrameLogIntervalMs = 500;
constexpr UINT kAsyncCompletionMessage = WM_APP + 0x4A1;
constexpr wchar_t kCompletionWindowClass[] = L"MisaRinBackendCompletionWindow";
constexpr size_t kMaxPooledSurfaces = 3;
constexpr uint64_t kMaxPooledPixels = 48ull * 1024ull * 1024ull;

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
    if (!binding) {
      return nullptr;
    }
    return binding->GetDescriptor();
  }

  void* shared_handle = nullptr;
  FlutterDesktopGpuSurfaceDescriptor descriptor{};
};

void ReleaseBinding(void* user_data) {
  auto* keepalive = static_cast<std::shared_ptr<GpuSurfaceBinding>*>(user_data);
  if (keepalive && *keepalive) {
    auto handle =
        static_cast<HANDLE>((*keepalive)->shared_handle);
    if (handle) {
      CloseHandle(handle);
      (*keepalive)->shared_handle = nullptr;
    }
  }
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
        return ClampIntervalUs(
            static_cast<int64_t>(1'000'000.0 / hz));
      }
    }
  }

  DEVMODE dev_mode{};
  dev_mode.dmSize = sizeof(dev_mode);
  if (EnumDisplaySettings(nullptr, ENUM_CURRENT_SETTINGS, &dev_mode)) {
    if (dev_mode.dmDisplayFrequency > 1) {
      return ClampIntervalUs(
          static_cast<int64_t>(1'000'000 / dev_mode.dmDisplayFrequency));
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
    if (_dupenv_s(&raw, &len, "MISA_RIN_WIN_PRESENT_LOG") != 0 || !raw) {
      return false;
    }
    const bool is_enabled = raw[0] != '\0' && raw[0] != '0';
    std::free(raw);
    return is_enabled;
  }();
  return enabled;
}

void PresentLog(const std::string& message) {
  if (!IsPresentLogEnabled()) {
    return;
  }
  const std::string msg = std::string("[misa-rin][present] ") + message;
  OutputDebugStringA((msg + "\n").c_str());
  std::cerr << msg << std::endl;
}

}  // namespace

class RustLibMisaRinPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar,
      FlutterDesktopPluginRegistrarRef raw_registrar);

  explicit RustLibMisaRinPlugin(
      FlutterDesktopTextureRegistrarRef texture_registrar,
      flutter::PluginRegistrarWindows* registrar);

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
  static LRESULT CALLBACK CompletionWindowProc(HWND hwnd,
                                               UINT message,
                                               WPARAM wparam,
                                               LPARAM lparam) {
    if (message == WM_NCCREATE) {
      auto* create = reinterpret_cast<CREATESTRUCTW*>(lparam);
      SetWindowLongPtrW(
          hwnd,
          GWLP_USERDATA,
          reinterpret_cast<LONG_PTR>(create->lpCreateParams));
      return TRUE;
    }
    auto* self =
        reinterpret_cast<Impl*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (self && message == kAsyncCompletionMessage) {
      self->DrainCompletions();
      return 0;
    }
    return DefWindowProcW(hwnd, message, wparam, lparam);
  }

  static HWND CreateCompletionWindow(Impl* owner) {
    static std::once_flag register_flag;
    std::call_once(register_flag, []() {
      WNDCLASSEXW wc{};
      wc.cbSize = sizeof(WNDCLASSEXW);
      wc.lpfnWndProc = CompletionWindowProc;
      wc.hInstance = GetModuleHandleW(nullptr);
      wc.lpszClassName = kCompletionWindowClass;
      RegisterClassExW(&wc);
    });
    return CreateWindowExW(
        0,
        kCompletionWindowClass,
        L"",
        0,
        0,
        0,
        0,
        0,
        HWND_MESSAGE,
        nullptr,
        GetModuleHandleW(nullptr),
        owner);
  }

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
    bool disposed = false;
    uint64_t request_id = 0;
    bool waiting_first_frame = false;
    int64_t first_frame_start_ms = 0;
    int64_t last_first_frame_log_ms = 0;
    uint32_t first_frame_poll_count = 0;
    bool first_frame_force_logged = false;
    bool pooled = false;
    int64_t last_used_ms = 0;

    int64_t RefreshFrame() {
      std::lock_guard<std::mutex> lock(mutex);
      if (engine_handle == 0 || texture_id < 0) {
        return -1;
      }
      const bool ready = engine_poll_frame_ready(engine_handle);
      if (waiting_first_frame) {
        first_frame_poll_count += 1;
        const int64_t now_ms = NowMs();
        const int64_t elapsed_ms = now_ms - first_frame_start_ms;
        if (ready) {
          PresentLog(
              "first frame ready surface=" + surface_id +
              " handle=" + std::to_string(engine_handle) +
              " texture=" + std::to_string(texture_id) +
              " polls=" + std::to_string(first_frame_poll_count) +
              " elapsed_ms=" + std::to_string(elapsed_ms));
          waiting_first_frame = false;
          first_frame_force_logged = false;
        } else if (elapsed_ms >= kFirstFrameForceAfterMs) {
          if (!first_frame_force_logged) {
            first_frame_force_logged = true;
            PresentLog(
                "first frame forced surface=" + surface_id +
                " handle=" + std::to_string(engine_handle) +
                " texture=" + std::to_string(texture_id) +
                " polls=" + std::to_string(first_frame_poll_count) +
                " elapsed_ms=" + std::to_string(elapsed_ms));
          }
          return texture_id;
        } else if (now_ms - last_first_frame_log_ms >=
                   kFirstFrameLogIntervalMs) {
          last_first_frame_log_ms = now_ms;
          PresentLog(
              "waiting first frame surface=" + surface_id +
              " handle=" + std::to_string(engine_handle) +
              " texture=" + std::to_string(texture_id) +
              " polls=" + std::to_string(first_frame_poll_count) +
              " elapsed_ms=" + std::to_string(elapsed_ms));
        }
      }
      if (!ready) {
        return -1;
      }
      return texture_id;
    }
  };

  explicit Impl(FlutterDesktopTextureRegistrarRef texture_registrar,
                flutter::PluginRegistrarWindows*)
      : texture_registrar_(texture_registrar), running_(true) {
    message_window_ = CreateCompletionWindow(this);
    frame_thread_ = std::thread([this]() { FrameLoop(); });
  }

  ~Impl() {
    running_.store(false);
    if (frame_thread_.joinable()) {
      frame_thread_.join();
    }
    if (message_window_) {
      DestroyWindow(message_window_);
      message_window_ = nullptr;
    }
    DisposeAll();
  }

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (method_call.method_name() == "getTextureInfo") {
      const auto* args =
          std::get_if<flutter::EncodableMap>(method_call.arguments());
      flutter::EncodableMap empty_args;
      HandleGetTextureInfo(args ? *args : empty_args, std::move(result));
      return;
    }
    if (method_call.method_name() == "disposeTexture") {
      const auto* args =
          std::get_if<flutter::EncodableMap>(method_call.arguments());
      flutter::EncodableMap empty_args;
      HandleDisposeTexture(args ? *args : empty_args, std::move(result));
      return;
    }
    result->NotImplemented();
  }

  void HandleGetTextureInfo(
      const flutter::EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const int64_t start_ms = NowMs();
    const std::string surface_id = GetSurfaceId(args);
    const int width =
        GetClampedInt(args, "width", kFallbackSize, 1, kMaxDimension);
    const int height =
        GetClampedInt(args, "height", kFallbackSize, 1, kMaxDimension);
    const int layer_count = GetClampedInt(
        args, "layerCount", kFallbackLayerCount, 1, kMaxLayerCount);
    const uint32_t background_color = GetBackgroundColor(args);
    PresentLog("getTextureInfo surface=" + surface_id + " size=" +
               std::to_string(width) + "x" + std::to_string(height) +
               " layers=" + std::to_string(layer_count));

    std::shared_ptr<SurfaceState> surface;
    std::shared_ptr<SurfaceState> invalid_pooled;
    bool reused_from_pool = false;
    {
      std::lock_guard<std::mutex> lock(surfaces_mutex_);
      auto it = surfaces_.find(surface_id);
      if (it != surfaces_.end()) {
        surface = it->second;
      } else {
        surface = TakePooledSurfaceLocked(width, height);
        if (surface && (surface->engine_handle == 0 || surface->texture_id < 0)) {
          invalid_pooled = surface;
          surface.reset();
        }
        if (surface && surface->engine_handle != 0 && surface->texture_id >= 0) {
          surface->surface_id = surface_id;
          surface->pooled = false;
          surface->last_used_ms = NowMs();
          surfaces_.emplace(surface_id, surface);
          reused_from_pool = true;
          PresentLog("reuse pooled surface surface=" + surface_id +
                     " texture=" + std::to_string(surface->texture_id) +
                     " handle=" + std::to_string(surface->engine_handle));
        } else {
          surface = std::make_shared<SurfaceState>();
          surface->surface_id = surface_id;
          surfaces_.emplace(surface_id, surface);
        }
      }
    }
    if (invalid_pooled) {
      std::lock_guard<std::mutex> lock(invalid_pooled->mutex);
      PresentLog("disposeTexture invalid pooled surface=" +
                 invalid_pooled->surface_id +
                 " handle=" + std::to_string(invalid_pooled->engine_handle) +
                 " texture=" + std::to_string(invalid_pooled->texture_id));
      UnregisterTextureLocked(invalid_pooled);
      if (invalid_pooled->engine_handle != 0) {
        engine_dispose(invalid_pooled->engine_handle);
        invalid_pooled->engine_handle = 0;
      }
    }

    uint64_t request_id = 0;
    {
      std::lock_guard<std::mutex> lock(surface->mutex);
      surface->disposed = false;
      if (surface->engine_handle != 0 && surface->texture_id >= 0 &&
          surface->width == width && surface->height == height &&
          surface->layer_count == layer_count) {
        PresentLog("reuse texture surface=" + surface_id +
                   " texture=" + std::to_string(surface->texture_id) +
                   " handle=" + std::to_string(surface->engine_handle));
        surface->background_color_argb = background_color;
        if (reused_from_pool) {
          surface->width = width;
          surface->height = height;
          surface->layer_count = layer_count;
          engine_reset_canvas_with_layers(surface->engine_handle,
                                          static_cast<uint32_t>(layer_count),
                                          background_color);
          PresentLog("reset_canvas pooled surface=" + surface_id +
                     " handle=" + std::to_string(surface->engine_handle) +
                     " layers=" + std::to_string(layer_count));
        }
        flutter::EncodableMap response;
        response[flutter::EncodableValue("textureId")] =
            flutter::EncodableValue(surface->texture_id);
        response[flutter::EncodableValue("engineHandle")] =
            flutter::EncodableValue(
                static_cast<int64_t>(surface->engine_handle));
        response[flutter::EncodableValue("width")] =
            flutter::EncodableValue(surface->width);
        response[flutter::EncodableValue("height")] =
            flutter::EncodableValue(surface->height);
        response[flutter::EncodableValue("isNewEngine")] =
            flutter::EncodableValue(reused_from_pool);
        result->Success(flutter::EncodableValue(response));
        return;
      }
      if (surface->engine_handle != 0 && surface->texture_id >= 0 &&
          surface->width == width && surface->height == height &&
          surface->layer_count != layer_count) {
        PresentLog("reuse texture (layer reset) surface=" + surface_id +
                   " texture=" + std::to_string(surface->texture_id) +
                   " handle=" + std::to_string(surface->engine_handle) +
                   " layers=" + std::to_string(layer_count));
        surface->background_color_argb = background_color;
        surface->layer_count = layer_count;
        engine_reset_canvas_with_layers(surface->engine_handle,
                                        static_cast<uint32_t>(layer_count),
                                        background_color);
        flutter::EncodableMap response;
        response[flutter::EncodableValue("textureId")] =
            flutter::EncodableValue(surface->texture_id);
        response[flutter::EncodableValue("engineHandle")] =
            flutter::EncodableValue(
                static_cast<int64_t>(surface->engine_handle));
        response[flutter::EncodableValue("width")] =
            flutter::EncodableValue(surface->width);
        response[flutter::EncodableValue("height")] =
            flutter::EncodableValue(surface->height);
        response[flutter::EncodableValue("isNewEngine")] =
            flutter::EncodableValue(true);
        result->Success(flutter::EncodableValue(response));
        return;
      }
      surface->request_id += 1;
      request_id = surface->request_id;
    }

    auto shared_result =
        std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(
            result.release());

    std::thread([this, surface, surface_id, width, height, layer_count,
                 background_color, request_id, shared_result, start_ms,
                 reused_from_pool]() mutable {
      const int64_t async_start_ms = NowMs();
      uint64_t handle = 0;
      bool engine_created = false;
      bool owns_handle = false;
      int64_t prev_texture_id = -1;
      int prev_width = 0;
      int prev_height = 0;
      int prev_layer_count = 0;
      {
        std::lock_guard<std::mutex> lock(surface->mutex);
        handle = surface->engine_handle;
        prev_texture_id = surface->texture_id;
        prev_width = surface->width;
        prev_height = surface->height;
        prev_layer_count = surface->layer_count;
      }

      bool resize_needed =
          handle != 0 &&
          (prev_width != width || prev_height != height);
      bool layer_changed =
          handle != 0 && prev_layer_count != layer_count;

      if (handle == 0) {
        handle = engine_create(static_cast<uint32_t>(width),
                               static_cast<uint32_t>(height));
        engine_created = true;
        owns_handle = true;
        PresentLog("engine_create handle=" + std::to_string(handle) +
                   " surface=" + surface_id);
      } else if (resize_needed) {
        if (engine_resize_canvas(handle, static_cast<uint32_t>(width),
                                 static_cast<uint32_t>(height),
                                 static_cast<uint32_t>(layer_count),
                                 background_color) == 0) {
          engine_dispose(handle);
          handle = engine_create(static_cast<uint32_t>(width),
                                 static_cast<uint32_t>(height));
          engine_created = true;
          owns_handle = true;
          PresentLog("engine_resize failed -> recreate handle=" +
                     std::to_string(handle) + " surface=" + surface_id);
        }
      }

      if (handle == 0) {
        PostCompletion([shared_result, surface_id, start_ms]() {
          shared_result->Error("engine_create_failed",
                               "engine_create returned 0",
                               flutter::EncodableValue());
          PresentLog("getTextureInfo failed surface=" + surface_id +
                     " elapsed_ms=" + std::to_string(NowMs() - start_ms));
        });
        return;
      }

      const bool needs_texture =
          engine_created || resize_needed || prev_texture_id < 0;
      void* shared_handle = nullptr;
      if (needs_texture) {
        PresentLog("create_present_dxgi_surface surface=" + surface_id +
                   " handle=" + std::to_string(handle) + " size=" +
                   std::to_string(width) + "x" + std::to_string(height));
        shared_handle = engine_create_present_dxgi_surface(
            handle, static_cast<uint32_t>(width),
            static_cast<uint32_t>(height));
        if (!shared_handle) {
          PostCompletion([shared_result, surface_id]() {
            shared_result->Error(
                "engine_create_present_failed",
                "engine_create_present_dxgi_surface returned null",
                flutter::EncodableValue());
          });
          return;
        }
        PresentLog("create_present_dxgi_surface ok surface=" + surface_id +
                   " handle=" + std::to_string(handle));
      }

      PostCompletion([this, surface, surface_id, width, height, layer_count,
                      background_color, handle, shared_handle, engine_created,
                      resize_needed, layer_changed, needs_texture, owns_handle,
                      request_id, shared_result, start_ms, async_start_ms,
                      reused_from_pool]() mutable {
        std::lock_guard<std::mutex> lock(surface->mutex);
        if (surface->disposed || surface->request_id != request_id) {
          if (shared_handle) {
            auto shared_handle_win = static_cast<HANDLE>(shared_handle);
            if (shared_handle_win) {
              CloseHandle(shared_handle_win);
            }
          }
          if (owns_handle && surface->engine_handle == 0) {
            engine_dispose(handle);
          }
          if (surface->engine_handle != 0 && surface->texture_id >= 0) {
            flutter::EncodableMap response;
            response[flutter::EncodableValue("textureId")] =
                flutter::EncodableValue(surface->texture_id);
            response[flutter::EncodableValue("engineHandle")] =
                flutter::EncodableValue(
                    static_cast<int64_t>(surface->engine_handle));
            response[flutter::EncodableValue("width")] =
                flutter::EncodableValue(surface->width);
            response[flutter::EncodableValue("height")] =
                flutter::EncodableValue(surface->height);
            response[flutter::EncodableValue("isNewEngine")] =
                flutter::EncodableValue(false);
            shared_result->Success(flutter::EncodableValue(response));
          } else {
            shared_result->Error("request_canceled",
                                 "getTextureInfo superseded",
                                 flutter::EncodableValue());
          }
          return;
        }

        surface->engine_handle = handle;
        surface->width = width;
        surface->height = height;
        surface->layer_count = layer_count;
        surface->background_color_argb = background_color;

        if (needs_texture) {
          UnregisterTextureLocked(surface);
          auto binding =
              std::make_shared<GpuSurfaceBinding>(shared_handle,
                                                  static_cast<size_t>(width),
                                                  static_cast<size_t>(height));

          FlutterDesktopTextureInfo texture_info{};
          texture_info.type = kFlutterDesktopGpuSurfaceTexture;
          texture_info.gpu_surface_config.struct_size =
              sizeof(FlutterDesktopGpuSurfaceTextureConfig);
          texture_info.gpu_surface_config.type =
              kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle;
          texture_info.gpu_surface_config.callback = GpuSurfaceBinding::Callback;
          texture_info.gpu_surface_config.user_data = binding.get();

          const int64_t texture_id =
              FlutterDesktopTextureRegistrarRegisterExternalTexture(
                  texture_registrar_, &texture_info);
          if (texture_id < 0) {
            auto shared_handle_win = static_cast<HANDLE>(shared_handle);
            if (shared_handle_win) {
              CloseHandle(shared_handle_win);
            }
            binding->shared_handle = nullptr;
            shared_result->Error("register_texture_failed",
                                 "RegisterExternalTexture returned < 0",
                                 flutter::EncodableValue());
            return;
          }

          surface->binding = std::move(binding);
          surface->texture_id = texture_id;
          surface->waiting_first_frame = true;
          surface->first_frame_start_ms = NowMs();
          surface->last_first_frame_log_ms = surface->first_frame_start_ms;
          surface->first_frame_poll_count = 0;
          surface->first_frame_force_logged = false;
          PresentLog("texture registered surface=" + surface_id +
                     " texture=" + std::to_string(texture_id) +
                     " handle=" + std::to_string(handle));
        } else if (shared_handle) {
          auto shared_handle_win = static_cast<HANDLE>(shared_handle);
          if (shared_handle_win) {
            CloseHandle(shared_handle_win);
          }
        }

        if (engine_created || resize_needed || layer_changed || reused_from_pool) {
          engine_reset_canvas_with_layers(handle,
                                          static_cast<uint32_t>(layer_count),
                                          background_color);
          PresentLog("reset_canvas surface=" + surface_id +
                     " handle=" + std::to_string(handle) +
                     " layers=" + std::to_string(layer_count));
        }

        flutter::EncodableMap response;
        response[flutter::EncodableValue("textureId")] =
            flutter::EncodableValue(surface->texture_id);
        response[flutter::EncodableValue("engineHandle")] =
            flutter::EncodableValue(
                static_cast<int64_t>(surface->engine_handle));
        response[flutter::EncodableValue("width")] =
            flutter::EncodableValue(surface->width);
        response[flutter::EncodableValue("height")] =
            flutter::EncodableValue(surface->height);
        response[flutter::EncodableValue("isNewEngine")] =
            flutter::EncodableValue(engine_created || resize_needed || reused_from_pool);
        shared_result->Success(flutter::EncodableValue(response));
        PresentLog("getTextureInfo done surface=" + surface_id +
                   " texture=" + std::to_string(surface->texture_id) +
                   " handle=" + std::to_string(surface->engine_handle) +
                   " newEngine=" +
                   std::to_string(engine_created || resize_needed || reused_from_pool) +
                   " elapsed_ms=" + std::to_string(NowMs() - start_ms) +
                   " async_ms=" + std::to_string(NowMs() - async_start_ms));
      });
    }).detach();
  }

  void HandleDisposeTexture(
      const flutter::EncodableMap& args,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const std::string surface_id = GetSurfaceId(args);
    PresentLog("disposeTexture request surface=" + surface_id);
    std::shared_ptr<SurfaceState> surface;
    std::vector<std::shared_ptr<SurfaceState>> to_dispose;
    {
      std::lock_guard<std::mutex> lock(surfaces_mutex_);
      auto it = surfaces_.find(surface_id);
      if (it != surfaces_.end()) {
        surface = it->second;
        surfaces_.erase(it);
      }
      if (surface) {
        std::lock_guard<std::mutex> lock_surface(surface->mutex);
        surface->request_id += 1;
        if (surface->engine_handle != 0 && surface->texture_id >= 0) {
          surface->disposed = false;
          surface->pooled = true;
          surface->last_used_ms = NowMs();
          pooled_surfaces_.push_back(surface);
          PresentLog("disposeTexture pooled surface=" + surface_id +
                     " handle=" + std::to_string(surface->engine_handle) +
                     " texture=" + std::to_string(surface->texture_id));
          TrimPoolLocked(to_dispose);
        } else {
          surface->disposed = true;
          to_dispose.push_back(surface);
        }
      }
    }
    if (!surface) {
      PresentLog("disposeTexture missing surface=" + surface_id);
    }
    for (const auto& entry : to_dispose) {
      if (!entry) {
        continue;
      }
      std::lock_guard<std::mutex> lock(entry->mutex);
      entry->disposed = true;
      PresentLog("disposeTexture surface=" + entry->surface_id +
                 " handle=" + std::to_string(entry->engine_handle) +
                 " texture=" + std::to_string(entry->texture_id));
      UnregisterTextureLocked(entry);
      if (entry->engine_handle != 0) {
        engine_dispose(entry->engine_handle);
        entry->engine_handle = 0;
      }
    }
    result->Success();
  }

  void DisposeAll() {
    std::vector<std::shared_ptr<SurfaceState>> entries;
    std::vector<std::shared_ptr<SurfaceState>> pooled;
    {
      std::lock_guard<std::mutex> lock(surfaces_mutex_);
      for (const auto& entry : surfaces_) {
        entries.push_back(entry.second);
      }
      surfaces_.clear();
      pooled.swap(pooled_surfaces_);
    }

    for (const auto& surface : entries) {
      if (!surface) {
        continue;
      }
      std::lock_guard<std::mutex> lock(surface->mutex);
      surface->disposed = true;
      surface->request_id += 1;
      UnregisterTextureLocked(surface);
      if (surface->engine_handle != 0) {
        engine_dispose(surface->engine_handle);
        surface->engine_handle = 0;
      }
    }
    for (const auto& surface : pooled) {
      if (!surface) {
        continue;
      }
      std::lock_guard<std::mutex> lock(surface->mutex);
      surface->disposed = true;
      surface->request_id += 1;
      UnregisterTextureLocked(surface);
      if (surface->engine_handle != 0) {
        engine_dispose(surface->engine_handle);
        surface->engine_handle = 0;
      }
    }
  }

  std::shared_ptr<SurfaceState> TakePooledSurfaceLocked(int width, int height) {
    if (pooled_surfaces_.empty()) {
      return nullptr;
    }
    for (size_t i = 0; i < pooled_surfaces_.size(); ++i) {
      const auto& entry = pooled_surfaces_[i];
      if (!entry) {
        continue;
      }
      if (entry->width == width && entry->height == height) {
        auto surface = entry;
        pooled_surfaces_.erase(pooled_surfaces_.begin() + i);
        return surface;
      }
    }
    return nullptr;
  }

  void TrimPoolLocked(
      std::vector<std::shared_ptr<SurfaceState>>& to_dispose) {
    uint64_t total_pixels = 0;
    for (const auto& entry : pooled_surfaces_) {
      if (!entry) {
        continue;
      }
      total_pixels +=
          static_cast<uint64_t>(entry->width) * static_cast<uint64_t>(entry->height);
    }

    auto should_trim = [&]() {
      return pooled_surfaces_.size() > kMaxPooledSurfaces ||
             total_pixels > kMaxPooledPixels;
    };

    while (should_trim()) {
      size_t oldest_index = 0;
      int64_t oldest_ts = std::numeric_limits<int64_t>::max();
      for (size_t i = 0; i < pooled_surfaces_.size(); ++i) {
        const auto& entry = pooled_surfaces_[i];
        if (!entry) {
          continue;
        }
        if (entry->last_used_ms < oldest_ts) {
          oldest_ts = entry->last_used_ms;
          oldest_index = i;
        }
      }
      if (oldest_ts == std::numeric_limits<int64_t>::max()) {
        break;
      }
      if (pooled_surfaces_.empty()) {
        break;
      }
      auto victim = pooled_surfaces_[oldest_index];
      pooled_surfaces_.erase(pooled_surfaces_.begin() + oldest_index);
      if (victim) {
        total_pixels -= static_cast<uint64_t>(victim->width) *
                        static_cast<uint64_t>(victim->height);
        to_dispose.push_back(victim);
      } else {
        break;
      }
    }
  }

  void PostCompletion(std::function<void()> task) {
    if (!task) {
      return;
    }
    if (!running_.load()) {
      return;
    }
    if (!message_window_) {
      task();
      return;
    }
    {
      std::lock_guard<std::mutex> lock(completions_mutex_);
      completions_.push_back(std::move(task));
    }
    PostMessage(message_window_, kAsyncCompletionMessage, 0, 0);
  }

  void DrainCompletions() {
    std::vector<std::function<void()>> tasks;
    {
      std::lock_guard<std::mutex> lock(completions_mutex_);
      tasks.swap(completions_);
    }
    for (auto& task : tasks) {
      if (task) {
        task();
      }
    }
  }

  void FrameLoop() {
    int64_t interval_us = QueryRefreshIntervalUs();
    auto next_refresh_check = std::chrono::steady_clock::now();
    auto next_tick = std::chrono::steady_clock::now() +
                     std::chrono::microseconds(interval_us);
    while (running_.load()) {
      std::vector<std::shared_ptr<SurfaceState>> entries;
      {
        std::lock_guard<std::mutex> lock(surfaces_mutex_);
        for (const auto& entry : surfaces_) {
          entries.push_back(entry.second);
        }
      }
      for (const auto& surface : entries) {
        if (!surface) {
          continue;
        }
        const int64_t texture_id = surface->RefreshFrame();
        if (texture_id >= 0) {
          FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(
              texture_registrar_, texture_id);
        }
      }
      auto now = std::chrono::steady_clock::now();
      if (now >= next_refresh_check) {
        interval_us = QueryRefreshIntervalUs();
        next_refresh_check = now + std::chrono::seconds(1);
      }
      if (next_tick <= now) {
        next_tick = now + std::chrono::microseconds(interval_us);
      }
      std::this_thread::sleep_until(next_tick);
      next_tick += std::chrono::microseconds(interval_us);
    }
  }

  void UnregisterTextureLocked(const std::shared_ptr<SurfaceState>& surface) {
    if (!surface || surface->texture_id < 0) {
      return;
    }
    const int64_t texture_id = surface->texture_id;
    PresentLog("unregister texture surface=" + surface->surface_id +
               " texture=" + std::to_string(texture_id));
    surface->texture_id = -1;
    surface->waiting_first_frame = false;
    surface->first_frame_start_ms = 0;
    surface->last_first_frame_log_ms = 0;
    surface->first_frame_poll_count = 0;
    surface->first_frame_force_logged = false;

    auto binding = surface->binding;
    surface->binding.reset();
    if (!binding) {
      return;
    }

    auto* keepalive = new std::shared_ptr<GpuSurfaceBinding>(binding);
    FlutterDesktopTextureRegistrarUnregisterExternalTexture(
        texture_registrar_, texture_id, ReleaseBinding, keepalive);
  }

  FlutterDesktopTextureRegistrarRef texture_registrar_;
  HWND message_window_ = nullptr;
  std::mutex completions_mutex_;
  std::vector<std::function<void()>> completions_;
  std::mutex surfaces_mutex_;
  std::unordered_map<std::string, std::shared_ptr<SurfaceState>> surfaces_;
  std::vector<std::shared_ptr<SurfaceState>> pooled_surfaces_;
  std::atomic<bool> running_;
  std::thread frame_thread_;
};

// static
void RustLibMisaRinPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar,
    FlutterDesktopPluginRegistrarRef raw_registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<RustLibMisaRinPlugin>(
      FlutterDesktopRegistrarGetTextureRegistrar(raw_registrar), registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

RustLibMisaRinPlugin::RustLibMisaRinPlugin(
    FlutterDesktopTextureRegistrarRef texture_registrar,
    flutter::PluginRegistrarWindows* registrar)
    : impl_(std::make_unique<Impl>(texture_registrar, registrar)) {}

RustLibMisaRinPlugin::~RustLibMisaRinPlugin() = default;

void RustLibMisaRinPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  impl_->HandleMethodCall(method_call, std::move(result));
}

}  // namespace rust_lib_misa_rin

void RustLibMisaRinPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  rust_lib_misa_rin::RustLibMisaRinPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar),
      registrar);
}
