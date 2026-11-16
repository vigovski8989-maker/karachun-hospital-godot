shader_type spatial;
// Procedural large-format stone tiles with grout, per-tile tone variation and fine speckle.
uniform vec3 col_a : source_color = vec3(0.86, 0.83, 0.77);
uniform vec3 col_b : source_color = vec3(0.80, 0.77, 0.71);
uniform vec3 grout : source_color = vec3(0.62, 0.60, 0.56);
uniform float tile = 0.6;
uniform float gw = 0.012;
varying vec3 wp;
float h21(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p){ vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
  return mix(mix(h21(i),h21(i+vec2(1,0)),f.x), mix(h21(i+vec2(0,1)),h21(i+vec2(1,1)),f.x), f.y); }
void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment(){
  vec2 p = wp.xz / tile;
  vec2 id = floor(p); vec2 f = fract(p);
  float chk = mod(id.x + id.y, 2.0);
  float v = h21(id);
  vec3 c = mix(col_a, col_b, chk) * (0.96 + 0.08 * v);
  float n = vn(wp.xz * 9.0) * 0.5 + vn(wp.xz * 31.0) * 0.5;
  c *= 0.95 + 0.07 * n;
  float speck = step(0.93, h21(floor(wp.xz * 140.0)));
  c = mix(c, c * 0.78, speck * 0.5);
  vec2 e = min(f, 1.0 - f) * tile;
  float g = 1.0 - smoothstep(gw * 0.5, gw, min(e.x, e.y));
  ALBEDO = mix(c, grout, g);
  ROUGHNESS = mix(0.32 + 0.12 * n, 0.85, g);
  SPECULAR = 0.45;
  // slight bevel normal at tile edges
  vec2 bev = (1.0 - smoothstep(0.0, 0.03, e)) * sign(0.5 - f) * vec2(1.0);
  NORMAL_MAP = normalize(vec3(-bev.x * 0.35 + 0.5, bev.y * 0.35 + 0.5, 1.0));
}
