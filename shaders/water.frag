// A clear pond seen from above. Pass 0 draws the pebble floor through the
// moving water (refraction, caustics, depth colour); pass 1 draws only the
// surface (sun glints, ripple highlights) over the fish.
#include <flutter/runtime_effect.glsl>
precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform float uMode;
uniform vec4 uR0; // ripple: x, y (pixels), age (s), strength
uniform vec4 uR1;
uniform vec4 uR2;
uniform vec4 uR3;
uniform vec4 uR4;
uniform vec4 uR5;
uniform vec4 uR6;
uniform vec4 uR7;

out vec4 fragColor;

vec2 hash2(vec2 p) {
  p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
  return fract(sin(p) * 43758.5453);
}

// Distance to the nearest and second nearest cell point, and the cell id.
vec3 voronoi(vec2 x, out vec2 id) {
  vec2 n = floor(x);
  vec2 f = fract(x);
  float d1 = 8.0, d2 = 8.0;
  id = vec2(0.0);
  for (int j = -1; j <= 1; j++) {
    for (int i = -1; i <= 1; i++) {
      vec2 g = vec2(float(i), float(j));
      vec2 o = 0.15 + 0.7 * hash2(n + g);
      vec2 r = g + o - f;
      float d = dot(r, r);
      if (d < d1) { d2 = d1; d1 = d; id = n + g; }
      else if (d < d2) { d2 = d; }
    }
  }
  return vec3(sqrt(d1), sqrt(d2), 0.0);
}

float ripple(vec4 r, vec2 p) {
  if (r.w <= 0.0 || r.z < 0.0 || r.z > 4.5) return 0.0;
  float d = distance(p, r.xy);
  float front = r.z * 175.0;
  float x = d - front;
  float env = exp(-x * x / 3200.0);
  return r.w * exp(-r.z * 0.8) * sin(x * 0.085) * env * 7.0 / (1.0 + d * 0.008);
}

float height(vec2 p) {
  float h = 0.9 * sin(p.x * 0.017 + uTime * 0.8) * sin(p.y * 0.021 - uTime * 0.6);
  h += 0.5 * sin((p.x + p.y) * 0.031 - uTime * 1.1);
  h += ripple(uR0, p) + ripple(uR1, p) + ripple(uR2, p) + ripple(uR3, p);
  h += ripple(uR4, p) + ripple(uR5, p) + ripple(uR6, p) + ripple(uR7, p);
  return h;
}

vec3 pebbleColour(vec2 id) {
  float k = hash2(id * 1.7).x;
  vec3 a = vec3(0.62, 0.58, 0.52);
  if (k < 0.2) a = vec3(0.70, 0.52, 0.40);
  else if (k < 0.4) a = vec3(0.45, 0.50, 0.55);
  else if (k < 0.6) a = vec3(0.78, 0.74, 0.66);
  else if (k < 0.8) a = vec3(0.52, 0.46, 0.42);
  return a * (0.85 + 0.3 * hash2(id).y);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float e = 2.0;
  float h = height(p);
  float hx = height(p + vec2(e, 0.0)) - h;
  float hy = height(p + vec2(0.0, e)) - h;
  vec3 n = normalize(vec3(-hx, -hy, e * 1.2));

  if (uMode < 0.5) {
    // Floor seen through the water.
    vec2 fp = p + n.xy * 46.0;
    vec2 id;
    vec3 v = voronoi(fp / 52.0, id);
    // Round pebbles of different sizes resting on sand.
    float size = 0.30 + 0.14 * hash2(id * 3.1).x;
    float stone = smoothstep(size, size - 0.05, v.x);
    vec3 sand = vec3(0.72, 0.66, 0.52) * (0.88 + 0.12 * hash2(floor(fp / 2.5)).x);
    // Sand is darker right next to a pebble (contact shadow).
    sand *= 0.78 + 0.22 * smoothstep(size, size + 0.12, v.x);
    vec3 peb = pebbleColour(id);
    // Pebbles are domes: lit from the upper left, darker at the rim.
    float dome = 1.0 - pow(clamp(v.x / size, 0.0, 1.0), 2.0);
    peb *= 0.55 + 0.6 * dome;
    vec3 floorCol = mix(sand, peb, stone);
    // Caustics: bright lines of focused sunlight that dance with the waves.
    vec2 cid;
    vec3 c1 = voronoi(fp / 85.0 + vec2(uTime * 0.05, uTime * 0.03), cid);
    vec3 c2 = voronoi(fp / 61.0 - vec2(uTime * 0.04, -uTime * 0.05), cid);
    float caustic = pow(1.0 - smoothstep(0.0, 0.22, c1.y - c1.x), 3.0) +
                    pow(1.0 - smoothstep(0.0, 0.18, c2.y - c2.x), 3.0) * 0.6;
    caustic *= 0.55 + 0.9 * length(n.xy) * 6.0;
    vec3 water = vec3(0.06, 0.38, 0.44);
    vec3 col = mix(floorCol, water, 0.42) + vec3(0.95, 1.0, 0.9) * caustic * 0.28;
    // Light from the upper left, deeper water at the edges.
    vec2 uv = p / uSize;
    col *= 0.82 + 0.25 * (1.0 - uv.y) * (1.0 - uv.x * 0.4);
    col *= 1.0 - 0.35 * dot(uv - 0.5, uv - 0.5);
    fragColor = vec4(col, 1.0);
  } else {
    // Surface only: sun glints and soft highlights, transparent elsewhere.
    vec3 sun = normalize(vec3(-0.45, -0.55, 1.0));
    float spec = pow(max(dot(reflect(-sun, n), vec3(0.0, 0.0, 1.0)), 0.0), 90.0);
    float sheen = clamp(length(n.xy) * 4.0, 0.0, 1.0);
    float a = clamp(spec * 1.4 + sheen * 0.18 + 0.05, 0.0, 1.0);
    vec3 col = mix(vec3(0.75, 0.9, 1.0), vec3(1.0), spec);
    fragColor = vec4(col * a, a);
  }
}
