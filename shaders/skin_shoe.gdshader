// Character skin + painted shoes. COLOR.r = shoe mask, COLOR.g = sole mask (baked per model from foot bone weights).
shader_type spatial;
render_mode cull_back;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap;
uniform bool has_nrm = false;
uniform vec3 tone = vec3(1.0);
uniform vec3 emis = vec3(0.0);
uniform vec3 shoe : source_color = vec3(0.1);
uniform vec3 sole : source_color = vec3(0.85);
uniform vec3 lace : source_color = vec3(0.9);
varying float m_shoe;
varying float m_sole;
varying float m_lace;
void vertex() {
	m_shoe = COLOR.r;
	m_sole = COLOR.g;
	m_lace = COLOR.b;
}
void fragment() {
	vec3 skin = texture(tex, UV).rgb * tone;
	vec3 sh = mix(shoe, sole, m_sole);
	sh = mix(sh, lace, m_lace * (1.0 - m_sole));
	ALBEDO = mix(skin, sh, m_shoe);
	ROUGHNESS = mix(0.8, mix(0.42, 0.85, m_sole), m_shoe);
	SPECULAR = mix(0.28, 0.5, m_shoe);
	METALLIC = 0.0;
	if (has_nrm) {
		NORMAL_MAP = mix(texture(nrm, UV).rgb, vec3(0.5, 0.5, 1.0), m_shoe);
	}
	EMISSION = emis * (1.0 - m_shoe);
}
