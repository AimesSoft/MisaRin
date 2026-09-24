//! Real GPU regressions for ordered input, imported canvases, and eyedropper.
use std::sync::atomic::Ordering;
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use super::engine::{create_engine, lookup_engine, EngineCommand};
use super::ffi;
use super::frame_events;
use super::types::EnginePoint;

const SIZE: u32 = 64;
const IMPORT_COLOR: u32 = 0xff2874b6;

struct Canvas(u64);

impl Canvas {
    fn attach_present(&self) {
        let (reply, rx) = mpsc::channel();
        self.send(EngineCommand::AttachPresentDxgi {
            width: SIZE,
            height: SIZE,
            reply,
        });
        let shared_handle = rx
            .recv_timeout(Duration::from_secs(30))
            .unwrap()
            .expect("DXGI surface");
        unsafe {
            winapi::um::handleapi::CloseHandle(shared_handle as winapi::um::winnt::HANDLE);
        }
    }

    fn imported() -> (Self, Vec<u32>) {
        let canvas = Self(create_engine(SIZE, SIZE).expect("GPU canvas"));
        canvas.send(EngineCommand::ResetCanvasWithLayers {
            layer_count: 2,
            background_color_argb: 0,
        });
        canvas.send(EngineCommand::SetActiveLayer { layer_index: 1 });
        let mut pixels = vec![0; (SIZE * SIZE) as usize];
        pixels[(8 * SIZE + 8) as usize] = IMPORT_COLOR;
        assert_eq!(
            ffi::engine_write_layer_async(canvas.0, 1, pixels.as_ptr(), pixels.len(), 0),
            1
        );
        (canvas, pixels)
    }

    fn send(&self, command: EngineCommand) {
        lookup_engine(self.0).unwrap().cmd_tx.send(command).unwrap();
    }

    fn dot(&self, x: f32, y: f32) {
        let points = [
            EnginePoint {
                x,
                y,
                pressure: 1.0,
                _pad0: 0.0,
                timestamp_us: 1000,
                flags: 1,
                pointer_id: 1,
            },
            EnginePoint {
                x,
                y,
                pressure: 1.0,
                _pad0: 0.0,
                timestamp_us: 2000,
                flags: 4,
                pointer_id: 1,
            },
        ];
        ffi::engine_push_points(self.0, points.as_ptr(), points.len());
    }

    fn pixels(&self, layer: u32) -> Vec<u32> {
        let (reply, rx) = mpsc::channel();
        self.send(EngineCommand::ReadLayer {
            layer_index: layer,
            reply,
        });
        rx.recv_timeout(Duration::from_secs(30))
            .expect("layer read completed")
            .expect("layer pixels")
    }

    fn sample(&self, x: u32, y: u32) -> Option<u32> {
        let (reply, rx) = mpsc::channel();
        self.send(EngineCommand::ReadPresentPixel { x, y, reply });
        rx.recv_timeout(Duration::from_secs(30))
            .expect("sample completed")
    }
}

impl Drop for Canvas {
    fn drop(&mut self) {
        ffi::engine_dispose(self.0);
    }
}

struct FrameHost {
    subscription: u64,
    worker: Option<thread::JoinHandle<()>>,
    frames: mpsc::Receiver<()>,
    wakeups: std::sync::Arc<std::sync::atomic::AtomicU64>,
}

impl FrameHost {
    fn new(handle: u64) -> Self {
        let subscription = frame_events::engine_frame_events_create();
        let (tx, frames) = mpsc::channel();
        let wakeups = std::sync::Arc::new(std::sync::atomic::AtomicU64::new(0));
        let worker_wakeups = wakeups.clone();
        let worker = thread::spawn(move || {
            while frame_events::engine_frame_events_wait(subscription) {
                worker_wakeups.fetch_add(1, Ordering::Relaxed);
                if ffi::engine_poll_frame_ready(handle) {
                    let _ = tx.send(());
                }
            }
        });
        Self {
            subscription,
            worker: Some(worker),
            frames,
            wakeups,
        }
    }

    fn wait_for_frame(&self) {
        self.frames
            .recv_timeout(Duration::from_secs(30))
            .expect("frame completion wakes native host");
    }
}

impl Drop for FrameHost {
    fn drop(&mut self) {
        frame_events::engine_frame_events_dispose(self.subscription);
        self.worker.take().unwrap().join().unwrap();
    }
}

#[test]
fn presented_canvases_and_native_hosts_sleep_then_deliver_input_and_undo() {
    let (canvas, original) = Canvas::imported();
    canvas.attach_present();
    ffi::engine_write_layer_async(canvas.0, 1, original.as_ptr(), original.len(), 0);
    assert_eq!(canvas.sample(8, 8), Some(IMPORT_COLOR));
    // Subscribe after GPU submission/texture registration to cover late hosts.
    let host = FrameHost::new(canvas.0);
    host.wait_for_frame();
    let (other, _) = Canvas::imported();
    other.attach_present();
    let other_host = FrameHost::new(other.0);
    other_host.wait_for_frame();
    thread::sleep(Duration::from_millis(150));
    while host.frames.try_recv().is_ok() {}
    let iterations = lookup_engine(canvas.0).unwrap().render_iterations;
    let other_iterations = lookup_engine(other.0).unwrap().render_iterations;
    let before = iterations.load(Ordering::Relaxed);
    let other_before = other_iterations.load(Ordering::Relaxed);
    let host_before = host.wakeups.load(Ordering::Relaxed);
    let other_host_before = other_host.wakeups.load(Ordering::Relaxed);
    thread::sleep(Duration::from_millis(300));
    assert_eq!(iterations.load(Ordering::Relaxed), before);
    assert_eq!(other_iterations.load(Ordering::Relaxed), other_before);
    assert_eq!(host.wakeups.load(Ordering::Relaxed), host_before);
    assert_eq!(
        other_host.wakeups.load(Ordering::Relaxed),
        other_host_before
    );
    canvas.dot(30.5, 30.5);
    host.wait_for_frame();
    assert_eq!(canvas.sample(30, 30), Some(0xffffffff));
    canvas.send(EngineCommand::Undo);
    host.wait_for_frame();
    assert_eq!(canvas.pixels(1), original);
    assert_eq!(
        other_iterations.load(Ordering::Relaxed),
        other_before,
        "drawing on one canvas must not wake an idle canvas render thread"
    );
}

#[test]
fn idle_canvas_sleeps_and_wakes_for_input_and_undo() {
    let (canvas, original) = Canvas::imported();
    assert_eq!(canvas.sample(8, 8), Some(IMPORT_COLOR));
    let iterations = lookup_engine(canvas.0).unwrap().render_iterations;
    thread::sleep(Duration::from_millis(100));
    let before = iterations.load(Ordering::Relaxed);
    thread::sleep(Duration::from_millis(300));
    let idle_iterations = iterations.load(Ordering::Relaxed) - before;
    eprintln!("idle render loop iterations over 300 ms: {idle_iterations}");
    assert_eq!(idle_iterations, 0, "an idle canvas must block on input");
    canvas.dot(30.5, 30.5);
    assert_eq!(canvas.sample(30, 30), Some(0xffffffff));
    canvas.send(EngineCommand::Undo);
    assert_eq!(canvas.pixels(1), original);
}

#[test]
fn imported_first_stroke_can_be_undone_immediately_and_redone() {
    let (canvas, original) = Canvas::imported();
    // No readback/sleep between import, first input and undo: they must retain
    // this order even while pipelines for the first stroke are being compiled.
    canvas.dot(30.5, 30.5);
    canvas.send(EngineCommand::Undo);
    assert_eq!(canvas.pixels(1), original);
    canvas.send(EngineCommand::Redo);
    assert_eq!(canvas.sample(30, 30), Some(0xffffffff));
    assert_eq!(canvas.sample(8, 8), Some(IMPORT_COLOR));
    canvas.send(EngineCommand::Undo);
    assert_eq!(canvas.pixels(1), original);
}

#[test]
fn immediate_eyedropper_observes_the_preceding_stroke() {
    let (canvas, _) = Canvas::imported();
    for x in [20, 35, 50] {
        canvas.dot(x as f32 + 0.5, 40.5);
        assert_eq!(canvas.sample(x, 40), Some(0xffffffff));
    }
    assert_eq!(canvas.sample(8, 8), Some(IMPORT_COLOR));
    assert_eq!(canvas.sample(60, 4), Some(0));
    assert_eq!(canvas.sample(SIZE, 0), None);
}

#[test]
fn eyedropper_uses_canvas_coordinates_and_color_with_view_overlays() {
    let (canvas, _) = Canvas::imported();
    for view_flags in [0, 1, 2, 3] {
        canvas.send(EngineCommand::SetViewFlags { view_flags });
        assert_eq!(canvas.sample(8, 8), Some(IMPORT_COLOR));
        assert_eq!(canvas.sample(SIZE - 1 - 8, 8), Some(0));
    }
}

#[test]
fn pending_stroke_keeps_its_layer_before_a_layer_switch() {
    let (canvas, original) = Canvas::imported();
    canvas.dot(30.5, 30.5);
    canvas.send(EngineCommand::SetActiveLayer { layer_index: 0 });
    canvas.dot(50.5, 50.5);
    let layer = canvas.pixels(1);
    assert_eq!(layer[(30 * SIZE + 30) as usize], 0xffffffff);
    assert_eq!(layer[(50 * SIZE + 50) as usize], 0);
    canvas.send(EngineCommand::Undo);
    assert_eq!(canvas.pixels(0), vec![0; (SIZE * SIZE) as usize]);
    canvas.send(EngineCommand::Undo);
    assert_eq!(canvas.pixels(1), original);
}

#[test]
fn thumbnail_reads_preserve_composite_sampling_state() {
    let (canvas, _) = Canvas::imported();
    canvas.send(EngineCommand::SetViewFlags { view_flags: 3 });
    let (reply, rx) = mpsc::channel();
    canvas.send(EngineCommand::ReadLayerPreview {
        layer_index: 1,
        width: 16,
        height: 16,
        reply,
    });
    assert_eq!(
        rx.recv_timeout(Duration::from_secs(30))
            .unwrap()
            .unwrap()
            .len(),
        16 * 16 * 4
    );
    assert_eq!(canvas.sample(8, 8), Some(IMPORT_COLOR));
    assert_eq!(canvas.sample(40, 40), Some(0));
}

#[test]
fn eyedropper_preserves_rgb_of_translucent_pixels_and_layer_opacity() {
    let (canvas, mut pixels) = Canvas::imported();
    for (x, alpha) in [(20, 1u32), (30, 128), (40, 255)] {
        pixels[(20 * SIZE + x) as usize] = (alpha << 24) | 0x2874b6;
    }
    assert_eq!(
        ffi::engine_write_layer_async(canvas.0, 1, pixels.as_ptr(), pixels.len(), 0),
        1
    );
    for (x, alpha) in [(20, 1u32), (30, 128), (40, 255)] {
        assert_eq!(canvas.sample(x, 20), Some((alpha << 24) | 0x2874b6));
    }
    canvas.send(EngineCommand::SetLayerOpacity {
        layer_index: 1,
        opacity: 0.5,
    });
    assert_eq!(canvas.sample(40, 20).unwrap() & 0xffffff, 0x2874b6);
    canvas.send(EngineCommand::SetLayerVisible {
        layer_index: 1,
        visible: false,
    });
    assert_eq!(canvas.sample(40, 20), Some(0));
}

#[test]
fn windows_shared_surface_and_streamline_first_stroke_undo() {
    let (canvas, original) = Canvas::imported();
    let (reply, rx) = mpsc::channel();
    canvas.send(EngineCommand::AttachPresentDxgi {
        width: SIZE,
        height: SIZE,
        reply,
    });
    let shared_handle = rx
        .recv_timeout(Duration::from_secs(30))
        .unwrap()
        .expect("DXGI surface");
    // No Flutter consumer in this test; close its transferred handle.
    unsafe {
        winapi::um::handleapi::CloseHandle(shared_handle as winapi::um::winnt::HANDLE);
    }
    // Surface attachment initializes the layers; the application uploads the
    // imported bitmap after attachment has completed.
    assert_eq!(
        ffi::engine_write_layer_async(canvas.0, 1, original.as_ptr(), original.len(), 0),
        1
    );
    assert_eq!(canvas.sample(8, 8), Some(IMPORT_COLOR));
    canvas.send(EngineCommand::SetBrush {
        color_argb: 0xffe83020,
        base_radius: 3.0,
        use_pressure: false,
        erase: false,
        antialias_level: 1,
        brush_shape: 0,
        random_rotation: false,
        smooth_rotation: false,
        rotation_seed: 0,
        spacing: 0.15,
        hardness: 1.0,
        flow: 1.0,
        scatter: 0.0,
        rotation_jitter: 0.0,
        snap_to_pixel: false,
        screentone_enabled: false,
        screentone_spacing: 10.0,
        screentone_dot_size: 0.6,
        screentone_rotation: 0.0,
        screentone_softness: 0.0,
        screentone_shape: 0,
        hollow_enabled: false,
        hollow_ratio: 0.0,
        hollow_erase_occluded: false,
        streamline_strength: 0.8,
        smoothing_mode: 1,
        stabilizer_strength: 0.0,
    });
    let points: Vec<_> = (0..6)
        .map(|i| EnginePoint {
            x: 20.5 + i as f32 * 4.0,
            y: 30.5,
            pressure: 1.0,
            _pad0: 0.0,
            timestamp_us: 1000 + i * 1000,
            flags: if i == 0 {
                1
            } else if i == 5 {
                4
            } else {
                2
            },
            pointer_id: 1,
        })
        .collect();
    ffi::engine_push_points(canvas.0, points.as_ptr(), points.len());
    assert_eq!(canvas.sample(30, 30), Some(0xffe83020));
    canvas.send(EngineCommand::Undo);
    assert_eq!(canvas.pixels(1), original);
    canvas.send(EngineCommand::Redo);
    assert_eq!(canvas.sample(30, 30), Some(0xffe83020));
}

#[test]
fn repeated_canvas_creation_and_pixel_sampling_complete() {
    let start = Instant::now();
    for _ in 0..3 {
        let (canvas, _) = Canvas::imported();
        for _ in 0..10 {
            assert_eq!(canvas.sample(8, 8), Some(IMPORT_COLOR));
        }
    }
    eprintln!("3 canvases + 30 one-pixel samples: {:?}", start.elapsed());
}
