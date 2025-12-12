#version 320 es
precision mediump float;
#include <flutter/runtime_effect.glsl>

// Input from the layer being filtered.
uniform sampler2D inputImage;

// Layer resolution in the same coordinate space as FlutterFragCoord
// (physical pixels under Impeller).
uniform vec2 uResolution;

// Size of one canvas pixel in physical pixels.
uniform float uPixelSize;

out vec4 fragColor;

void main() {
  vec2 coord = FlutterFragCoord().xy;

  float sizePx = max(uPixelSize, 1.0);
  // Quantize to a grid of sizePx and sample at cell center.
  vec2 snapped = floor(coord / sizePx) * sizePx + vec2(0.5 * sizePx);

  vec2 uv = snapped / uResolution;
  fragColor = texture(inputImage, uv);
}
