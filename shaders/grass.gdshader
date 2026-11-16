shader_type spatial;
uniform vec3 c1 : source_color = vec3(0.47, 0.66, 0.33);
uniform vec3 c2 : source_color = vec3(0.40, 0.60, 0.29);
varying vec3 wp;
float h21(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p){ vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
  return mix(mix(h21(i),h21(i+vec2(1,0)),f.x), mix(h21(i+vec2(0,1)),h21(i+vec2(1,1)),f.x), f.y); }
void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment(){
  vec2 id = floor(wp.xz / 1.5);
  float chk = mod(id.x + id.y, 2.0);
  float n = vn(wp.xz * 2.0) * 0.5 + vn(wp.xz * 11.0) * 0.5;
  ALBEDO = mix(c1, c2, chk) * (0.9 + 0.18 * n);
  ROUGHNESS = 0.95;
}
