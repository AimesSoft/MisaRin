use crate::gpu::brush_renderer::{
    BrushRenderer, BrushShape, Color, Point2D, PointRotation, MAX_POINTS,
};
use crate::gpu::debug::{self, LogLevel};

use super::types::EnginePoint;

#[derive(Clone, Copy, Debug)]
pub(crate) struct EngineBrushSettings {
    pub(crate) color_argb: u32,
    pub(crate) base_radius: f32,
    pub(crate) use_pressure: bool,
    pub(crate) erase: bool,
    pub(crate) antialias_level: u32,
    pub(crate) shape: BrushShape,
    pub(crate) random_rotation: bool,
    pub(crate) rotation_seed: u32,
    pub(crate) spacing: f32,
    pub(crate) hardness: f32,
    pub(crate) flow: f32,
    pub(crate) scatter: f32,
    pub(crate) rotation_jitter: f32,
    pub(crate) snap_to_pixel: bool,
    pub(crate) hollow_enabled: bool,
    pub(crate) hollow_ratio: f32,
    pub(crate) hollow_erase_occluded: bool,
    pub(crate) streamline_strength: f32,
}

impl Default for EngineBrushSettings {
    fn default() -> Self {
        Self {
            color_argb: 0xFFFFFFFF,
            base_radius: 6.0,
            use_pressure: true,
            erase: false,
            antialias_level: 1,
            shape: BrushShape::Circle,
            random_rotation: false,
            rotation_seed: 0,
            spacing: 0.15,
            hardness: 0.8,
            flow: 1.0,
            scatter: 0.0,
            rotation_jitter: 1.0,
            snap_to_pixel: false,
            hollow_enabled: false,
            hollow_ratio: 0.0,
            hollow_erase_occluded: false,
            streamline_strength: 0.0,
        }
    }
}

impl EngineBrushSettings {
    pub(crate) fn sanitize(&mut self) {
        if !self.base_radius.is_finite() {
            self.base_radius = 0.0;
        }
        if self.base_radius < 0.0 {
            self.base_radius = 0.0;
        }
        if !self.spacing.is_finite() {
            self.spacing = 0.15;
        } else {
            self.spacing = self.spacing.clamp(0.02, 2.5);
        }
        if !self.hardness.is_finite() {
            self.hardness = 0.8;
        } else {
            self.hardness = self.hardness.clamp(0.0, 1.0);
        }
        if !self.flow.is_finite() {
            self.flow = 1.0;
        } else {
            self.flow = self.flow.clamp(0.0, 1.0);
        }
        if !self.scatter.is_finite() {
            self.scatter = 0.0;
        } else {
            self.scatter = self.scatter.clamp(0.0, 1.0);
        }
        if !self.rotation_jitter.is_finite() {
            self.rotation_jitter = 1.0;
        } else {
            self.rotation_jitter = self.rotation_jitter.clamp(0.0, 1.0);
        }
        if !self.hollow_ratio.is_finite() {
            self.hollow_ratio = 0.0;
        } else {
            self.hollow_ratio = self.hollow_ratio.clamp(0.0, 1.0);
        }
        if !self.streamline_strength.is_finite() {
            self.streamline_strength = 0.0;
        } else {
            self.streamline_strength = self.streamline_strength.clamp(0.0, 1.0);
        }
        self.antialias_level = self.antialias_level.clamp(0, 9);
        self.color_argb = apply_flow_to_argb(self.color_argb, self.flow);
    }

    pub(crate) fn radius_from_pressure(&self, pressure: f32) -> f32 {
        brush_radius_from_pressure(pressure, self.base_radius, self.use_pressure)
    }

    pub(crate) fn softness(&self) -> f32 {
        (1.0 - self.hardness).clamp(0.0, 1.0)
    }
}

pub(crate) struct StreamlinePayload {
    pub(crate) points: Vec<(Point2D, f32)>,
    pub(crate) strength: f32,
}

struct ConsumedStrokePoints {
    points_len: usize,
    down_count: usize,
    up_count: usize,
    emitted: Vec<(Point2D, f32)>,
}

pub(crate) struct StrokeResampler {
    last_emitted: Option<Point2D>,
    last_pressure: f32,
    last_tick_dirty: Option<(i32, i32, i32, i32)>,
    last_tick_point: Option<Point2D>,
    streamline_points: Vec<(Point2D, f32)>,
    streamline_active: bool,
    streamline_strength: f32,
    resample_scale: f32,
}

impl StrokeResampler {
    pub(crate) fn new() -> Self {
        Self {
            last_emitted: None,
            last_pressure: 1.0,
            last_tick_dirty: None,
            last_tick_point: None,
            streamline_points: Vec::new(),
            streamline_active: false,
            streamline_strength: 0.0,
            resample_scale: 1.0,
        }
    }

    pub(crate) fn last_tick_dirty(&self) -> Option<(i32, i32, i32, i32)> {
        self.last_tick_dirty
    }

    pub(crate) fn last_tick_point(&self) -> Option<Point2D> {
        self.last_tick_point
    }

    pub(crate) fn set_resample_scale(&mut self, scale: f32) {
        let scale = if scale.is_finite() {
            scale.clamp(1.0, 8.0)
        } else {
            1.0
        };
        self.resample_scale = scale;
    }

    pub(crate) fn take_streamline_payload(&mut self) -> Option<StreamlinePayload> {
        if !self.streamline_active {
            self.streamline_points.clear();
            self.streamline_strength = 0.0;
            return None;
        }
        let points = std::mem::take(&mut self.streamline_points);
        let strength = self.streamline_strength;
        self.streamline_active = false;
        self.streamline_strength = 0.0;
        if points.len() < 2 || strength <= 0.0001 {
            return None;
        }
        Some(StreamlinePayload { points, strength })
    }

    fn begin_streamline(&mut self, strength: f32) {
        let strength = if strength.is_finite() {
            strength.clamp(0.0, 1.0)
        } else {
            0.0
        };
        self.streamline_strength = strength;
        self.streamline_active = strength > 0.0001;
        self.streamline_points.clear();
    }

    fn record_streamline_points(&mut self, emitted: &[(Point2D, f32)]) {
        if !self.streamline_active || emitted.is_empty() {
            return;
        }
        for (point, pressure) in emitted {
            if let Some((last_point, last_pressure)) = self.streamline_points.last() {
                let dx = point.x - last_point.x;
                let dy = point.y - last_point.y;
                let dist2 = dx * dx + dy * dy;
                if dist2 <= 1.0e-6 && (pressure - last_pressure).abs() <= 1.0e-4 {
                    continue;
                }
            }
            self.streamline_points.push((*point, *pressure));
        }
    }

    fn consume_points_internal(
        &mut self,
        brush_settings: &EngineBrushSettings,
        points: Vec<EnginePoint>,
    ) -> Option<ConsumedStrokePoints> {
        const FLAG_DOWN: u32 = 1;
        const FLAG_UP: u32 = 4;

        if points.is_empty() {
            if debug::level() >= LogLevel::Info && brush_settings.streamline_strength > 0.0001 {
                debug::log(
                    LogLevel::Info,
                    format_args!("stroke consume skipped: points=0"),
                );
            }
            self.last_tick_dirty = None;
            self.last_tick_point = None;
            return None;
        }

        let points_len = points.len();
        let mut emitted: Vec<(Point2D, f32)> = Vec::new();
        let mut down_count: usize = 0;
        let mut up_count: usize = 0;

        for p in points {
            let x = if p.x.is_finite() { p.x } else { 0.0 };
            let y = if p.y.is_finite() { p.y } else { 0.0 };
            let pressure = if p.pressure.is_finite() {
                p.pressure.clamp(0.0, 1.0)
            } else {
                0.0
            };

            let is_down = (p.flags & FLAG_DOWN) != 0;
            let is_up = (p.flags & FLAG_UP) != 0;
            if is_down {
                down_count += 1;
            }
            if is_up {
                up_count += 1;
            }
            if is_down {
                self.begin_streamline(brush_settings.streamline_strength);
            }

            let current = Point2D { x, y };
            if is_down || self.last_emitted.is_none() {
                self.last_emitted = Some(current);
                self.last_pressure = pressure;
                emitted.push((current, pressure));
                continue;
            }

            let Some(prev) = self.last_emitted else {
                continue;
            };

            let dx = current.x - prev.x;
            let dy = current.y - prev.y;
            let dist = (dx * dx + dy * dy).sqrt();
            if !dist.is_finite() || dist <= 0.0001 {
                if is_up {
                    emitted.push((current, pressure));
                    self.last_emitted = Some(current);
                    self.last_pressure = pressure;
                }
                continue;
            }

            let radius_prev = brush_settings.radius_from_pressure(self.last_pressure);
            let radius_next = brush_settings.radius_from_pressure(pressure);
            let mut step = resample_step_from_radius(
                (radius_prev + radius_next) * 0.5,
                brush_settings.spacing,
                self.resample_scale,
            );
            step = cap_resample_step_for_segment(dist, step);

            let dir_x = dx / dist;
            let dir_y = dy / dist;
            let mut traveled = 0.0f32;

            while traveled + step <= dist {
                traveled += step;
                let t = (traveled / dist).clamp(0.0, 1.0);
                let interp_pressure = self.last_pressure + (pressure - self.last_pressure) * t;
                let sample = Point2D {
                    x: prev.x + dir_x * traveled,
                    y: prev.y + dir_y * traveled,
                };
                emitted.push((sample, interp_pressure));
                self.last_emitted = Some(sample);
                self.last_pressure = interp_pressure;
            }

            if is_up {
                emitted.push((current, pressure));
                self.last_emitted = Some(current);
                self.last_pressure = pressure;
            }
        }

        let emitted = if emitted.len() > MAX_EMITTED_POINTS {
            let original_len = emitted.len();
            let reduced = downsample_emitted(&emitted, MAX_EMITTED_POINTS);
            if debug::level() >= LogLevel::Info {
                debug::log(
                    LogLevel::Info,
                    format_args!(
                        "stroke resample cap emitted={} -> {}",
                        original_len, MAX_EMITTED_POINTS
                    ),
                );
            }
            reduced
        } else {
            emitted
        };

        let emitted = if emitted.len() > 2 {
            fit_and_resample_points(emitted)
        } else {
            emitted
        };

        self.record_streamline_points(&emitted);

        if emitted.is_empty() {
            if debug::level() >= LogLevel::Info && brush_settings.streamline_strength > 0.0001 {
                debug::log(
                    LogLevel::Info,
                    format_args!(
                        "stroke consume skipped: points={points_len} down={down_count} up={up_count} emitted=0"
                    ),
                );
            }
            self.last_tick_dirty = None;
            self.last_tick_point = None;
            return None;
        }

        self.last_tick_point = emitted.last().map(|(point, _)| *point);
        self.last_tick_dirty = None;
        Some(ConsumedStrokePoints {
            points_len,
            down_count,
            up_count,
            emitted,
        })
    }

    pub(crate) fn consume_points(
        &mut self,
        brush_settings: &EngineBrushSettings,
        points: Vec<EnginePoint>,
    ) -> Vec<(Point2D, f32)> {
        self.consume_points_internal(brush_settings, points)
            .map(|out| out.emitted)
            .unwrap_or_default()
    }

    pub(crate) fn consume_and_draw<F: FnMut(&mut BrushRenderer, (i32, i32, i32, i32))>(
        &mut self,
        brush: &mut BrushRenderer,
        brush_settings: &EngineBrushSettings,
        layer_texture: &wgpu::Texture,
        layer_index: u32,
        layer_view: &wgpu::TextureView,
        points: Vec<EnginePoint>,
        canvas_width: u32,
        canvas_height: u32,
        before_draw: &mut F,
    ) -> bool {
        let Some(consumed) = self.consume_points_internal(brush_settings, points) else {
            return false;
        };
        let ConsumedStrokePoints {
            points_len,
            down_count,
            up_count,
            emitted,
        } = consumed;

        let drawn = self.draw_emitted_points(
            brush,
            brush_settings,
            layer_texture,
            layer_index,
            layer_view,
            &emitted,
            canvas_width,
            canvas_height,
            before_draw,
        );
        if debug::level() >= LogLevel::Info && brush_settings.streamline_strength > 0.0001 {
            debug::log(
                LogLevel::Info,
                format_args!(
                    "stroke consume drawn={drawn} points={points_len} down={down_count} up={up_count} emitted={}",
                    emitted.len()
                ),
            );
        }
        if !drawn && brush_settings.streamline_strength > 0.0001 {
            debug::log(
                LogLevel::Warn,
                format_args!(
                    "stroke consume no-draw points={points_len} down={down_count} up={up_count} emitted={}",
                    emitted.len()
                ),
            );
        }
        drawn
    }

    pub(crate) fn draw_emitted_points<F: FnMut(&mut BrushRenderer, (i32, i32, i32, i32))>(
        &mut self,
        brush: &mut BrushRenderer,
        brush_settings: &EngineBrushSettings,
        layer_texture: &wgpu::Texture,
        layer_index: u32,
        layer_view: &wgpu::TextureView,
        emitted: &[(Point2D, f32)],
        canvas_width: u32,
        canvas_height: u32,
        before_draw: &mut F,
    ) -> bool {
        self.last_tick_point = emitted.last().map(|(point, _)| *point);
        let (drew_any, dirty_union) = draw_emitted_points_internal(
            brush,
            brush_settings,
            layer_texture,
            layer_index,
            layer_view,
            emitted,
            canvas_width,
            canvas_height,
            before_draw,
        );
        self.last_tick_dirty = dirty_union;
        if !drew_any {
            self.last_tick_point = None;
        }
        drew_any
    }
}

fn draw_emitted_points_internal<F: FnMut(&mut BrushRenderer, (i32, i32, i32, i32))>(
    brush: &mut BrushRenderer,
    brush_settings: &EngineBrushSettings,
    layer_texture: &wgpu::Texture,
    layer_index: u32,
    layer_view: &wgpu::TextureView,
    emitted: &[(Point2D, f32)],
    canvas_width: u32,
    canvas_height: u32,
    before_draw: &mut F,
) -> (bool, Option<(i32, i32, i32, i32)>) {
    if emitted.is_empty() {
        return (false, None);
    }

    brush.set_canvas_size(canvas_width, canvas_height);
    let softness = brush_settings.softness();
    brush.set_softness(softness);

    let hollow_enabled = brush_settings.hollow_enabled
        && !brush_settings.erase
        && brush_settings.hollow_ratio > 0.0001;
    let hollow_ratio = if hollow_enabled {
        brush_settings.hollow_ratio
    } else {
        0.0
    };
    let hollow_erase = hollow_enabled && brush_settings.hollow_erase_occluded;

    let mut dirty_union: Option<(i32, i32, i32, i32)> = None;
    let mut drew_any = false;
    let dirty_scale = if softness > 0.0001 { 1.0 + softness } else { 1.0 };
    let (points, radii) = prepare_brush_samples(brush_settings, emitted);
    if points.is_empty() || points.len() != radii.len() {
        return (false, None);
    }

    let use_point_mode = true;
    if use_point_mode {
        let dirty_radii: Vec<f32> = radii.iter().map(|r| r * dirty_scale).collect();
        let dirty = compute_dirty_rect_i32(&points, &dirty_radii, canvas_width, canvas_height);
        before_draw(brush, dirty);

        let needs_rotation = brush_settings.random_rotation
            && brush_settings.rotation_jitter > 0.0001
            && !matches!(brush_settings.shape, BrushShape::Circle);
        let rotations = if needs_rotation {
            let mut rotations: Vec<PointRotation> = Vec::with_capacity(points.len());
            for point in &points {
                let angle =
                    brush_random_rotation_radians(*point, brush_settings.rotation_seed)
                        * brush_settings.rotation_jitter;
                rotations.push(PointRotation {
                    sin: angle.sin(),
                    cos: angle.cos(),
                });
            }
            Some(rotations)
        } else {
            None
        };

        let color = Color {
            argb: brush_settings.color_argb,
        };
        let mut start = 0usize;
        let mut any_drawn = false;
        while start < points.len() {
            let end = (start + MAX_POINTS).min(points.len());
            let pts = &points[start..end];
            let rs = &radii[start..end];
            let rot_slice = rotations.as_ref().map(|rots| &rots[start..end]);
            match brush.draw_points(
                layer_texture,
                layer_index,
                layer_view,
                pts,
                rs,
                None,
                rot_slice,
                color,
                brush_settings.shape,
                brush_settings.erase,
                brush_settings.antialias_level,
                softness,
                hollow_enabled,
                hollow_ratio,
                hollow_erase,
                hollow_enabled,
                true,
            ) {
                Ok(()) => {
                    any_drawn = true;
                }
                Err(err) => {
                    debug::log(
                        LogLevel::Warn,
                        format_args!("Brush draw_points failed: {err}"),
                    );
                }
            }
            start = end;
        }
        if any_drawn {
            drew_any = true;
            dirty_union = union_dirty_rect_i32(dirty_union, dirty);
        }
        return (drew_any, dirty_union);
    }

    if points.len() == 1 {
        let p0 = points[0];
        let r0 = radii[0];
        let dirty_r0 = r0 * dirty_scale;
        let dirty = compute_dirty_rect_i32(&[p0], &[dirty_r0], canvas_width, canvas_height);
        before_draw(brush, dirty);
        let rotation = if brush_settings.random_rotation
            && brush_settings.rotation_jitter > 0.0001
            && !matches!(brush_settings.shape, BrushShape::Circle)
        {
            brush_random_rotation_radians(p0, brush_settings.rotation_seed)
                * brush_settings.rotation_jitter
        } else {
            0.0
        };
        match brush.draw_stroke(
            layer_texture,
            layer_index,
            layer_view,
            &[p0],
            &[r0],
            Color {
                argb: brush_settings.color_argb,
            },
            brush_settings.shape,
            brush_settings.erase,
            brush_settings.antialias_level,
            rotation,
            hollow_enabled,
            hollow_ratio,
            hollow_erase,
            hollow_enabled,
            false,
        ) {
            Ok(()) => {
                drew_any = true;
                dirty_union = union_dirty_rect_i32(dirty_union, dirty);
            }
            Err(err) => {
                debug::log(
                    LogLevel::Warn,
                    format_args!("Brush draw_stroke failed: {err}"),
                );
            }
        }
    } else if hollow_enabled {
        let dirty_radii: Vec<f32> = radii.iter().map(|r| r * dirty_scale).collect();
        let dirty = compute_dirty_rect_i32(&points, &dirty_radii, canvas_width, canvas_height);
        before_draw(brush, dirty);
        let rotation = if brush_settings.random_rotation
            && brush_settings.rotation_jitter > 0.0001
            && !matches!(brush_settings.shape, BrushShape::Circle)
        {
            brush_random_rotation_radians(points[0], brush_settings.rotation_seed)
                * brush_settings.rotation_jitter
        } else {
            0.0
        };
        match brush.draw_stroke(
            layer_texture,
            layer_index,
            layer_view,
            &points,
            &radii,
            Color {
                argb: brush_settings.color_argb,
            },
            brush_settings.shape,
            brush_settings.erase,
            brush_settings.antialias_level,
            rotation,
            hollow_enabled,
            hollow_ratio,
            hollow_erase,
            hollow_enabled,
            false,
        ) {
            Ok(()) => {
                drew_any = true;
                dirty_union = union_dirty_rect_i32(dirty_union, dirty);
            }
            Err(err) => {
                debug::log(
                    LogLevel::Warn,
                    format_args!("Brush draw_stroke failed: {err}"),
                );
            }
        }
    } else {
        let needs_per_segment_rotation =
            brush_settings.random_rotation
                && brush_settings.rotation_jitter > 0.0001
                && !matches!(brush_settings.shape, BrushShape::Circle);
        let color = Color {
            argb: brush_settings.color_argb,
        };
        if needs_per_segment_rotation {
            for i in 0..points.len().saturating_sub(1) {
                let p0 = points[i];
                let p1 = points[i + 1];
                let r0 = radii[i];
                let r1 = radii[i + 1];
                let pts = [p0, p1];
                let radii = [r0, r1];
                let dirty_radii = [r0 * dirty_scale, r1 * dirty_scale];
                let dirty = compute_dirty_rect_i32(&pts, &dirty_radii, canvas_width, canvas_height);
                before_draw(brush, dirty);
                let rotation =
                    brush_random_rotation_radians(p0, brush_settings.rotation_seed)
                        * brush_settings.rotation_jitter;
                match brush.draw_stroke(
                    layer_texture,
                    layer_index,
                    layer_view,
                    &pts,
                    &radii,
                    color,
                    brush_settings.shape,
                    brush_settings.erase,
                    brush_settings.antialias_level,
                    rotation,
                    hollow_enabled,
                    hollow_ratio,
                    hollow_erase,
                    hollow_enabled,
                    false,
                ) {
                    Ok(()) => {
                        drew_any = true;
                        dirty_union = union_dirty_rect_i32(dirty_union, dirty);
                    }
                    Err(err) => {
                        debug::log(
                            LogLevel::Warn,
                            format_args!("Brush draw_stroke failed: {err}"),
                        );
                    }
                }
            }
        } else {
            const MAX_BATCH_POINTS: usize = 128;
            let mut batch_points: Vec<Point2D> = Vec::with_capacity(MAX_BATCH_POINTS + 1);
            let mut batch_radii: Vec<f32> = Vec::with_capacity(MAX_BATCH_POINTS + 1);
            let mut batch_dirty_union: Option<(i32, i32, i32, i32)> = None;

            for i in 0..points.len().saturating_sub(1) {
                let p0 = points[i];
                let p1 = points[i + 1];
                let r0 = radii[i];
                let r1 = radii[i + 1];
                let pts = [p0, p1];
                let dirty_radii = [r0 * dirty_scale, r1 * dirty_scale];
                let dirty = compute_dirty_rect_i32(&pts, &dirty_radii, canvas_width, canvas_height);
                before_draw(brush, dirty);
                batch_dirty_union = union_dirty_rect_i32(batch_dirty_union, dirty);

                if batch_points.is_empty() {
                    batch_points.push(p0);
                    batch_radii.push(r0);
                }
                batch_points.push(p1);
                batch_radii.push(r1);

                if batch_points.len() >= MAX_BATCH_POINTS {
                    match brush.draw_stroke(
                        layer_texture,
                        layer_index,
                        layer_view,
                        &batch_points,
                        &batch_radii,
                        color,
                        brush_settings.shape,
                        brush_settings.erase,
                        brush_settings.antialias_level,
                        0.0,
                        hollow_enabled,
                        hollow_ratio,
                        hollow_erase,
                        hollow_enabled,
                        false,
                    ) {
                        Ok(()) => {
                            drew_any = true;
                            if let Some(batch_dirty) = batch_dirty_union {
                                dirty_union = union_dirty_rect_i32(dirty_union, batch_dirty);
                            }
                        }
                        Err(err) => {
                            debug::log(
                                LogLevel::Warn,
                                format_args!("Brush draw_stroke failed: {err}"),
                            );
                        }
                    }
                    let last_point = *batch_points.last().expect("batch points not empty");
                    let last_radius = *batch_radii.last().expect("batch radii not empty");
                    batch_points.clear();
                    batch_radii.clear();
                    batch_points.push(last_point);
                    batch_radii.push(last_radius);
                    batch_dirty_union = None;
                }
            }

            if batch_points.len() > 1 {
                match brush.draw_stroke(
                    layer_texture,
                    layer_index,
                    layer_view,
                    &batch_points,
                    &batch_radii,
                    color,
                    brush_settings.shape,
                    brush_settings.erase,
                    brush_settings.antialias_level,
                    0.0,
                    hollow_enabled,
                    hollow_ratio,
                    hollow_erase,
                    hollow_enabled,
                    false,
                ) {
                    Ok(()) => {
                        drew_any = true;
                        if let Some(batch_dirty) = batch_dirty_union {
                            dirty_union = union_dirty_rect_i32(dirty_union, batch_dirty);
                        }
                    }
                    Err(err) => {
                        debug::log(
                            LogLevel::Warn,
                            format_args!("Brush draw_stroke failed: {err}"),
                        );
                    }
                }
            }
        }
    }

    (drew_any, dirty_union)
}

const RUST_PRESSURE_MIN_FACTOR: f32 = 0.09;
const MAX_SEGMENT_SAMPLES: usize = 64;
const MAX_EMITTED_POINTS: usize = 4096;

fn brush_radius_from_pressure(pressure: f32, base_radius: f32, use_pressure: bool) -> f32 {
    let base = if base_radius.is_finite() {
        base_radius.max(0.0)
    } else {
        0.0
    };
    if !use_pressure {
        return base;
    }
    let p = if pressure.is_finite() {
        pressure.clamp(0.0, 1.0)
    } else {
        0.0
    };
    base * (RUST_PRESSURE_MIN_FACTOR + (1.0 - RUST_PRESSURE_MIN_FACTOR) * p)
}

fn apply_flow_to_argb(color_argb: u32, flow: f32) -> u32 {
    if !flow.is_finite() || flow >= 0.9999 {
        return color_argb;
    }
    let clamped = flow.clamp(0.0, 1.0);
    let alpha = ((color_argb >> 24) & 0xFF) as f32;
    let scaled = (alpha * clamped).round().clamp(0.0, 255.0) as u32;
    (color_argb & 0x00FF_FFFF) | (scaled << 24)
}

fn snap_point_to_pixel(point: Point2D) -> Point2D {
    Point2D {
        x: point.x.floor() + 0.5,
        y: point.y.floor() + 0.5,
    }
}

fn snap_radius_to_pixel(radius: f32) -> f32 {
    if !radius.is_finite() {
        return radius;
    }
    (radius * 2.0).round() * 0.5
}

pub(crate) fn prepare_brush_samples(
    brush_settings: &EngineBrushSettings,
    emitted: &[(Point2D, f32)],
) -> (Vec<Point2D>, Vec<f32>) {
    let mut points: Vec<Point2D> = Vec::with_capacity(emitted.len());
    let mut radii: Vec<f32> = Vec::with_capacity(emitted.len());
    let scatter = brush_settings.scatter;
    let snap = brush_settings.snap_to_pixel;
    let scatter_seed = if brush_settings.random_rotation {
        brush_settings.rotation_seed
    } else {
        0
    };
    for (idx, (p, pres)) in emitted.iter().enumerate() {
        let mut radius = brush_settings.radius_from_pressure(*pres);
        if !radius.is_finite() || radius <= 0.0 {
            radius = 0.01;
        }
        let mut point = *p;
        if scatter > 0.0001 {
            let scatter_radius = radius.abs().max(0.01) * 2.0 * scatter;
            if scatter_radius > 0.0001 {
                let jitter = brush_scatter_offset(
                    point,
                    scatter_seed,
                    scatter_radius,
                    idx as u32,
                );
                point.x += jitter.x;
                point.y += jitter.y;
            }
        }
        if snap {
            point = snap_point_to_pixel(point);
            radius = snap_radius_to_pixel(radius);
        }
        if !radius.is_finite() || radius <= 0.0 {
            radius = 0.01;
        }
        points.push(point);
        radii.push(radius);
    }
    (points, radii)
}

fn resample_step_from_radius(radius: f32, spacing: f32, scale: f32) -> f32 {
    let r = if radius.is_finite() {
        radius.max(0.0)
    } else {
        0.0
    };
    let spacing = if spacing.is_finite() {
        spacing.clamp(0.02, 2.5)
    } else {
        0.15
    };
    let base = (r * 2.0 * spacing).max(0.1);
    let scale = if scale.is_finite() {
        scale.clamp(1.0, 8.0)
    } else {
        1.0
    };
    (base * scale).clamp(base, base * 8.0)
}

fn cap_resample_step_for_segment(dist: f32, step: f32) -> f32 {
    if !dist.is_finite() || dist <= 0.0 || !step.is_finite() || step <= 0.0 {
        return step;
    }
    let max_samples = MAX_SEGMENT_SAMPLES as f32;
    if dist / step > max_samples {
        dist / max_samples
    } else {
        step
    }
}

fn downsample_emitted(points: &[(Point2D, f32)], target_count: usize) -> Vec<(Point2D, f32)> {
    let len = points.len();
    if len <= target_count {
        return points.to_vec();
    }
    if target_count <= 1 {
        return vec![points[len.saturating_sub(1)]];
    }
    let last = len - 1;
    let mut output = Vec::with_capacity(target_count);
    for i in 0..target_count {
        let idx = (i * last) / (target_count - 1);
        output.push(points[idx]);
    }
    output
}

fn fit_and_resample_points(points: Vec<(Point2D, f32)>) -> Vec<(Point2D, f32)> {
    let target_count = points.len();
    if target_count < 3 {
        return points;
    }
    adaptive_resample_spline(&points, target_count)
}

pub(crate) fn apply_streamline(
    points: &[(Point2D, f32)],
    strength: f32,
) -> Vec<(Point2D, f32)> {
    let strength = if strength.is_finite() {
        strength.clamp(0.0, 1.0)
    } else {
        0.0
    };
    if strength <= 0.0001 || points.len() < 3 {
        return points.to_vec();
    }
    let eased = strength.powf(0.7);
    let passes = ((eased * 2.0).ceil() as usize).clamp(1, 3);
    let mut smoothed = adaptive_resample_spline(points, points.len());
    for _ in 1..passes {
        smoothed = adaptive_resample_spline(&smoothed, smoothed.len());
    }
    if smoothed.len() != points.len() {
        return points.to_vec();
    }
    let mut output: Vec<(Point2D, f32)> = Vec::with_capacity(points.len());
    for (orig, smooth) in points.iter().zip(smoothed.iter()) {
        let x = orig.0.x + (smooth.0.x - orig.0.x) * eased;
        let y = orig.0.y + (smooth.0.y - orig.0.y) * eased;
        let blended = orig.1 + (smooth.1 - orig.1) * (eased * 0.5);
        let pres = if blended.is_finite() {
            blended.clamp(0.0, 1.0)
        } else {
            orig.1
        };
        output.push((Point2D { x, y }, pres));
    }
    output
}

fn adaptive_resample_spline(points: &[(Point2D, f32)], target_count: usize) -> Vec<(Point2D, f32)> {
    if points.len() < 2 || target_count < 2 {
        return points.to_vec();
    }

    let mut turning: Vec<f32> = vec![0.0; points.len()];
    for i in 1..points.len().saturating_sub(1) {
        turning[i] = turning_angle(points[i - 1].0, points[i].0, points[i + 1].0);
    }

    let curvature_weight = 0.75f32;
    let mut weights: Vec<f32> = Vec::with_capacity(points.len().saturating_sub(1));
    let mut total_weight = 0.0f32;

    for i in 0..points.len().saturating_sub(1) {
        let length = point_distance(points[i].0, points[i + 1].0);
        let mut curvature = 0.0f32;
        let mut count = 0.0f32;
        if i > 0 {
            curvature += turning[i];
            count += 1.0;
        }
        if i + 1 < points.len().saturating_sub(1) {
            curvature += turning[i + 1];
            count += 1.0;
        }
        if count > 0.0 {
            curvature /= count;
        }
        let weight = (length * (1.0 + curvature_weight * curvature)).max(1.0e-4);
        weights.push(weight);
        total_weight += weight;
    }

    if !total_weight.is_finite() || total_weight <= 0.0 {
        return points.to_vec();
    }

    let mut output: Vec<(Point2D, f32)> = Vec::with_capacity(target_count);
    output.push(points[0]);

    let step = total_weight / (target_count.saturating_sub(1) as f32);
    if !step.is_finite() || step <= 0.0 {
        return points.to_vec();
    }

    let mut seg_index = 0usize;
    let mut seg_start = 0.0f32;
    let mut seg_end = weights[0];

    for sample_idx in 1..target_count.saturating_sub(1) {
        let target = step * sample_idx as f32;
        while target > seg_end && seg_index + 1 < weights.len() {
            seg_index += 1;
            seg_start = seg_end;
            seg_end += weights[seg_index];
        }

        let denom = (seg_end - seg_start).max(1.0e-6);
        let t = ((target - seg_start) / denom).clamp(0.0, 1.0);

        let p0 = if seg_index == 0 {
            points[0].0
        } else {
            points[seg_index - 1].0
        };
        let p1 = points[seg_index].0;
        let p2 = points[seg_index + 1].0;
        let p3 = if seg_index + 2 < points.len() {
            points[seg_index + 2].0
        } else {
            points[points.len() - 1].0
        };
        let pos = catmull_rom(p0, p1, p2, p3, t);
        let pres = points[seg_index].1 + (points[seg_index + 1].1 - points[seg_index].1) * t;
        output.push((pos, pres));
    }

    output.push(points[points.len() - 1]);
    output
}

fn point_distance(a: Point2D, b: Point2D) -> f32 {
    let dx = a.x - b.x;
    let dy = a.y - b.y;
    (dx * dx + dy * dy).sqrt()
}

fn turning_angle(prev: Point2D, curr: Point2D, next: Point2D) -> f32 {
    let v1x = curr.x - prev.x;
    let v1y = curr.y - prev.y;
    let v2x = next.x - curr.x;
    let v2y = next.y - curr.y;
    let len1 = (v1x * v1x + v1y * v1y).sqrt();
    let len2 = (v2x * v2x + v2y * v2y).sqrt();
    if len1 <= 1.0e-6 || len2 <= 1.0e-6 {
        return 0.0;
    }
    let cos = ((v1x * v2x + v1y * v2y) / (len1 * len2)).clamp(-1.0, 1.0);
    cos.acos()
}

fn catmull_rom(p0: Point2D, p1: Point2D, p2: Point2D, p3: Point2D, t: f32) -> Point2D {
    let t = if t.is_finite() {
        t.clamp(0.0, 1.0)
    } else {
        0.0
    };
    let t2 = t * t;
    let t3 = t2 * t;
    let x = 0.5
        * ((2.0 * p1.x)
            + (-p0.x + p2.x) * t
            + (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * t2
            + (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * t3);
    let y = 0.5
        * ((2.0 * p1.y)
            + (-p0.y + p2.y) * t
            + (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2
            + (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3);
    Point2D { x, y }
}

pub(crate) fn map_brush_shape(index: u32) -> BrushShape {
    // Dart enum: circle=0, triangle=1, square=2, star=3.
    match index {
        0 => BrushShape::Circle,
        1 => BrushShape::Triangle,
        2 => BrushShape::Square,
        3 => BrushShape::Star,
        _ => BrushShape::Circle,
    }
}

pub(crate) fn brush_random_rotation_radians(center: Point2D, seed: u32) -> f32 {
    let x = (center.x * 256.0).round() as i32;
    let y = (center.y * 256.0).round() as i32;

    let mut h: u32 = 0;
    h ^= seed;
    h ^= (x as u32).wrapping_mul(0x9e3779b1);
    h ^= (y as u32).wrapping_mul(0x85ebca77);
    h = mix32(h);

    let unit = (h as f64) / 4294967296.0;
    (unit * std::f64::consts::PI * 2.0) as f32
}

fn brush_random_unit(center: Point2D, seed: u32, salt: u32) -> f32 {
    let x = (center.x * 256.0).round() as i32;
    let y = (center.y * 256.0).round() as i32;

    let mut h: u32 = 0;
    h ^= seed;
    h ^= salt;
    h ^= (x as u32).wrapping_mul(0x9e3779b1);
    h ^= (y as u32).wrapping_mul(0x85ebca77);
    h = mix32(h);

    (h as f64 / 4294967296.0) as f32
}

fn brush_scatter_offset(center: Point2D, seed: u32, radius: f32, salt: u32) -> Point2D {
    if !radius.is_finite() || radius <= 0.0 {
        return Point2D { x: 0.0, y: 0.0 };
    }
    let u = brush_random_unit(center, seed, salt);
    let v = brush_random_unit(center, seed, salt.wrapping_add(1));
    let dist = u.sqrt() * radius;
    let angle = v * std::f32::consts::PI * 2.0;
    Point2D {
        x: angle.cos() * dist,
        y: angle.sin() * dist,
    }
}

fn mix32(mut h: u32) -> u32 {
    h ^= h >> 16;
    h = h.wrapping_mul(0x7feb352d);
    h ^= h >> 15;
    h = h.wrapping_mul(0x846ca68b);
    h ^= h >> 16;
    h
}

fn compute_dirty_rect_i32(
    points: &[Point2D],
    radii: &[f32],
    canvas_width: u32,
    canvas_height: u32,
) -> (i32, i32, i32, i32) {
    if canvas_width == 0 || canvas_height == 0 || points.is_empty() || points.len() != radii.len() {
        return (0, 0, 0, 0);
    }

    let mut min_x: f32 = f32::INFINITY;
    let mut min_y: f32 = f32::INFINITY;
    let mut max_x: f32 = f32::NEG_INFINITY;
    let mut max_y: f32 = f32::NEG_INFINITY;
    let mut max_r: f32 = 0.0;

    for (p, &r) in points.iter().zip(radii.iter()) {
        let x = if p.x.is_finite() { p.x } else { 0.0 };
        let y = if p.y.is_finite() { p.y } else { 0.0 };
        let radius = if r.is_finite() { r.max(0.0) } else { 0.0 };
        min_x = min_x.min(x);
        min_y = min_y.min(y);
        max_x = max_x.max(x);
        max_y = max_y.max(y);
        max_r = max_r.max(radius);
    }

    if !min_x.is_finite() || !min_y.is_finite() || !max_x.is_finite() || !max_y.is_finite() {
        return (0, 0, 0, 0);
    }

    let pad = max_r + 2.0;
    let left = ((min_x - pad).floor() as i64).clamp(0, canvas_width as i64);
    let top = ((min_y - pad).floor() as i64).clamp(0, canvas_height as i64);
    let right = ((max_x + pad).ceil() as i64).clamp(0, canvas_width as i64);
    let bottom = ((max_y + pad).ceil() as i64).clamp(0, canvas_height as i64);

    let width = (right - left).max(0) as i32;
    let height = (bottom - top).max(0) as i32;
    (left as i32, top as i32, width, height)
}

fn union_dirty_rect_i32(
    existing: Option<(i32, i32, i32, i32)>,
    candidate: (i32, i32, i32, i32),
) -> Option<(i32, i32, i32, i32)> {
    let (cl, ct, cw, ch) = candidate;
    if cw <= 0 || ch <= 0 {
        return existing;
    }
    let Some((el, et, ew, eh)) = existing else {
        return Some(candidate);
    };
    if ew <= 0 || eh <= 0 {
        return Some(candidate);
    }

    let el64 = el as i64;
    let et64 = et as i64;
    let er64 = el64 + ew as i64;
    let eb64 = et64 + eh as i64;

    let cl64 = cl as i64;
    let ct64 = ct as i64;
    let cr64 = cl64 + cw as i64;
    let cb64 = ct64 + ch as i64;

    let left = el64.min(cl64);
    let top = et64.min(ct64);
    let right = er64.max(cr64);
    let bottom = eb64.max(cb64);

    let width = (right - left).max(0) as i32;
    let height = (bottom - top).max(0) as i32;
    Some((left as i32, top as i32, width, height))
}
