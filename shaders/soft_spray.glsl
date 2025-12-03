#version 100
#extension GL_OES_standard_derivatives : enable
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uResolution;
uniform float uInnerRatio;
uniform float uExponent;

out vec4 fragColor;

void main() {
  vec2 coord = FlutterFragCoord().xy;
  vec2 center = uResolution * 0.5;
  float outerRadius = min(uResolution.x, uResolution.y) * 0.5;
  float distanceNorm = length(coord - center) / max(outerRadius, 0.0001);
  float alpha;
  if (distanceNorm <= uInnerRatio) {
    alpha = 1.0;
  } else if (distanceNorm >= 1.0) {
    alpha = 0.0;
  } else {
    float t = (distanceNorm - uInnerRatio) / max(1.0 - uInnerRatio, 0.0001);
    float eased = pow(max(1.0 - t, 0.0), uExponent);
    alpha = eased;
  }
  fragColor = vec4(vec3(alpha), alpha);
}
