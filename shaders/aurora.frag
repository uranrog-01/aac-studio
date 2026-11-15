// Northern lights over mountains and a still lake, under slowly turning
// stars. Touch makes the lights grow brighter where the finger is.
#include <flutter/runtime_effect.glsl>
precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform vec3 uTouch;   // x (0..1), y (0..1, up), strength 0..1
uniform vec3 uShoot;   // shooting star: x, y (0..1, up), age (s)

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * noise(p);
    p = p * 2.03 + vec2(1.7, 9.2);
    a *= 0.5;
  }
  return v;
}

vec3 aurora(vec2 uv) {
  vec3 col = vec3(0.0);
  for (int i = 0; i < 3; i++) {
    float fi = float(i);
    float t = uTime * (0.025 + fi * 0.008);
    float w = fbm(vec2(uv.x * 1.6 + fi * 3.1 + t, t * 2.0));
    float centre = 0.58 + fi * 0.07 + 0.10 * sin(uv.x * 2.2 + t * 3.0 + fi) + (w - 0.5) * 0.22;
    float d = uv.y - centre;
    // A curtain: bright lower edge, fading upward, with vertical rays.
    float curtain = d > 0.0 ? exp(-d * (6.0 + fi * 2.0)) : exp(d * 38.0);
    float rays = 0.55 + 0.45 * noise(vec2(uv.x * 34.0 + w * 9.0, t * 6.0 + fi));
    float glow = curtain * rays;
    vec3 c = mix(vec3(0.15, 0.95, 0.55), vec3(0.20, 0.65, 0.95), fi * 0.45);
    c = mix(c, vec3(0.70, 0.35, 0.95), smoothstep(0.0, 0.25, d) * 0.6);
    col += c * glow * (0.55 - fi * 0.12);
  }
  // A touch makes the lights nearby glow more.
  float near = exp(-pow((uv.x - uTouch.x) * 3.5, 2.0));
  return col * (1.0 + near * uTouch.z * 1.4);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = vec2(frag.x / uSize.x, 1.0 - frag.y / uSize.y);
  float aspect = uSize.x / uSize.y;
  float horizon = 0.24;
  float ridge = horizon + 0.07 + 0.08 * fbm(vec2(uv.x * aspect * 2.2, 3.0)) +
                0.03 * sin(uv.x * 5.0);

  vec2 sky = uv;
  float lake = 0.0;
  if (uv.y < horizon) {
    // The still lake mirrors the sky, with a few slow ripples.
    lake = 1.0;
    sky.y = 2.0 * horizon - uv.y;
    sky.x += 0.004 * sin(uv.y * 160.0 + uTime * 0.8);
  }
  vec2 sa = vec2(sky.x * aspect, sky.y);

  vec3 col = mix(vec3(0.03, 0.07, 0.14), vec3(0.005, 0.01, 0.04), smoothstep(horizon, 1.0, sky.y));
  // Stars, twinkling slowly.
  vec2 cell = floor(sa * 90.0);
  float h = hash(cell);
  if (h > 0.985) {
    vec2 f = fract(sa * 90.0) - 0.5;
    float tw = 0.6 + 0.4 * sin(uTime * (0.6 + h * 2.0) + h * 40.0);
    col += vec3(0.9, 0.95, 1.0) * smoothstep(0.25, 0.0, length(f)) * tw;
  }
  col += aurora(vec2(sky.x * aspect / max(aspect, 1.0), sky.y));
  // A shooting star now and then.
  if (uShoot.z >= 0.0 && uShoot.z < 1.2) {
    vec2 head = uShoot.xy + vec2(-0.35, -0.18) * uShoot.z;
    vec2 dir = normalize(vec2(-0.35, -0.18));
    vec2 rel = vec2(sky.x, sky.y) - head;
    float along = dot(rel, -dir);
    float across = abs(dot(rel, vec2(-dir.y, dir.x)));
    if (along > 0.0 && along < 0.12) {
      col += vec3(1.0) * smoothstep(0.003, 0.0, across) * (1.0 - along / 0.12) *
             (1.0 - uShoot.z / 1.2);
    }
  }
  if (lake > 0.5) {
    col *= 0.55;
    col = mix(col, vec3(0.01, 0.02, 0.04), smoothstep(horizon, 0.0, uv.y) * 0.4);
  }
  // Mountains in front of the sky (and their dark reflection).
  float mirrorRidge = 2.0 * horizon - ridge;
  if (uv.y < ridge && uv.y > horizon) {
    float rim = smoothstep(ridge - 0.012, ridge, uv.y);
    col = mix(vec3(0.01, 0.015, 0.03), vec3(0.08, 0.14, 0.12), rim * 0.6);
  } else if (uv.y <= horizon && uv.y > mirrorRidge) {
    col = mix(col, vec3(0.008, 0.012, 0.025), 0.85);
  }
  fragColor = vec4(col, 1.0);
}
