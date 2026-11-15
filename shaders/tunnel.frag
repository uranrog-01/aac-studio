// Calm light tunnel: soft colours flow slowly toward a warm light. Touch
// steers the way and makes the light glow; nothing is fast or flashing.
#include <flutter/runtime_effect.glsl>
precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform vec2 uCenter;   // where the light is, -1..1
uniform float uGlow;    // 0..1, while touching
uniform float uPalette; // slowly changing colour set

out vec4 fragColor;

vec3 palette(float t) {
  // Soft pastel rainbow, never harsh.
  vec3 c = 0.55 + 0.38 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
  return mix(c, vec3(0.45, 0.55, 0.85), 0.18);
}

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float s = min(uSize.x, uSize.y);
  vec2 p = (frag - uSize * 0.5) / s;
  p -= uCenter * 0.22 * (1.0 - length(p));
  float r = max(length(p), 0.0015);
  float a = atan(p.y, p.x) / 6.28318;
  float z = 0.32 / r + uTime * 0.28;

  float twist = a + z * 0.045 + 0.04 * sin(z * 0.6);
  float rings = 0.5 + 0.5 * sin(z * 3.14159);
  float bands = 0.5 + 0.5 * sin(twist * 6.28318 * 5.0 + z * 0.9);
  vec3 col = palette(z * 0.05 + uPalette) * (0.55 + 0.45 * rings);
  col = mix(col, palette(z * 0.05 + uPalette + 0.33), bands * 0.4);
  // Soft panels on the tunnel wall.
  float panel = smoothstep(0.0, 0.08, abs(fract(z * 0.5) - 0.5)) *
                smoothstep(0.0, 0.06, abs(fract(twist * 8.0) - 0.5));
  col *= 0.82 + 0.18 * panel;
  // Far away is misty; the end of the tunnel glows.
  col *= 0.12 + 0.88 * smoothstep(0.02, 0.55, r);
  vec3 light = mix(vec3(1.0, 0.92, 0.78), palette(uPalette + 0.15), 0.25);
  col += light * exp(-r * (7.5 - uGlow * 2.5)) * (0.9 + 0.5 * uGlow);
  // Tiny drifting motes of light.
  vec2 cell = vec2(floor(z * 6.0), floor(a * 48.0));
  float h = hash(cell);
  if (h > 0.93) {
    vec2 f = vec2(fract(z * 6.0), fract(a * 48.0)) - 0.5;
    col += light * smoothstep(0.32, 0.0, length(f)) * 0.5 * smoothstep(0.05, 0.4, r);
  }
  // Darker near the screen edge, like looking down a real tunnel.
  col *= 0.55 + 0.45 * smoothstep(1.1, 0.25, r);
  fragColor = vec4(col, 1.0);
}
