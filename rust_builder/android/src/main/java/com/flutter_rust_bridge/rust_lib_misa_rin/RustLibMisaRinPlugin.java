package com.flutter_rust_bridge.rust_lib_misa_rin;

import android.graphics.SurfaceTexture;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Surface;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class RustLibMisaRinPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private static final String CHANNEL_NAME = "misarin/rust_canvas_texture";
  private static final String TAG = "MisaRinCanvas";
  private static final int FALLBACK_SIZE = 512;
  private static final int MAX_DIMENSION = 16384;
  private static final int FALLBACK_LAYER_COUNT = 1;
  private static final int MAX_LAYER_COUNT = 1024;
  private static final int FALLBACK_BACKGROUND = 0xFFFFFFFF;
  private static final int DEFAULT_LOG_LEVEL = 0; // OFF
  private static volatile boolean debugEnabled = false;

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
    final List<PendingResult> pendingResults = new ArrayList<>();

    SurfaceState(String surfaceId, int width, int height) {
      this.surfaceId = surfaceId;
      this.width = width;
      this.height = height;
      this.layerCount = FALLBACK_LAYER_COUNT;
      this.backgroundColorArgb = FALLBACK_BACKGROUND;
      this.engineHandle = 0L;
    }
  }

  private static final class PendingResult {
    final RequestedInfo request;
    final MethodChannel.Result result;

    PendingResult(RequestedInfo request, MethodChannel.Result result) {
      this.request = request;
      this.result = result;
    }
  }

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    textureRegistry = binding.getTextureRegistry();
    channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
    channel.setMethodCallHandler(this);
    nativeEngineSetLogLevel(resolveLogLevel());
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
      case "setDebug":
        debugEnabled = readBoolean(call.arguments, "enabled");
        if (debugEnabled) {
          Log.i(TAG, "backend canvas debug enabled");
        }
        result.success(null);
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

  private static final class SurfaceCreateResult {
    final TextureRegistry.SurfaceTextureEntry textureEntry;
    final Surface surface;
    final String error;

    SurfaceCreateResult(
        TextureRegistry.SurfaceTextureEntry textureEntry, Surface surface, String error) {
      this.textureEntry = textureEntry;
      this.surface = surface;
      this.error = error;
    }

    static SurfaceCreateResult error(String message) {
      return new SurfaceCreateResult(null, null, message);
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
        if (debugEnabled) {
          Log.i(
              TAG,
              "getTextureInfo hit cache surface="
                  + request.surfaceId
                  + " size="
                  + entry.width
                  + "x"
                  + entry.height
                  + " layers="
                  + entry.layerCount
                  + " handle="
                  + entry.engineHandle);
        }
        result.success(buildResponse(entry, false));
        return;
      }
      entry.pendingResults.add(new PendingResult(request, result));
      if (debugEnabled) {
        Log.i(
            TAG,
            "getTextureInfo request surface="
                + request.surfaceId
                + " size="
                + request.width
                + "x"
                + request.height
                + " layers="
                + request.layerCount
                + " initInProgress="
                + entry.initInProgress
                + " handle="
                + entry.engineHandle
                + " hasTexture="
                + (entry.textureEntry != null));
      }
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
    if (debugEnabled) {
      Log.i(
          TAG,
          "initSurface start surface="
              + request.surfaceId
              + " size="
              + request.width
              + "x"
              + request.height
              + " layers="
              + request.layerCount);
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
    if (debugEnabled) {
      Log.i(
          TAG,
          "engine init surface="
              + request.surfaceId
              + " handle="
              + handle
              + " created="
              + engineCreated
              + " resizeOk="
              + resizeOk
              + " needsResize="
              + needsResize);
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
      SurfaceCreateResult createResult = createSurfaceOnMainThread(request.width, request.height);
      if (createResult.textureEntry == null || createResult.surface == null) {
        if (handle != 0 && handle != prevHandle) {
          nativeEngineDispose(handle);
        }
        completeWithError(
            entry,
            "create_surface_failed",
            createResult.error != null ? createResult.error : "Surface creation failed");
        return;
      }
      entry.textureEntry = createResult.textureEntry;
      entry.surface = createResult.surface;
      if (debugEnabled) {
        Log.i(
            TAG,
            "surface created surface="
                + request.surfaceId
                + " textureId="
                + entry.textureEntry.id());
      }
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
    if (debugEnabled) {
      Log.i(
          TAG,
          "surface attached surface="
              + request.surfaceId
              + " handle="
              + handle
              + " textureId="
              + (entry.textureEntry != null ? entry.textureEntry.id() : -1));
    }

    if (engineCreated || needsResize || layerChanged) {
      nativeEngineResetCanvasWithLayers(
          handle, request.layerCount, request.backgroundColorArgb);
    }

    List<MethodChannel.Result> callbacks = new ArrayList<>();
    RequestedInfo nextRequest = null;
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
      if (!entry.pendingResults.isEmpty()) {
        List<PendingResult> remaining = new ArrayList<>();
        for (PendingResult pending : entry.pendingResults) {
          if (pending.request.width == entry.width
              && pending.request.height == entry.height
              && pending.request.layerCount == entry.layerCount) {
            callbacks.add(pending.result);
          } else {
            remaining.add(pending);
          }
        }
        entry.pendingResults.clear();
        entry.pendingResults.addAll(remaining);
        if (!entry.pendingResults.isEmpty()) {
          nextRequest = entry.pendingResults.get(entry.pendingResults.size() - 1).request;
          entry.initInProgress = true;
        }
      }
    }

    final Map<String, Object> response =
        buildResponse(entry, engineCreated || needsResize || layerChanged);
    mainHandler.post(() -> {
      for (MethodChannel.Result callback : callbacks) {
        callback.success(response);
      }
    });

    if (nextRequest != null) {
      final RequestedInfo followRequest = nextRequest;
      if (debugEnabled) {
        Log.i(
            TAG,
            "initSurface requeue surface="
                + followRequest.surfaceId
                + " size="
                + followRequest.width
                + "x"
                + followRequest.height
                + " layers="
                + followRequest.layerCount);
      }
      initExecutor.execute(() -> initSurface(followRequest, entry));
    }
  }

  private void completeWithError(SurfaceState entry, String code, String message) {
    List<MethodChannel.Result> callbacks = new ArrayList<>();
    synchronized (lock) {
      entry.initInProgress = false;
      for (PendingResult pending : entry.pendingResults) {
        callbacks.add(pending.result);
      }
      entry.pendingResults.clear();
    }
    if (debugEnabled) {
      Log.w(TAG, "initSurface error code=" + code + " msg=" + message);
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
      List<MethodChannel.Result> callbacks = new ArrayList<>();
      synchronized (lock) {
        for (PendingResult pending : entry.pendingResults) {
          callbacks.add(pending.result);
        }
        entry.pendingResults.clear();
      }
      for (MethodChannel.Result callback : callbacks) {
        callback.error("surface_disposed", "surface disposed", null);
      }
      if (debugEnabled) {
        Log.i(TAG, "disposeSurface surface=" + surfaceId);
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
      if (debugEnabled) {
        Log.i(
            TAG,
            "releaseSurfaceEntry surface="
                + entry.surfaceId
                + " textureId="
                + entry.textureEntry.id());
      }
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

  private SurfaceCreateResult createSurfaceOnMainThread(int width, int height) {
    if (Looper.myLooper() == Looper.getMainLooper()) {
      return createSurface(width, height);
    }
    final SurfaceCreateResult[] holder = new SurfaceCreateResult[1];
    final CountDownLatch latch = new CountDownLatch(1);
    mainHandler.post(() -> {
      try {
        holder[0] = createSurface(width, height);
      } catch (RuntimeException e) {
        holder[0] = SurfaceCreateResult.error("create_surface_exception: " + e.getMessage());
      } finally {
        latch.countDown();
      }
    });
    try {
      latch.await();
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return SurfaceCreateResult.error("create_surface_interrupted");
    }
    if (holder[0] == null) {
      return SurfaceCreateResult.error("create_surface_failed");
    }
    return holder[0];
  }

  private SurfaceCreateResult createSurface(int width, int height) {
    if (textureRegistry == null) {
      return SurfaceCreateResult.error("Texture registry unavailable");
    }
    TextureRegistry.SurfaceTextureEntry textureEntry = textureRegistry.createSurfaceTexture();
    SurfaceTexture surfaceTexture = textureEntry.surfaceTexture();
    surfaceTexture.setDefaultBufferSize(width, height);
    Surface surface = new Surface(surfaceTexture);
    return new SurfaceCreateResult(textureEntry, surface, null);
  }

  private static int readInt32(Object value, int fallback) {
    if (value instanceof Number) {
      return (int) ((Number) value).longValue();
    }
    return fallback;
  }

  private static int resolveLogLevel() {
    String raw = System.getProperty("misa_rin.rust_log_level");
    if (raw != null) {
      try {
        return Integer.parseInt(raw.trim());
      } catch (NumberFormatException ignored) {}
    }
    return DEFAULT_LOG_LEVEL;
  }

  private static boolean readBoolean(Object arguments, String key) {
    if (arguments instanceof Map) {
      Map<?, ?> args = (Map<?, ?>) arguments;
      Object value = args.get(key);
      if (value instanceof Boolean) {
        return (Boolean) value;
      }
      if (value instanceof Number) {
        return ((Number) value).intValue() != 0;
      }
      if (value instanceof String) {
        String raw = ((String) value).trim().toLowerCase();
        return raw.equals("1") || raw.equals("true") || raw.equals("yes") || raw.equals("on");
      }
    }
    return false;
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
