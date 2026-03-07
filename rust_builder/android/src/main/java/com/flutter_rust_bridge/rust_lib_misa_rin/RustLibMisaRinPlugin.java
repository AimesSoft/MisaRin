package com.flutter_rust_bridge.rust_lib_misa_rin;

import android.graphics.SurfaceTexture;
import android.os.Handler;
import android.os.Looper;
import android.view.Surface;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class RustLibMisaRinPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private static final String CHANNEL_NAME = "misarin/rust_canvas_texture";
  private static final int FALLBACK_SIZE = 512;
  private static final int MAX_DIMENSION = 16384;
  private static final int FALLBACK_LAYER_COUNT = 1;
  private static final int MAX_LAYER_COUNT = 1024;
  private static final int FALLBACK_BACKGROUND = 0xFFFFFFFF;

  static {
    System.loadLibrary("rust_lib_misa_rin");
  }

  private MethodChannel channel;
  private TextureRegistry textureRegistry;
  private final Object lock = new Object();
  private final Map<String, SurfaceState> surfaces = new HashMap<>();
  private final ExecutorService initExecutor =
      Executors.newSingleThreadExecutor(r -> new Thread(r, "misa-rin-canvas-init"));
  private final Handler mainHandler = new Handler(Looper.getMainLooper());

  private static final class SurfaceState {
    final String surfaceId;
    TextureRegistry.SurfaceTextureEntry textureEntry;
    Surface surface;
    int width;
    int height;
    int layerCount;
    int backgroundColorArgb;
    long engineHandle;
    boolean initInProgress;
    boolean disposed;
    final List<MethodChannel.Result> pendingResults = new ArrayList<>();

    SurfaceState(String surfaceId, int width, int height) {
      this.surfaceId = surfaceId;
      this.width = width;
      this.height = height;
      this.layerCount = FALLBACK_LAYER_COUNT;
      this.backgroundColorArgb = FALLBACK_BACKGROUND;
      this.engineHandle = 0L;
    }
  }

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    textureRegistry = binding.getTextureRegistry();
    channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    channel.setMethodCallHandler(this);
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    if (channel != null) {
      channel.setMethodCallHandler(null);
      channel = null;
    }
    releaseAllSurfaces();
    textureRegistry = null;
    initExecutor.shutdown();
  }

  @Override
  public void onMethodCall(MethodCall call, MethodChannel.Result result) {
    switch (call.method) {
      case "getTextureInfo":
        RequestedInfo request = parseRequestedInfo(call.arguments);
        getTextureInfo(request, result);
        break;
      case "disposeTexture":
        String surfaceId = parseSurfaceId(call.arguments);
        disposeSurface(surfaceId, result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private static final class RequestedInfo {
    final String surfaceId;
    final int width;
    final int height;
    final int layerCount;
    final int backgroundColorArgb;

    RequestedInfo(
        String surfaceId,
        int width,
        int height,
        int layerCount,
        int backgroundColorArgb) {
      this.surfaceId = surfaceId;
      this.width = width;
      this.height = height;
      this.layerCount = layerCount;
      this.backgroundColorArgb = backgroundColorArgb;
    }
  }

  private RequestedInfo parseRequestedInfo(Object arguments) {
    int width = FALLBACK_SIZE;
    int height = FALLBACK_SIZE;
    int layerCount = FALLBACK_LAYER_COUNT;
    int background = FALLBACK_BACKGROUND;
    String surfaceId = "default";

    if (arguments instanceof Map) {
      Map<?, ?> args = (Map<?, ?>) arguments;
      width = clampInt(args.get("width"), FALLBACK_SIZE, 1, MAX_DIMENSION);
      height = clampInt(args.get("height"), FALLBACK_SIZE, 1, MAX_DIMENSION);
      layerCount = clampInt(args.get("layerCount"), FALLBACK_LAYER_COUNT, 1, MAX_LAYER_COUNT);
      background = readInt32(args.get("backgroundColorArgb"), FALLBACK_BACKGROUND);
      Object surfaceIdValue = args.get("surfaceId");
      if (surfaceIdValue instanceof String && !((String) surfaceIdValue).isEmpty()) {
        surfaceId = (String) surfaceIdValue;
      } else if (surfaceIdValue instanceof Number) {
        surfaceId = String.valueOf(((Number) surfaceIdValue).longValue());
      }
    }

    return new RequestedInfo(surfaceId, width, height, layerCount, background);
  }

  private String parseSurfaceId(Object arguments) {
    if (arguments instanceof Map) {
      Map<?, ?> args = (Map<?, ?>) arguments;
      Object surfaceIdValue = args.get("surfaceId");
      if (surfaceIdValue instanceof String && !((String) surfaceIdValue).isEmpty()) {
        return (String) surfaceIdValue;
      }
      if (surfaceIdValue instanceof Number) {
        return String.valueOf(((Number) surfaceIdValue).longValue());
      }
    }
    return "default";
  }

  private void getTextureInfo(RequestedInfo request, MethodChannel.Result result) {
    final SurfaceState entry;
    synchronized (lock) {
      entry = surfaces.computeIfAbsent(
          request.surfaceId,
          id -> new SurfaceState(id, request.width, request.height));
      if (!entry.initInProgress
          && entry.engineHandle != 0
          && entry.textureEntry != null
          && entry.width == request.width
          && entry.height == request.height
          && entry.layerCount == request.layerCount) {
        result.success(buildResponse(entry, false));
        return;
      }
      entry.pendingResults.add(result);
      if (entry.initInProgress) {
        return;
      }
      entry.initInProgress = true;
    }

    initExecutor.execute(() -> initSurface(request, entry));
  }

  private void initSurface(RequestedInfo request, SurfaceState entry) {
    if (textureRegistry == null) {
      completeWithError(entry, "plugin_detached", "Texture registry unavailable");
      return;
    }
    long prevHandle = entry.engineHandle;
    boolean engineCreated = false;
    boolean resizeOk = true;
    boolean needsResize = entry.width != request.width || entry.height != request.height;
    boolean layerChanged = entry.layerCount != request.layerCount;
    boolean shouldCreateTexture = entry.textureEntry == null || needsResize;

    long handle = entry.engineHandle;
    if (handle == 0) {
      handle = nativeEngineCreate(request.width, request.height);
      engineCreated = handle != 0;
    } else if (needsResize) {
      resizeOk =
          nativeEngineResize(
              handle,
              request.width,
              request.height,
              request.layerCount,
              request.backgroundColorArgb);
      if (!resizeOk) {
        nativeEngineDispose(handle);
        handle = nativeEngineCreate(request.width, request.height);
        engineCreated = handle != 0;
        resizeOk = handle != 0;
      }
    }

    if (handle == 0 || !resizeOk) {
      if (handle != 0 && handle != prevHandle) {
        nativeEngineDispose(handle);
      }
      releaseSurfaceEntry(entry);
      completeWithError(entry, "engine_create_failed", "engine_create returned 0");
      return;
    }

    if (shouldCreateTexture) {
      releaseSurfaceEntry(entry);
      TextureRegistry.SurfaceTextureEntry textureEntry =
          textureRegistry.createSurfaceTexture();
      SurfaceTexture surfaceTexture = textureEntry.surfaceTexture();
      surfaceTexture.setDefaultBufferSize(request.width, request.height);
      Surface surface = new Surface(surfaceTexture);
      entry.textureEntry = textureEntry;
      entry.surface = surface;
    }

    boolean attached = nativeEngineAttachSurface(handle, entry.surface, request.width, request.height);
    if (!attached) {
      if (handle != 0 && handle != prevHandle) {
        nativeEngineDispose(handle);
      }
      releaseSurfaceEntry(entry);
      completeWithError(entry, "attach_surface_failed", "nativeEngineAttachSurface failed");
      return;
    }

    if (engineCreated || needsResize || layerChanged) {
      nativeEngineResetCanvasWithLayers(
          handle, request.layerCount, request.backgroundColorArgb);
    }

    List<MethodChannel.Result> callbacks;
    synchronized (lock) {
      if (entry.disposed) {
        releaseSurfaceEntry(entry);
        nativeEngineDispose(handle);
        return;
      }
      entry.engineHandle = handle;
      entry.width = request.width;
      entry.height = request.height;
      entry.layerCount = request.layerCount;
      entry.backgroundColorArgb = request.backgroundColorArgb;
      entry.initInProgress = false;
      callbacks = new ArrayList<>(entry.pendingResults);
      entry.pendingResults.clear();
    }

    final Map<String, Object> response =
        buildResponse(entry, engineCreated || needsResize || layerChanged);
    mainHandler.post(() -> {
      for (MethodChannel.Result callback : callbacks) {
        callback.success(response);
      }
    });
  }

  private void completeWithError(SurfaceState entry, String code, String message) {
    List<MethodChannel.Result> callbacks;
    synchronized (lock) {
      entry.initInProgress = false;
      callbacks = new ArrayList<>(entry.pendingResults);
      entry.pendingResults.clear();
    }
    mainHandler.post(() -> {
      for (MethodChannel.Result callback : callbacks) {
        callback.error(code, message, null);
      }
    });
  }

  private Map<String, Object> buildResponse(SurfaceState entry, boolean isNewEngine) {
    Map<String, Object> response = new HashMap<>();
    long textureId = entry.textureEntry != null ? entry.textureEntry.id() : -1L;
    response.put("textureId", textureId);
    response.put("engineHandle", entry.engineHandle);
    response.put("width", entry.width);
    response.put("height", entry.height);
    response.put("isNewEngine", isNewEngine);
    return response;
  }

  private void disposeSurface(String surfaceId, MethodChannel.Result result) {
    SurfaceState entry;
    synchronized (lock) {
      entry = surfaces.remove(surfaceId);
      if (entry != null) {
        entry.disposed = true;
      }
    }

    if (entry != null) {
      List<MethodChannel.Result> callbacks;
      synchronized (lock) {
        callbacks = new ArrayList<>(entry.pendingResults);
        entry.pendingResults.clear();
      }
      for (MethodChannel.Result callback : callbacks) {
        callback.error("surface_disposed", "surface disposed", null);
      }
      releaseSurfaceEntry(entry);
      if (entry.engineHandle != 0) {
        nativeEngineDispose(entry.engineHandle);
        entry.engineHandle = 0;
      }
    }
    result.success(null);
  }

  private void releaseAllSurfaces() {
    List<SurfaceState> entries = new ArrayList<>();
    synchronized (lock) {
      entries.addAll(surfaces.values());
      surfaces.clear();
    }
    for (SurfaceState entry : entries) {
      entry.disposed = true;
      releaseSurfaceEntry(entry);
      if (entry.engineHandle != 0) {
        nativeEngineDispose(entry.engineHandle);
        entry.engineHandle = 0;
      }
    }
  }

  private void releaseSurfaceEntry(SurfaceState entry) {
    if (entry.surface != null) {
      entry.surface.release();
      entry.surface = null;
    }
    if (entry.textureEntry != null) {
      entry.textureEntry.release();
      entry.textureEntry = null;
    }
  }

  private static int clampInt(Object value, int fallback, int minValue, int maxValue) {
    if (value instanceof Number) {
      long raw = ((Number) value).longValue();
      if (raw < minValue) {
        return minValue;
      }
      if (raw > maxValue) {
        return maxValue;
      }
      return (int) raw;
    }
    return fallback;
  }

  private static int readInt32(Object value, int fallback) {
    if (value instanceof Number) {
      return (int) ((Number) value).longValue();
    }
    return fallback;
  }

  private static native long nativeEngineCreate(int width, int height);

  private static native boolean nativeEngineResize(
      long handle,
      int width,
      int height,
      int layerCount,
      int backgroundColorArgb);

  private static native void nativeEngineResetCanvasWithLayers(
      long handle,
      int layerCount,
      int backgroundColorArgb);

  private static native void nativeEngineDispose(long handle);

  private static native boolean nativeEngineAttachSurface(
      long handle,
      Surface surface,
      int width,
      int height);

  @SuppressWarnings("unused")
  private static native void nativeEngineSetLogLevel(int level);
}
