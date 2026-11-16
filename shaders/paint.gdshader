shader_type spatial;
// Soft wall paint with subtle roller texture (world-space).
uniform vec3 col : source_color = vec3(0.93, 0.92, 0.88);
uniform float rough = 0.85;
varying vec3 wp;
float h21(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p){ vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
  return mix(mix(h21(i),h21(i+vec2(1,0)),f.x), mix(h21(i+vec2(0,1)),h21(i+vec2(1,1)),f.x), f.y); }
void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment(){
  float n = vn(vec2(wp.x + wp.z, wp.y) * 18.0) * 0.6 + vn(vec2(wp.x + wp.z, wp.y) * 3.0) * 0.4;
  ALBEDO = col * (0.97 + 0.05 * n);
  ROUGHNESS = rough;
}
