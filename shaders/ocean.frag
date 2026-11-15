// Deep, calm ocean: soft light rays from the surface far above and tiny
// specks drifting in the water. The jellyfish are drawn on top.
#include <flutter/runtime_effect.glsl>
precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform vec3 uTint;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  // Lighter near the surface, almost black far below.
  vec3 col = mix(vec3(0.05, 0.28, 0.42), vec3(0.0, 0.025, 0.07), pow(uv.y, 0.8));
  col = mix(col, col * uTint * 1.6, 0.35);
  // Light rays, slanted and slowly swaying.
  float x = uv.x + uv.y * 0.25;
  float rays = 0.0;
  rays += pow(0.5 + 0.5 * sin(x * 13.0 + uTime * 0.12 + noise(vec2(x * 4.0, uTime * 0.1)) * 2.0), 6.0);
  rays += 0.6 * pow(0.5 + 0.5 * sin(x * 21.0 - uTime * 0.09 + 1.7), 8.0);
  rays *= (1.0 - uv.y) * (1.0 - uv.y) * 0.32;
  col += vec3(0.55, 0.85, 0.95) * rays;
  // Marine snow: tiny specks that float up very slowly.
  vec2 g = vec2(uv.x * uSize.x / 9.0, uv.y * uSize.y / 9.0 + uTime * 0.6);
  vec2 cell = floor(g);
  float h = hash(cell);
  if (h > 0.965) {
    vec2 f = fract(g) - 0.5 + 0.3 * vec2(sin(uTime * 0.3 + h * 20.0), 0.0);
    col += vec3(0.6, 0.8, 0.9) * smoothstep(0.18, 0.0, length(f)) * 0.35;
  }
  vec2 v = uv - 0.5;
  col *= 1.0 - dot(v, v) * 0.7;
  fragColor = vec4(col, 1.0);
}
