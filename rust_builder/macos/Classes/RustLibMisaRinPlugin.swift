import Cocoa
import CoreVideo
import FlutterMacOS
import Foundation
import Metal

@_silgen_name("engine_create")
private func engine_create(_ width: UInt32, _ height: UInt32) -> UInt64

@_silgen_name("engine_get_mtl_device")
private func engine_get_mtl_device(_ engineHandle: UInt64) -> UnsafeMutableRawPointer?

@_silgen_name("engine_attach_present_texture")
private func engine_attach_present_texture(
  _ engineHandle: UInt64,
  _ mtlTexturePtr: UnsafeMutableRawPointer?,
  _ width: UInt32,
  _ height: UInt32,
  _ bytesPerRow: UInt32
)

@_silgen_name("engine_dispose")
private func engine_dispose(_ engineHandle: UInt64)

@_silgen_name("engine_poll_frame_ready")
private func engine_poll_frame_ready(_ engineHandle: UInt64) -> Bool

@_silgen_name("engine_reset_canvas_with_layers")
private func engine_reset_canvas_with_layers(
  _ engineHandle: UInt64,
  _ layerCount: UInt32,
  _ backgroundColorArgb: UInt32
)

@_silgen_name("engine_resize_canvas")
private func engine_resize_canvas(
  _ engineHandle: UInt64,
  _ width: UInt32,
  _ height: UInt32,
  _ layerCount: UInt32,
  _ backgroundColorArgb: UInt32
) -> UInt8

// Keep CPU drawing symbols alive when Rust is statically linked on macOS.
@_silgen_name("cpu_brush_draw_stamp")
private func cpu_brush_draw_stamp(
  _ pixels: UnsafeMutablePointer<UInt32>?,
  _ pixelsLen: UInt,
  _ width: UInt32,
  _ height: UInt32,
  _ centerX: Float,
  _ centerY: Float,
  _ radius: Float,
  _ colorArgb: UInt32,
  _ brushShape: UInt32,
  _ antialiasLevel: UInt32,
  _ softness: Float,
  _ erase: UInt8,
  _ randomRotation: UInt8,
  _ rotationSeed: UInt32,
  _ rotationJitter: Float,
  _ snapToPixel: UInt8,
  _ selection: UnsafePointer<UInt8>?,
  _ selectionLen: UInt
) -> UInt8

@_silgen_name("cpu_brush_draw_capsule_segment")
private func cpu_brush_draw_capsule_segment(
  _ pixels: UnsafeMutablePointer<UInt32>?,
  _ pixelsLen: UInt,
  _ width: UInt32,
  _ height: UInt32,
  _ ax: Float,
  _ ay: Float,
  _ bx: Float,
  _ by: Float,
  _ startRadius: Float,
  _ endRadius: Float,
  _ colorArgb: UInt32,
  _ antialiasLevel: UInt32,
  _ includeStartCap: UInt8,
  _ erase: UInt8,
  _ selection: UnsafePointer<UInt8>?,
  _ selectionLen: UInt
) -> UInt8

@_silgen_name("cpu_brush_fill_polygon")
private func cpu_brush_fill_polygon(
  _ pixels: UnsafeMutablePointer<UInt32>?,
  _ pixelsLen: UInt,
  _ width: UInt32,
  _ height: UInt32,
  _ vertices: UnsafePointer<Float>?,
  _ verticesLen: UInt,
  _ radius: Float,
  _ colorArgb: UInt32,
  _ antialiasLevel: UInt32,
  _ softness: Float,
  _ erase: UInt8,
  _ selection: UnsafePointer<UInt8>?,
  _ selectionLen: UInt
) -> UInt8

private final class RustCanvasTexture: NSObject, FlutterTexture {
  fileprivate let pixelBuffer: CVPixelBuffer

  init(width: Int, height: Int) {
    var buffer: CVPixelBuffer?

    let attributes: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:],
      kCVPixelBufferMetalCompatibilityKey: true,
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ]

    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attributes as CFDictionary,
      &buffer
    )

    guard status == kCVReturnSuccess, let resolved = buffer else {
      fatalError("Failed to create CVPixelBuffer: \(status)")
    }

    pixelBuffer = resolved
    super.init()
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    return Unmanaged.passRetained(pixelBuffer)
  }
}

private final class RustCanvasSurfaceState {
  var surfaceId: String
  var texture: RustCanvasTexture
  var textureId: Int64?
  var textureWidth: Int
  var textureHeight: Int
  var layerCount: Int
  var engineHandle: UInt64
  var textureCache: CVMetalTextureCache?
  var presentTexture: CVMetalTexture?
  var initInProgress: Bool
  var pendingTextureInfoResults: [FlutterResult]

  init(surfaceId: String, width: Int, height: Int) {
    self.surfaceId = surfaceId
    self.texture = RustCanvasTexture(width: width, height: height)
    self.textureId = nil
    self.textureWidth = width
    self.textureHeight = height
    self.layerCount = 1
    self.engineHandle = 0
    self.textureCache = nil
    self.presentTexture = nil
    self.initInProgress = false
    self.pendingTextureInfoResults = []
  }
}

private func rustCanvasDisplayLinkCallback(
  displayLink: CVDisplayLink,
  inNow: UnsafePointer<CVTimeStamp>,
  inOutputTime: UnsafePointer<CVTimeStamp>,
  flagsIn: CVOptionFlags,
  flagsOut: UnsafeMutablePointer<CVOptionFlags>,
  displayLinkContext: UnsafeMutableRawPointer?
) -> CVReturn {
  guard let displayLinkContext else {
    return kCVReturnError
  }
  autoreleasepool {
    let plugin = Unmanaged<RustLibMisaRinPlugin>.fromOpaque(displayLinkContext).takeUnretainedValue()
    plugin.onDisplayLinkTick()
  }
  return kCVReturnSuccess
}

public final class RustLibMisaRinPlugin: NSObject, FlutterPlugin {
  private static let channelName = "misarin/rust_canvas_texture"
  private static var didRegister = false

  private let textureRegistry: FlutterTextureRegistry
  private let engineStateLock = NSLock()
  private var surfaces: [String: RustCanvasSurfaceState] = [:]
  private var idleSurfaces: [String: [RustCanvasSurfaceState]] = [:]
  // Disable pooling to guarantee per-project isolation.
  private let maxIdleSurfacesPerSize = 0
  private var displayLink: CVDisplayLink?
  private let engineInitQueue = DispatchQueue(label: "misarin.canvas.engine-init", qos: .userInitiated)
  private let presentLogEnabled: Bool
  private var presentLogLastMs: UInt64 = 0
  private var presentPollCount: UInt64 = 0
  private var presentPollReadyCount: UInt64 = 0
  private var presentTickCount: UInt64 = 0
  private var presentMainDispatchCount: UInt64 = 0
  private var presentMainDirectCount: UInt64 = 0
  private var presentMainExecCount: UInt64 = 0
  private var presentMainDelaySumMs: UInt64 = 0
  private var presentMainDelayMaxMs: UInt64 = 0
  private var pixelSampleLogCount: UInt32 = 0

  public static func register(with registrar: FlutterPluginRegistrar) {
    if didRegister {
      return
    }
    didRegister = true

    // Touch CPU brush symbols so they are not stripped from the linked framework.
    _ = cpu_brush_draw_stamp(
      nil,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      nil,
      0
    )
    _ = cpu_brush_draw_capsule_segment(
      nil,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      nil,
      0
    )
    _ = cpu_brush_fill_polygon(
      nil,
      0,
      0,
      0,
      nil,
      0,
      0,
      0,
      0,
      0,
      0,
      nil,
      0
    )

    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger)
    let instance = RustLibMisaRinPlugin(textureRegistry: registrar.textures)
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.startDisplayLink()
  }

  private init(textureRegistry: FlutterTextureRegistry) {
    self.textureRegistry = textureRegistry
    self.presentLogEnabled = RustLibMisaRinPlugin.isPresentLogEnabled()
    super.init()
  }

  deinit {
    if let displayLink {
      CVDisplayLinkStop(displayLink)
    }
    var handlesToDispose: [UInt64] = []
    var texturesToUnregister: [Int64] = []
    engineStateLock.lock()
    for entry in surfaces.values {
      if entry.engineHandle != 0 {
        handlesToDispose.append(entry.engineHandle)
      }
      if let id = entry.textureId {
        texturesToUnregister.append(id)
      }
    }
    surfaces.removeAll()
    for bucket in idleSurfaces.values {
      for entry in bucket {
        if entry.engineHandle != 0 {
          handlesToDispose.append(entry.engineHandle)
        }
        if let id = entry.textureId {
          texturesToUnregister.append(id)
        }
      }
    }
    idleSurfaces.removeAll()
    engineStateLock.unlock()

    for id in texturesToUnregister {
      textureRegistry.unregisterTexture(id)
    }
    for handle in handlesToDispose {
      engine_dispose(handle)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getTextureInfo":
      let requested = parseRequestedTextureInfo(arguments: call.arguments)
      getTextureInfo(
        surfaceId: requested.surfaceId,
        width: requested.width,
        height: requested.height,
        layerCount: requested.layerCount,
        backgroundColor: requested.backgroundColor,
        result: result
      )
    case "disposeTexture":
      let surfaceId = parseSurfaceId(arguments: call.arguments)
      disposeSurface(surfaceId: surfaceId, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func isPresentLogEnabled() -> Bool {
    guard let raw = ProcessInfo.processInfo.environment["MISA_RIN_RUST_GPU_LOG"] else {
      return false
    }
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.isEmpty {
      return false
    }
    switch normalized {
    case "0", "off", "false", "no", "warn", "warning":
      return false
    default:
      return true
    }
  }

  private func nowMs() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds / 1_000_000
  }

  private func presentLog(_ message: String) {
    guard presentLogEnabled else {
      return
    }
    NSLog("[misa-rin][rust][present] \(message)")
  }

  private func parseRequestedTextureInfo(
    arguments: Any?
  ) -> (surfaceId: String, width: Int, height: Int, layerCount: Int, backgroundColor: UInt32) {
    let fallbackWidth = 512
    let fallbackHeight = 512
    let fallbackSurfaceId = "default"
    let fallbackLayerCount = 1
    let fallbackBackground: UInt32 = 0xFFFFFFFF
    guard let dict = arguments as? [String: Any] else {
      return (fallbackSurfaceId, fallbackWidth, fallbackHeight, fallbackLayerCount, fallbackBackground)
    }
    let w = (dict["width"] as? NSNumber)?.intValue ?? fallbackWidth
    let h = (dict["height"] as? NSNumber)?.intValue ?? fallbackHeight
    let layerCountRaw = (dict["layerCount"] as? NSNumber)?.intValue ?? fallbackLayerCount
    let layerCount = max(1, min(layerCountRaw, 1024))
    let backgroundRaw = (dict["backgroundColorArgb"] as? NSNumber)?.uint64Value ?? UInt64(fallbackBackground)
    let backgroundColor = UInt32(truncatingIfNeeded: backgroundRaw)
    let surfaceIdValue = dict["surfaceId"]
    let surfaceId: String
    if let str = surfaceIdValue as? String, !str.isEmpty {
      surfaceId = str
    } else if let num = surfaceIdValue as? NSNumber {
      surfaceId = num.stringValue
    } else {
      surfaceId = fallbackSurfaceId
    }
    return (
      surfaceId,
      max(1, min(w, 16384)),
      max(1, min(h, 16384)),
      layerCount,
      backgroundColor
    )
  }

  private func parseSurfaceId(arguments: Any?) -> String {
    let fallbackSurfaceId = "default"
    guard let dict = arguments as? [String: Any] else {
      return fallbackSurfaceId
    }
    let surfaceIdValue = dict["surfaceId"]
    if let str = surfaceIdValue as? String, !str.isEmpty {
      return str
    }
    if let num = surfaceIdValue as? NSNumber {
      return num.stringValue
    }
    return fallbackSurfaceId
  }

  private func poolKey(width: Int, height: Int) -> String {
    return "\(width)x\(height)"
  }

  private func takeIdleSurface(width: Int, height: Int) -> RustCanvasSurfaceState? {
    if maxIdleSurfacesPerSize <= 0 {
      return nil
    }
    let key = poolKey(width: width, height: height)
    guard var bucket = idleSurfaces[key], !bucket.isEmpty else {
      return nil
    }
    let entry = bucket.removeLast()
    idleSurfaces[key] = bucket
    return entry
  }

  private func resetEntryForPooling(_ entry: RustCanvasSurfaceState) {
    if let textureId = entry.textureId {
      textureRegistry.unregisterTexture(textureId)
    }
    entry.pendingTextureInfoResults.removeAll()
    entry.initInProgress = false
    entry.presentTexture = nil
    entry.textureCache = nil
    entry.textureId = nil
  }

  private func addIdleSurface(_ entry: RustCanvasSurfaceState) {
    guard entry.engineHandle != 0 else {
      return
    }
    if maxIdleSurfacesPerSize <= 0 {
      destroySurfaceState(entry)
      return
    }
    let key = poolKey(width: entry.textureWidth, height: entry.textureHeight)
    var bucket = idleSurfaces[key] ?? []
    bucket.append(entry)
    while bucket.count > maxIdleSurfacesPerSize {
      let evicted = bucket.removeFirst()
      destroySurfaceState(evicted)
    }
    idleSurfaces[key] = bucket
  }

  private func destroySurfaceState(_ entry: RustCanvasSurfaceState) {
    if let textureId = entry.textureId {
      textureRegistry.unregisterTexture(textureId)
    }
    if entry.engineHandle != 0 {
      engineInitQueue.async {
        engine_dispose(entry.engineHandle)
      }
    }
  }

  private func getTextureInfo(
    surfaceId: String,
    width: Int,
    height: Int,
    layerCount: Int,
    backgroundColor: UInt32,
    result: @escaping FlutterResult
  ) {
    engineStateLock.lock()
    var reusedFromPool = false
    let entry: RustCanvasSurfaceState
    if let existing = surfaces[surfaceId] {
      entry = existing
    } else if let reused = takeIdleSurface(width: width, height: height) {
      reusedFromPool = true
      reused.surfaceId = surfaceId
      resetEntryForPooling(reused)
      surfaces[surfaceId] = reused
      entry = reused
    } else {
      let created = RustCanvasSurfaceState(surfaceId: surfaceId, width: width, height: height)
      surfaces[surfaceId] = created
      entry = created
    }
    let resolvedLayerCount = max(1, layerCount)
    let layerCountChanged = entry.layerCount != resolvedLayerCount
    entry.layerCount = resolvedLayerCount
    let hasMatchingEngine = entry.engineHandle != 0
      && entry.textureWidth == width
      && entry.textureHeight == height
    if hasMatchingEngine && entry.textureId != nil && !reusedFromPool && !layerCountChanged {
      let currentTextureId = entry.textureId!
      let currentWidth = entry.textureWidth
      let currentHeight = entry.textureHeight
      let currentHandle = entry.engineHandle
      engineStateLock.unlock()
      result([
        "textureId": currentTextureId,
        "engineHandle": NSNumber(value: currentHandle),
        "width": currentWidth,
        "height": currentHeight,
        "isNewEngine": false,
      ])
      return
    }
    if entry.initInProgress {
      entry.pendingTextureInfoResults.append(result)
      engineStateLock.unlock()
      return
    }
    entry.initInProgress = true
    entry.pendingTextureInfoResults.append(result)
    let handleToReuse = entry.engineHandle
    let needsResize = entry.textureWidth != width || entry.textureHeight != height
    let shouldRecreateTexture = needsResize || reusedFromPool
    let oldTextureId: Int64? = entry.textureId
    let existingTexture = entry.texture
    entry.engineHandle = 0
    entry.textureId = nil
    entry.presentTexture = nil
    engineStateLock.unlock()

    engineInitQueue.async { [weak self] in
      guard let self else {
        return
      }
      let unregisterOldTexture = {
        if let oldTextureId {
          DispatchQueue.main.async {
            self.textureRegistry.unregisterTexture(oldTextureId)
          }
        }
      }

      let targetTexture: RustCanvasTexture = shouldRecreateTexture
        ? RustCanvasTexture(width: width, height: height)
        : existingTexture

      let resolvedWidth = CVPixelBufferGetWidth(targetTexture.pixelBuffer)
      let resolvedHeight = CVPixelBufferGetHeight(targetTexture.pixelBuffer)
      self.clearPixelBuffer(targetTexture.pixelBuffer, to: backgroundColor)

      var handle = handleToReuse
      var engineCreated = false
      var resizeOk = true

      if handle == 0 {
        handle = engine_create(UInt32(resolvedWidth), UInt32(resolvedHeight))
        engineCreated = true
      } else if needsResize {
        resizeOk = engine_resize_canvas(
          handle,
          UInt32(resolvedWidth),
          UInt32(resolvedHeight),
          UInt32(resolvedLayerCount),
          backgroundColor
        ) != 0
        if !resizeOk {
          engine_dispose(handle)
          handle = engine_create(UInt32(resolvedWidth), UInt32(resolvedHeight))
          engineCreated = true
          resizeOk = handle != 0
        }
      }

      if handle == 0 || !resizeOk {
        unregisterOldTexture()
        DispatchQueue.main.async {
          self.completePendingTextureInfoRequests(
            surfaceId: surfaceId,
            response: FlutterError(code: "engine_create_failed", message: "engine_create returned 0", details: nil)
          )
        }
        return
      }

      guard let devicePtr = engine_get_mtl_device(handle) else {
        unregisterOldTexture()
        DispatchQueue.main.async {
          self.completePendingTextureInfoRequests(
            surfaceId: surfaceId,
            response: FlutterError(
              code: "engine_get_mtl_device_failed",
              message: "engine_get_mtl_device returned null",
              details: nil
            )
          )
        }
        return
      }

      let mtlDevice = Unmanaged<AnyObject>.fromOpaque(devicePtr).takeUnretainedValue() as! MTLDevice

      var cache: CVMetalTextureCache?
      let cacheStatus = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, mtlDevice, nil, &cache)
      guard cacheStatus == kCVReturnSuccess, let resolvedCache = cache else {
        unregisterOldTexture()
        DispatchQueue.main.async {
          self.completePendingTextureInfoRequests(
            surfaceId: surfaceId,
            response: FlutterError(
              code: "cv_metal_texture_cache_failed",
              message: "CVMetalTextureCacheCreate failed: \(cacheStatus)",
              details: nil
            )
          )
        }
        return
      }

      var cvTexture: CVMetalTexture?
      let bytesPerRow = CVPixelBufferGetBytesPerRow(targetTexture.pixelBuffer)
      let textureAttributes: [CFString: Any] = [
        kCVMetalTextureUsage: NSNumber(
          value: MTLTextureUsage.shaderRead.rawValue
            | MTLTextureUsage.shaderWrite.rawValue
            | MTLTextureUsage.renderTarget.rawValue
        )
      ]

      let texStatus = CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault,
        resolvedCache,
        targetTexture.pixelBuffer,
        textureAttributes as CFDictionary,
        .bgra8Unorm,
        resolvedWidth,
        resolvedHeight,
        0,
        &cvTexture
      )

      guard texStatus == kCVReturnSuccess, let resolvedCvTexture = cvTexture else {
        unregisterOldTexture()
        DispatchQueue.main.async {
          self.completePendingTextureInfoRequests(
            surfaceId: surfaceId,
            response: FlutterError(
              code: "cv_metal_texture_failed",
              message: "CVMetalTextureCacheCreateTextureFromImage failed: \(texStatus)",
              details: nil
            )
          )
        }
        return
      }

      guard let mtlTexture = CVMetalTextureGetTexture(resolvedCvTexture) else {
        unregisterOldTexture()
        DispatchQueue.main.async {
          self.completePendingTextureInfoRequests(
            surfaceId: surfaceId,
            response: FlutterError(
              code: "cv_metal_texture_get_failed",
              message: "CVMetalTextureGetTexture returned null",
              details: nil
            )
          )
        }
        return
      }

      let shouldResetCanvas = engineCreated || needsResize || reusedFromPool || layerCountChanged
      let texturePtr = Unmanaged.passRetained(mtlTexture as AnyObject).toOpaque()
      engine_attach_present_texture(
        handle,
        texturePtr,
        UInt32(resolvedWidth),
        UInt32(resolvedHeight),
        UInt32(bytesPerRow)
      )
      if shouldResetCanvas {
        engine_reset_canvas_with_layers(
          handle,
          UInt32(resolvedLayerCount),
          backgroundColor
        )
      }

      DispatchQueue.main.async {
        self.engineStateLock.lock()
        guard let entry = self.surfaces[surfaceId] else {
          unregisterOldTexture()
          self.engineStateLock.unlock()
          self.engineInitQueue.async {
            engine_dispose(handle)
          }
          return
        }
        if let oldTextureId {
          self.textureRegistry.unregisterTexture(oldTextureId)
        }
        entry.texture = targetTexture
        entry.textureWidth = resolvedWidth
        entry.textureHeight = resolvedHeight
        let resolvedTextureId = self.textureRegistry.register(entry.texture)
        entry.textureId = resolvedTextureId
        entry.engineHandle = handle
        entry.textureCache = resolvedCache
        entry.presentTexture = resolvedCvTexture
        self.engineStateLock.unlock()
        self.completePendingTextureInfoRequests(surfaceId: surfaceId, response: [
          "textureId": resolvedTextureId,
          "engineHandle": NSNumber(value: handle),
          "width": resolvedWidth,
          "height": resolvedHeight,
          "isNewEngine": engineCreated || needsResize || reusedFromPool,
        ])
      }
    }
  }

  private func disposeSurface(surfaceId: String, result: @escaping FlutterResult) {
    var pendingResults: [FlutterResult] = []
    engineStateLock.lock()
    if let entry = surfaces.removeValue(forKey: surfaceId) {
      pendingResults = entry.pendingTextureInfoResults
      resetEntryForPooling(entry)
      addIdleSurface(entry)
    }
    engineStateLock.unlock()

    for callback in pendingResults {
      callback(
        FlutterError(
          code: "surface_disposed",
          message: "surface disposed",
          details: nil
        )
      )
    }
    result(nil)
  }

  private func completePendingTextureInfoRequests(surfaceId: String, response: Any?) {
    engineStateLock.lock()
    guard let entry = surfaces[surfaceId] else {
      engineStateLock.unlock()
      return
    }
    let callbacks = entry.pendingTextureInfoResults
    entry.pendingTextureInfoResults.removeAll()
    entry.initInProgress = false
    engineStateLock.unlock()

    for callback in callbacks {
      callback(response)
    }
  }

  private func clearPixelBuffer(_ pixelBuffer: CVPixelBuffer, to colorArgb: UInt32) {
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      return
    }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let a = UInt8((colorArgb >> 24) & 0xFF)
    let r = UInt8((colorArgb >> 16) & 0xFF)
    let g = UInt8((colorArgb >> 8) & 0xFF)
    let b = UInt8(colorArgb & 0xFF)
    var pixel = UInt32(b) | (UInt32(g) << 8) | (UInt32(r) << 16) | (UInt32(a) << 24)
    for y in 0..<height {
      let rowPtr = baseAddress.advanced(by: y * bytesPerRow)
      memset_pattern4(rowPtr, &pixel, bytesPerRow)
    }
  }

  private func logPixelBufferSamplesIfNeeded(_ pixelBuffer: CVPixelBuffer, reason: String) {
    guard presentLogEnabled, pixelSampleLogCount < 6 else {
      return
    }
    pixelSampleLogCount &+= 1
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      presentLog("pixelBuffer samples reason=\(reason) baseAddress=null")
      return
    }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    guard width > 0, height > 0, bytesPerRow >= width * 4 else {
      presentLog("pixelBuffer samples reason=\(reason) invalid size=\(width)x\(height) bpr=\(bytesPerRow)")
      return
    }

    var stats = PixelSampleStats()
    var samples: [String] = []
    for point in pixelSamplePoints(width: width, height: height) {
      let offset = point.y * bytesPerRow + point.x * 4
      let ptr = baseAddress.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
      let b = UInt32(ptr[0])
      let g = UInt32(ptr[1])
      let r = UInt32(ptr[2])
      let a = UInt32(ptr[3])
      let argb = (a << 24) | (r << 16) | (g << 8) | b
      stats.push(argb)
      if point.logLabel {
        samples.append(
          "\(point.label)@\(point.x),\(point.y)=ARGB#\(hex8(argb))/BGRA(\(b),\(g),\(r),\(a))"
        )
      }
    }
    let sampleSummary = samples.joined(separator: "; ")
    presentLog(
      "pixelBuffer samples reason=\(reason) count=\(pixelSampleLogCount) size=\(width)x\(height) bpr=\(bytesPerRow) stats=\(stats.summary()) samples=[\(sampleSummary)]"
    )
  }

  private struct PixelSamplePoint {
    let label: String
    let x: Int
    let y: Int
    let logLabel: Bool
  }

  private struct PixelSampleStats {
    var total: UInt32 = 0
    var nonTransparent: UInt32 = 0
    var transparent: UInt32 = 0
    var purpleLike: UInt32 = 0
    var magentaLike: UInt32 = 0
    var buckets: [UInt32: UInt32] = [:]

    mutating func push(_ argb: UInt32) {
      total &+= 1
      let a = (argb >> 24) & 0xFF
      let r = (argb >> 16) & 0xFF
      let g = (argb >> 8) & 0xFF
      let b = argb & 0xFF
      if a <= 8 {
        transparent &+= 1
      } else {
        nonTransparent &+= 1
      }
      if a > 8, r > 160, b > 160, g < 96 {
        purpleLike &+= 1
      }
      if a > 8, r > 220, b > 180, g < 64 {
        magentaLike &+= 1
      }
      let bucket = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)
      buckets[bucket, default: 0] &+= 1
    }

    func summary() -> String {
      let dominant = buckets.max { lhs, rhs in lhs.value < rhs.value }.map { entry -> String in
        let r = (entry.key >> 8) & 0xF
        let g = (entry.key >> 4) & 0xF
        let b = entry.key & 0xF
        return "#\(String(r, radix: 16, uppercase: true))\(String(g, radix: 16, uppercase: true))\(String(b, radix: 16, uppercase: true))x count=\(entry.value)"
      } ?? "none"
      return "total=\(total) non_transparent=\(nonTransparent) transparent=\(transparent)(\(percent(transparent, total))%) purple_like=\(purpleLike)(\(percent(purpleLike, total))%) magenta_like=\(magentaLike)(\(percent(magentaLike, total))%) dominant_bucket=\(dominant)"
    }

    private func percent(_ count: UInt32, _ total: UInt32) -> String {
      guard total > 0 else {
        return "0.0"
      }
      let value = (Double(count) / Double(total)) * 100.0
      return String(format: "%.1f", value)
    }
  }

  private func pixelSamplePoints(width: Int, height: Int) -> [PixelSamplePoint] {
    let columns = 9
    let rows = 9
    var points: [PixelSamplePoint] = []
    for row in 0..<rows {
      for col in 0..<columns {
        let x = gridCoord(size: width, index: col, count: columns)
        let y = gridCoord(size: height, index: row, count: rows)
        let logLabel = (row == rows / 2 && col == columns / 2)
          || (row == 1 && col == 1)
          || (row == 1 && col + 2 == columns)
          || (row + 2 == rows && col == 1)
          || (row + 2 == rows && col + 2 == columns)
        points.append(PixelSamplePoint(label: "g\(col)x\(row)", x: x, y: y, logLabel: logLabel))
      }
    }
    return points
  }

  private func gridCoord(size: Int, index: Int, count: Int) -> Int {
    guard size > 1, count > 1 else {
      return 0
    }
    return (index * (size - 1)) / (count - 1)
  }

  private func hex8(_ value: UInt32) -> String {
    String(format: "%08X", value)
  }

  private func startDisplayLink() {
    var link: CVDisplayLink?
    let status = CVDisplayLinkCreateWithActiveCGDisplays(&link)
    guard status == kCVReturnSuccess, let link else {
      return
    }

    displayLink = link
    CVDisplayLinkSetOutputCallback(
      link,
      rustCanvasDisplayLinkCallback,
      Unmanaged.passUnretained(self).toOpaque()
    )
    CVDisplayLinkStart(link)
  }

  fileprivate func onDisplayLinkTick() {
    var entries: [(UInt64, Int64, CVPixelBuffer)] = []
    engineStateLock.lock()
    for entry in surfaces.values {
      if entry.engineHandle != 0, let textureId = entry.textureId {
        entries.append((entry.engineHandle, textureId, entry.texture.pixelBuffer))
      }
    }
    engineStateLock.unlock()
    var readyCount = 0
    for (handle, textureId, pixelBuffer) in entries {
      let ready = engine_poll_frame_ready(handle)
      if presentLogEnabled {
        presentPollCount &+= 1
        if ready {
          presentPollReadyCount &+= 1
        }
      }
      if ready {
        readyCount += 1
        logPixelBufferSamplesIfNeeded(pixelBuffer, reason: "frame_ready")
        if Thread.isMainThread {
          presentMainDirectCount &+= 1
          textureRegistry.textureFrameAvailable(textureId)
        } else {
          presentMainDispatchCount &+= 1
          let queuedAt = nowMs()
          DispatchQueue.main.async { [weak self, textureRegistry] in
            guard let self else {
              return
            }
            let delay = self.nowMs() &- queuedAt
            self.presentMainExecCount &+= 1
            self.presentMainDelaySumMs &+= delay
            if delay > self.presentMainDelayMaxMs {
              self.presentMainDelayMaxMs = delay
            }
            textureRegistry.textureFrameAvailable(textureId)
          }
        }
      }
    }
    if presentLogEnabled {
      presentTickCount &+= 1
      if readyCount > 0 {
        let threadTag = Thread.isMainThread ? "main" : "bg"
        presentLog("displayLink ready=\(readyCount) entries=\(entries.count) thread=\(threadTag)")
      }
      let now = nowMs()
      if now &- presentLogLastMs >= 1000 {
        let avgDelay = presentMainExecCount == 0
          ? 0
          : presentMainDelaySumMs / presentMainExecCount
        presentLog(
          "displayLink summary ticks=\(presentTickCount) polls=\(presentPollCount) ready=\(presentPollReadyCount) entries=\(entries.count) main_direct=\(presentMainDirectCount) main_dispatch=\(presentMainDispatchCount) main_exec=\(presentMainExecCount) main_delay_avg_ms=\(avgDelay) main_delay_max_ms=\(presentMainDelayMaxMs)"
        )
        presentLogLastMs = now
        presentTickCount = 0
        presentPollCount = 0
        presentPollReadyCount = 0
        presentMainDispatchCount = 0
        presentMainDirectCount = 0
        presentMainExecCount = 0
        presentMainDelaySumMs = 0
        presentMainDelayMaxMs = 0
      }
    }
  }
}
