// Lava lamp: a glass lamp on a metal base, lit from below. Wax blobs are
// metaballs with 3D lighting (soft diffuse, subsurface glow, specular), so
// they stretch, join and split like real heated wax.
#include <flutter/runtime_effect.glsl>
precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform vec3 uWax;     // wax colour
uniform vec3 uLiquid;  // liquid colour
uniform vec4 uB0;      // blob: x, y (lamp units), radius, unused
uniform vec4 uB1;
uniform vec4 uB2;
uniform vec4 uB3;
uniform vec4 uB4;
uniform vec4 uB5;
uniform vec4 uB6;
uniform vec4 uB7;

out vec4 fragColor;

const float GLASS_TOP = -0.33;
const float GLASS_BOTTOM = 0.27;
const float CAP_TOP = -0.46;
const float BASE_BOTTOM = 0.46;

float glassHalfWidth(float y) {
  float t = clamp((y - GLASS_TOP) / (GLASS_BOTTOM - GLASS_TOP), 0.0, 1.0);
  // Narrow at the top, widest a little above the base, a gentle curve.
  return mix(0.058, 0.128, t) + 0.012 * sin(t * 3.14159);
}

float baseHalfWidth(float y) {
  float t = clamp((y - GLASS_BOTTOM) / (BASE_BOTTOM - GLASS_BOTTOM), 0.0, 1.0);
  return mix(0.118, 0.172, t * t * 0.6 + t * 0.4);
}

float capHalfWidth(float y) {
  float t = clamp((y - CAP_TOP) / (GLASS_TOP - CAP_TOP), 0.0, 1.0);
  return mix(0.026, 0.06, t);
}

void addBlob(vec4 b, vec2 q, inout float f, inout vec2 g) {
  if (b.z <= 0.0) return;
  vec2 d = q - b.xy;
  float d2 = dot(d, d) + 1e-5;
  float r2 = b.z * b.z;
  f += r2 / d2;
  g += -2.0 * r2 * d / (d2 * d2);
}

vec3 metal(float xn, float y, vec3 glow) {
  // Brushed chrome cylinder: soft wrap-around shading plus two bright bands.
  float shade = 0.42 + 0.38 * cos(xn * 1.35);
  float band = 0.75 * exp(-pow((xn + 0.48) / 0.13, 2.0)) +
               0.30 * exp(-pow((xn - 0.58) / 0.09, 2.0));
  float brushed = 0.03 * sin(y * 900.0 + xn * 3.0);
  vec3 c = vec3(0.50, 0.52, 0.56) * shade + band + brushed;
  return c + glow;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float L = min(uSize.y * 0.94, uSize.x * 1.9);
  vec2 q = (p - vec2(uSize.x * 0.5, uSize.y * 0.5)) / L;
  float px = 1.0 / L;

  // Dark room with the lamp's warm light on the wall and the table.
  float lampGlow = exp(-length(vec2(q.x * 1.6, (q.y - 0.02) * 0.9)) * 3.2);
  vec3 col = vec3(0.018, 0.016, 0.03) + mix(uLiquid, uWax, 0.5) * lampGlow * 0.32;
  if (q.y > BASE_BOTTOM) {
    float table = exp(-abs(q.x) * 3.0) * exp(-(q.y - BASE_BOTTOM) * 6.0);
    col = vec3(0.05, 0.035, 0.03) + uWax * table * 0.25;
  }

  float y = q.y;
  // Metal cap.
  if (y > CAP_TOP && y < GLASS_TOP) {
    float w = capHalfWidth(y);
    float e = (w - abs(q.x)) / px;
    if (e > -1.0) {
      vec3 m = metal(q.x / w, y, uWax * 0.05);
      col = mix(col, m, clamp(e + 0.5, 0.0, 1.0));
    }
  }
  // Metal base, warm from the bulb near the glass.
  if (y > GLASS_BOTTOM && y < BASE_BOTTOM) {
    float w = baseHalfWidth(y);
    float e = (w - abs(q.x)) / px;
    if (e > -1.0) {
      float near = exp(-(y - GLASS_BOTTOM) * 22.0);
      vec3 m = metal(q.x / w, y, uWax * near * 0.35);
      col = mix(col, m, clamp(e + 0.5, 0.0, 1.0));
    }
  }
  // The glass and everything inside it.
  if (y >= GLASS_TOP && y <= GLASS_BOTTOM) {
    float w = glassHalfWidth(y);
    float e = (w - abs(q.x)) / px;
    if (e > -1.0) {
      float xn = q.x / w;
      float bottomness = smoothstep(GLASS_TOP, GLASS_BOTTOM, y);
      // Liquid: lit from below, darker at the top and at the curved sides.
      vec3 liquid = uLiquid * (0.22 + 0.95 * pow(bottomness, 1.6));
      liquid *= 0.75 + 0.25 * (1.0 - xn * xn);
      // Wax field, with a melted pool resting on the bottom.
      float f = 0.0;
      vec2 g = vec2(0.0);
      addBlob(uB0, q, f, g);
      addBlob(uB1, q, f, g);
      addBlob(uB2, q, f, g);
      addBlob(uB3, q, f, g);
      addBlob(uB4, q, f, g);
      addBlob(uB5, q, f, g);
      addBlob(uB6, q, f, g);
      addBlob(uB7, q, f, g);
      float pool = smoothstep(GLASS_BOTTOM - 0.055, GLASS_BOTTOM - 0.005, y);
      f += pool * 1.6;
      g += vec2(0.0, -40.0) * pool;
      float inside = smoothstep(0.96, 1.04, f);
      if (inside > 0.0) {
        float thick = smoothstep(1.0, 2.4, f);
        vec2 dir = length(g) > 0.0 ? normalize(g) : vec2(0.0);
        vec3 n = normalize(vec3(-dir * (1.0 - thick) * 1.4, 0.55 + thick));
        vec3 fromBulb = normalize(vec3(0.0, 0.75, 0.65));
        vec3 fromRoom = normalize(vec3(-0.5, -0.6, 0.7));
        float diff = max(dot(n, fromBulb), 0.0);
        float spec = pow(max(dot(reflect(-fromRoom, n), vec3(0.0, 0.0, 1.0)), 0.0), 28.0);
        float sss = thick * (0.35 + 0.65 * bottomness);
        vec3 wax = uWax * (0.42 + 0.7 * diff) + uWax * sss * 0.6;
        wax += vec3(1.0, 0.95, 0.85) * spec * 0.55;
        // Thin edges let the liquid show through a little.
        wax = mix(liquid, wax, 0.72 + 0.28 * thick);
        liquid = mix(liquid, wax, inside);
      }
      // Glass: reflections, a bright vertical streak and darker rims.
      float fres = pow(abs(xn), 6.0);
      float streak = 0.2 * exp(-pow((xn + 0.62) / 0.06, 2.0)) +
                     0.07 * exp(-pow((xn - 0.74) / 0.05, 2.0));
      vec3 glass = mix(liquid, liquid * 0.45 + vec3(0.12), fres * 0.6) + streak;
      col = mix(col, glass, clamp(e + 0.5, 0.0, 1.0));
    }
  }
  // Gentle vignette.
  vec2 v = p / uSize - 0.5;
  col *= 1.0 - dot(v, v) * 0.6;
  fragColor = vec4(col, 1.0);
}
