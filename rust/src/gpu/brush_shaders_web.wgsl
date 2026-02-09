const EPS: f32 = 0.000001;

struct StrokePoint {
  pos: vec2<f32>,
  radius: f32,
  alpha: f32,
  rot_sin: f32,
  rot_cos: f32,
};

struct Config {
  canvas_width: u32,
  canvas_height: u32,
  origin_x: u32,
  origin_y: u32,
  region_width: u32,
  region_height: u32,
  point_count: u32,
  brush_shape: u32,        // 0: circle, 1: triangle, 2: square, 3: star
  erase_mode: u32,         // 0: paint, 1: erase
  antialias_level: u32,    // 0..9
  color_argb: u32,         // straight alpha ARGB8888
  softness: f32,           // 0.0..1.0 (extra edge feather as fraction of radius)
  rotation_sin: f32,       // sin(theta) for brush rotation
  rotation_cos: f32,       // cos(theta) for brush rotation
  hollow_mode: u32,        // 0: solid, 1: hollow
  hollow_ratio: f32,       // 0.0..1.0 (inner radius scale)
  hollow_erase: u32,       // 0: keep underlying, 1: erase underlying
  stroke_mask_mode: u32,  // 0: disabled, 1: use stroke hollow mask
  stroke_base_mode: u32,  // 0: disabled, 1: blend against stroke base
  stroke_accumulate_mode: u32, // 0: max coverage, 1: accumulate coverage
  stroke_mode: u32,       // 0: segments, 1: points
  selection_mask_mode: u32, // 0: disabled, 1: clip by selection mask
};

const SQRT2: f32 = 1.414213562;

@group(0) @binding(0)
var<storage, read> stroke_points: array<StrokePoint>;

@group(0) @binding(1)
var layer_in: texture_2d<u32>;

@group(0) @binding(2)
var layer_out: texture_storage_2d<r32uint, write>;

@group(0) @binding(3)
var<uniform> cfg: Config;

@group(0) @binding(4)
var stroke_mask_in: texture_2d<u32>;

@group(0) @binding(5)
var stroke_mask_out: texture_storage_2d<r32uint, write>;

@group(0) @binding(6)
var stroke_base: texture_2d<u32>;

@group(0) @binding(7)
var selection_mask: texture_2d<u32>;

fn clamp01(x: f32) -> f32 {
  return clamp(x, 0.0, 1.0);
}

fn to_u8(x: f32) -> u32 {
  let v = floor(clamp01(x) * 255.0 + 0.5);
  return u32(clamp(v, 0.0, 255.0));
}

fn pack_argb(a: f32, r: f32, g: f32, b: f32) -> u32 {
  let aa = to_u8(a);
  let rr = to_u8(r);
  let gg = to_u8(g);
  let bb = to_u8(b);
  return (aa << 24u) | (rr << 16u) | (gg << 8u) | bb;
}

fn unpack_a(c: u32) -> f32 {
  return f32((c >> 24u) & 0xFFu) / 255.0;
}

fn unpack_r(c: u32) -> f32 {
  return f32((c >> 16u) & 0xFFu) / 255.0;
}

fn unpack_g(c: u32) -> f32 {
  return f32((c >> 8u) & 0xFFu) / 255.0;
}

fn unpack_b(c: u32) -> f32 {
  return f32(c & 0xFFu) / 255.0;
}

fn unpack_inner_mask(c: u32) -> f32 {
  return f32(c & 0xFFu) / 255.0;
}

fn unpack_outer_mask(c: u32) -> f32 {
  return f32((c >> 8u) & 0xFFu) / 255.0;
}

fn pack_mask(inner: f32, outer: f32) -> u32 {
  let inner_u = to_u8(inner);
  let outer_u = to_u8(outer);
  return (outer_u << 8u) | inner_u;
}

fn antialias_feather(level: u32) -> f32 {
  if (level == 0u) {
    return 0.0;
  }
  if (level == 1u) {
    return 0.7;
  }
  if (level == 2u) {
    return 1.1;
  }
  if (level == 3u) {
    return 1.6;
  }
  if (level == 4u) {
    return 1.9;
  }
  if (level == 5u) {
    return 2.2;
  }
  if (level == 6u) {
    return 2.5;
  }
  if (level == 7u) {
    return 2.8;
  }
  if (level == 8u) {
    return 3.1;
  }
  return 3.4;
}

fn brush_alpha(dist: f32, radius: f32, softness: f32) -> f32 {
  if (radius <= 0.0) {
    return 0.0;
  }
  let s = clamp(softness, 0.0, 1.0);
  let aa_feather = antialias_feather(cfg.antialias_level);
  let edge = max(aa_feather, radius * s);
  if (edge <= 0.0) {
    return select(0.0, 1.0, dist <= radius);
  }
  let inner = max(radius - edge, 0.0);
  let outer = radius + edge;
  if (dist <= inner) {
    return 1.0;
  }
  if (dist >= outer) {
    return 0.0;
  }
  return (outer - dist) / (outer - inner);
}

fn closest_t_to_segment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let ab = b - a;
  let ap = p - a;
  let ab_len2 = dot(ab, ab);
  if (ab_len2 <= EPS) {
    return 0.0;
  }
  return clamp(dot(ap, ab) / ab_len2, 0.0, 1.0);
}

fn rotate_to_brush_space(v: vec2<f32>, rot_sin: f32, rot_cos: f32) -> vec2<f32> {
  return vec2<f32>(
    v.x * rot_cos + v.y * rot_sin,
    -v.x * rot_sin + v.y * rot_cos,
  );
}

fn tri_vert(i: u32) -> vec2<f32> {
  if (i == 0u) {
    return vec2<f32>(0.000000000, -1.000000000);
  }
  if (i == 1u) {
    return vec2<f32>(0.866025404, 0.500000000);
  }
  return vec2<f32>(-0.866025404, 0.500000000);
}

fn star_vert(i: u32) -> vec2<f32> {
  if (i == 0u) {
    return vec2<f32>(0.000000000, -1.000000000);
  }
  if (i == 1u) {
    return vec2<f32>(0.224513988, -0.309016994);
  }
  if (i == 2u) {
    return vec2<f32>(0.951056516, -0.309016994);
  }
  if (i == 3u) {
    return vec2<f32>(0.363271264, 0.118033989);
  }
  if (i == 4u) {
    return vec2<f32>(0.587785252, 0.809016994);
  }
  if (i == 5u) {
    return vec2<f32>(0.000000000, 0.381966011);
  }
  if (i == 6u) {
    return vec2<f32>(-0.587785252, 0.809016994);
  }
  if (i == 7u) {
    return vec2<f32>(-0.363271264, 0.118033989);
  }
  if (i == 8u) {
    return vec2<f32>(-0.951056516, -0.309016994);
  }
  return vec2<f32>(-0.224513988, -0.309016994);
}

fn segment_distance(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
  let t = closest_t_to_segment(p, a, b);
  let c = a + (b - a) * t;
  return length(p - c);
}

fn signed_distance_box(p: vec2<f32>, half_size: vec2<f32>) -> f32 {
  let d = abs(p) - half_size;
  let outside = length(max(d, vec2<f32>(0.0, 0.0)));
  let inside = min(max(d.x, d.y), 0.0);
  return outside + inside;
}

fn signed_distance_triangle_unit(p: vec2<f32>) -> f32 {
  var min_dist = 1e9;
  var inside = false;
  var j: u32 = 2u;
  for (var i: u32 = 0u; i < 3u; i = i + 1u) {
    let a = tri_vert(j);
    let b = tri_vert(i);
    min_dist = min(min_dist, segment_distance(p, a, b));
    if ((a.y > p.y) != (b.y > p.y)) {
      let x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y);
      if (p.x < x) {
        inside = !inside;
      }
    }
    j = i;
  }
  return select(min_dist, -min_dist, inside);
}

fn signed_distance_star_unit(p: vec2<f32>) -> f32 {
  var min_dist = 1e9;
  var inside = false;
  var j: u32 = 9u;
  for (var i: u32 = 0u; i < 10u; i = i + 1u) {
    let a = star_vert(j);
    let b = star_vert(i);
    min_dist = min(min_dist, segment_distance(p, a, b));
    if ((a.y > p.y) != (b.y > p.y)) {
      let x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y);
      if (p.x < x) {
        inside = !inside;
      }
    }
    j = i;
  }
  return select(min_dist, -min_dist, inside);
}

fn shape_distance_to_point(
  sample_pos: vec2<f32>,
  center: vec2<f32>,
  radius: f32,
  rot_sin: f32,
  rot_cos: f32,
) -> f32 {
  let rel = rotate_to_brush_space(sample_pos - center, rot_sin, rot_cos);
  if (cfg.brush_shape == 0u) {
    return length(rel);
  }
  if (radius <= EPS) {
    return radius;
  }
  if (cfg.brush_shape == 2u) {
    let half_side = radius / SQRT2;
    let sd = signed_distance_box(rel, vec2<f32>(half_side, half_side));
    return radius + sd;
  }
  let inv_r = 1.0 / radius;
  let rel_unit = rel * inv_r;
  var sd_unit = signed_distance_triangle_unit(rel_unit);
  if (cfg.brush_shape == 3u) {
    sd_unit = signed_distance_star_unit(rel_unit);
  }
  return radius + sd_unit * radius;
}

fn shape_distance_to_segment(
  sample_pos: vec2<f32>,
  a: vec2<f32>,
  b: vec2<f32>,
  radius: f32,
  rot_sin: f32,
  rot_cos: f32,
) -> f32 {
  let t = closest_t_to_segment(sample_pos, a, b);
  let c = a + (b - a) * t;
  return shape_distance_to_point(sample_pos, c, radius, rot_sin, rot_cos);
}

fn stroke_coverage_at(sample_pos: vec2<f32>, radius_scale: f32) -> f32 {
  let count = cfg.point_count;
  if (count == 0u) {
    return 0.0;
  }
  let scale = max(radius_scale, 0.0);
  if (scale <= 0.0) {
    return 0.0;
  }
  if (count == 1u) {
    let sp = stroke_points[0u];
    let radius = sp.radius * scale;
    let rot_sin = select(cfg.rotation_sin, sp.rot_sin, cfg.stroke_mode == 1u);
    let rot_cos = select(cfg.rotation_cos, sp.rot_cos, cfg.stroke_mode == 1u);
    let dist = shape_distance_to_point(sample_pos, sp.pos, radius, rot_sin, rot_cos);
    return brush_alpha(dist, radius, cfg.softness) * clamp01(sp.alpha);
  }

  if (cfg.stroke_mode == 1u) {
    var out_alpha = 0.0;
    if (cfg.stroke_accumulate_mode == 0u) {
      for (var i: u32 = 0u; i < count; i = i + 1u) {
        let sp = stroke_points[i];
        let radius = sp.radius * scale;
        let dist = shape_distance_to_point(sample_pos, sp.pos, radius, sp.rot_sin, sp.rot_cos);
        let a = brush_alpha(dist, radius, cfg.softness) * clamp01(sp.alpha);
        out_alpha = max(out_alpha, a);
      }
      return out_alpha;
    }
    var remain = 1.0;
    for (var i: u32 = 0u; i < count; i = i + 1u) {
      let sp = stroke_points[i];
      let radius = sp.radius * scale;
      let dist = shape_distance_to_point(sample_pos, sp.pos, radius, sp.rot_sin, sp.rot_cos);
      let a = clamp01(brush_alpha(dist, radius, cfg.softness) * clamp01(sp.alpha));
      remain = remain * (1.0 - a);
    }
    return 1.0 - remain;
  }

  var out_alpha = 0.0;
  if (cfg.stroke_accumulate_mode == 0u) {
    for (var i: u32 = 0u; i + 1u < count; i = i + 1u) {
      let p0 = stroke_points[i];
      let p1 = stroke_points[i + 1u];
      let t = closest_t_to_segment(sample_pos, p0.pos, p1.pos);
      let radius = mix(p0.radius, p1.radius, t) * scale;
      let alpha = mix(p0.alpha, p1.alpha, t);
      let dist = shape_distance_to_segment(
        sample_pos,
        p0.pos,
        p1.pos,
        radius,
        cfg.rotation_sin,
        cfg.rotation_cos,
      );
      let a = brush_alpha(dist, radius, cfg.softness) * clamp01(alpha);
      out_alpha = max(out_alpha, a);
    }
    return out_alpha;
  }
  var remain = 1.0;
  for (var i: u32 = 0u; i + 1u < count; i = i + 1u) {
    let p0 = stroke_points[i];
    let p1 = stroke_points[i + 1u];
    let t = closest_t_to_segment(sample_pos, p0.pos, p1.pos);
    let radius = mix(p0.radius, p1.radius, t) * scale;
    let alpha = mix(p0.alpha, p1.alpha, t);
    let dist = shape_distance_to_segment(
      sample_pos,
      p0.pos,
      p1.pos,
      radius,
      cfg.rotation_sin,
      cfg.rotation_cos,
    );
    let a = clamp01(brush_alpha(dist, radius, cfg.softness) * clamp01(alpha));
    remain = remain * (1.0 - a);
  }
  return 1.0 - remain;
}

fn antialias_samples_per_axis(level: u32) -> u32 {
  let clamped = min(level, 9u);
  if (clamped <= 3u) {
    return 1u << clamped;
  }
  return 8u + (clamped - 3u) * 2u;
}

fn blend_paint(dst: u32, src_rgb: vec3<f32>, src_a: f32) -> u32 {
  if (src_a <= 0.0) {
    return dst;
  }
  let da = unpack_a(dst);
  let dr = unpack_r(dst);
  let dg = unpack_g(dst);
  let db = unpack_b(dst);

  let out_a = src_a + da * (1.0 - src_a);
  if (out_a <= 0.0) {
    return 0u;
  }

  let dst_w = da * (1.0 - src_a);
  let out_rgb = (src_rgb * src_a + vec3<f32>(dr, dg, db) * dst_w) / out_a;
  return pack_argb(out_a, out_rgb.x, out_rgb.y, out_rgb.z);
}

fn blend_erase(dst: u32, erase_a: f32) -> u32 {
  if (erase_a <= 0.0) {
    return dst;
  }
  let da = unpack_a(dst);
  if (da <= 0.0) {
    return dst;
  }
  let out_a = da * (1.0 - clamp01(erase_a));
  if (out_a <= 0.0) {
    return 0u;
  }
  // Preserve straight RGB; only alpha changes.
  return pack_argb(out_a, unpack_r(dst), unpack_g(dst), unpack_b(dst));
}

@compute @workgroup_size(16, 16)
fn draw_brush_stroke(@builtin(global_invocation_id) id: vec3<u32>) {
  let lx = id.x;
  let ly = id.y;
  if (lx >= cfg.region_width || ly >= cfg.region_height) {
    return;
  }

  let x = cfg.origin_x + lx;
  let y = cfg.origin_y + ly;
  if (x >= cfg.canvas_width || y >= cfg.canvas_height) {
    return;
  }
  if (cfg.selection_mask_mode != 0u) {
    let sel = textureLoad(selection_mask, vec2<i32>(i32(x), i32(y)), 0).x;
    if (sel == 0u) {
      let dst = textureLoad(layer_in, vec2<i32>(i32(x), i32(y)), 0).x;
      textureStore(layer_out, vec2<i32>(i32(x), i32(y)), vec4<u32>(dst, 0u, 0u, 0u));
      if (cfg.stroke_mask_mode != 0u) {
        let mask_before = textureLoad(stroke_mask_in, vec2<i32>(i32(x), i32(y)), 0).x;
        textureStore(
          stroke_mask_out,
          vec2<i32>(i32(x), i32(y)),
          vec4<u32>(mask_before, 0u, 0u, 0u),
        );
      }
      return;
    }
  }

  let samples = antialias_samples_per_axis(cfg.antialias_level);
  let inv_samples = 1.0 / f32(samples);
  let ratio = clamp(cfg.hollow_ratio, 0.0, 1.0);
  let use_hollow = (cfg.hollow_mode != 0u) && (ratio > 0.0001) && (cfg.erase_mode == 0u);
  var outer_accum = 0.0;
  var inner_accum = 0.0;
  for (var sy: u32 = 0u; sy < samples; sy = sy + 1u) {
    for (var sx: u32 = 0u; sx < samples; sx = sx + 1u) {
      let ox = (f32(sx) + 0.5) * inv_samples - 0.5;
      let oy = (f32(sy) + 0.5) * inv_samples - 0.5;
      let sample_pos = vec2<f32>(f32(x) + 0.5 + ox, f32(y) + 0.5 + oy);
      outer_accum = outer_accum + stroke_coverage_at(sample_pos, 1.0);
      if (use_hollow) {
        inner_accum = inner_accum + stroke_coverage_at(sample_pos, ratio);
      }
    }
  }
  let total_samples = f32(samples * samples);
  let outer = clamp01(outer_accum / max(1.0, total_samples));
  let inner = select(0.0, clamp01(inner_accum / max(1.0, total_samples)), use_hollow);
  let use_mask = use_hollow && (cfg.stroke_mask_mode != 0u);
  let use_base = use_hollow && (cfg.stroke_base_mode != 0u);
  var hole = inner;
  var outer_union = outer;
  if (use_mask) {
    let mask_before = textureLoad(stroke_mask_in, vec2<i32>(i32(x), i32(y)), 0).x;
    let inner_before = unpack_inner_mask(mask_before);
    let outer_before = unpack_outer_mask(mask_before);
    hole = max(inner_before, inner);
    outer_union = max(outer_before, outer);
    let mask_u = pack_mask(hole, outer_union);
    textureStore(
      stroke_mask_out,
      vec2<i32>(i32(x), i32(y)),
      vec4<u32>(mask_u, 0u, 0u, 0u),
    );
  }
  let hollow_outer = select(outer, outer_union, use_base);
  let paint_cov = select(outer, max(hollow_outer - hole, 0.0), use_hollow);
  let erase_cov = select(0.0, hole, cfg.hollow_erase != 0u);

  let dst = textureLoad(layer_in, vec2<i32>(i32(x), i32(y)), 0).x;
  var out = dst;
  let src_a_base = unpack_a(cfg.color_argb);
  if (cfg.erase_mode != 0u) {
    let erase_a = clamp01(outer * src_a_base);
    if (erase_a > 0.0) {
      out = blend_erase(dst, erase_a);
    }
    textureStore(layer_out, vec2<i32>(i32(x), i32(y)), vec4<u32>(out, 0u, 0u, 0u));
    return;
  }

  let paint_a = clamp01(paint_cov * src_a_base);
  let erase_a = clamp01(erase_cov);

  let src_rgb = vec3<f32>(
    unpack_r(cfg.color_argb),
    unpack_g(cfg.color_argb),
    unpack_b(cfg.color_argb),
  );

  if (use_base) {
    let base = textureLoad(stroke_base, vec2<i32>(i32(x), i32(y)), 0).x;
    out = blend_paint(base, src_rgb, paint_a);
    textureStore(layer_out, vec2<i32>(i32(x), i32(y)), vec4<u32>(out, 0u, 0u, 0u));
    return;
  }

  if (paint_a > 0.0 || erase_a > 0.0) {
    out = blend_paint(dst, src_rgb, paint_a);
    if (erase_a > 0.0) {
      out = blend_erase(out, erase_a);
    }
  }

  textureStore(layer_out, vec2<i32>(i32(x), i32(y)), vec4<u32>(out, 0u, 0u, 0u));
}
