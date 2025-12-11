#version 320 es
precision mediump float;
#include <flutter/runtime_effect.glsl>

uniform sampler2D uTexture;
uniform vec2 uResolution;
uniform vec2 uBrushPos;
uniform float uBrushRadius;
uniform vec4 uBrushColor;

out vec4 fragColor;

void main() {
  vec2 coord = FlutterFragCoord().xy;
  vec2 uv = coord / uResolution;
  vec4 base = texture(uTexture, uv);

  float radius = max(uBrushRadius, 0.0001);
  float dist = distance(coord, uBrushPos);
  float t = clamp(1.0 - dist / radius, 0.0, 1.0);
  float falloff = t * t * (3.0 - 2.0 * t);
  float alpha = falloff * uBrushColor.a;

  float outA = alpha + base.a * (1.0 - alpha);
  vec3 outRgb = outA <= 1e-5
      ? vec3(0.0)
      : (uBrushColor.rgb * alpha + base.rgb * base.a * (1.0 - alpha)) / outA;

  fragColor = vec4(outRgb, outA);
}
