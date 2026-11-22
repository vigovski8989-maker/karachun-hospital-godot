class_name LookPool
extends RefCounted
# 0.9.6: patient variety. A deterministic per-patient look (body, outfit palette, hair, age, build) rolled from the id.
# The 0.9.5 crowd was one bearded man in an orange shirt and blue trousers; now every patient draws from every body
# (male, female, child, elder, heavy, thin) with its own outfit colours and hair.
const HAIR_COLS := [Color(0.07, 0.07, 0.08), Color(0.2, 0.14, 0.1), Color(0.37, 0.26, 0.18), Color(0.5, 0.3, 0.16), Color(0.8, 0.65, 0.38), Color(0.55, 0.2, 0.1), Color(0.11, 0.1, 0.11), Color(0.3, 0.2, 0.13)]
const GREY := [Color(0.6, 0.6, 0.62), Color(0.85, 0.85, 0.88), Color(0.72, 0.72, 0.75)]
const SOFT := [Color(0.95, 0.55, 0.6), Color(0.55, 0.75, 0.95), Color(0.65, 0.9, 0.7), Color(0.95, 0.85, 0.45), Color(0.8, 0.65, 0.95), Color(0.95, 0.7, 0.45), Color(0.45, 0.8, 0.8), Color(0.9, 0.9, 0.92), Color(0.75, 0.55, 0.45), Color(0.55, 0.6, 0.7), Color(0.85, 0.4, 0.45), Color(0.5, 0.65, 0.45)]
const TROUS := [Color(0.35, 0.4, 0.55), Color(0.2, 0.2, 0.24), Color(0.55, 0.5, 0.42), Color(0.4, 0.3, 0.25), Color(0.6, 0.65, 0.75), Color(0.25, 0.35, 0.3)]
const NPA := 16

static func roll(e: Dictionary, dis: String, vip: bool) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = absi(hash(int(e.id) * 2654435 + 977))
	var L := {"glb": "patient_a", "tex": "", "tint": null, "scale": 1.0, "shape": Vector3.ONE, "stoop": 0.0, "head_k": 1.0,
		"hair": -1, "hcol": Color.WHITE, "bald": false, "beard": false, "age": "adult", "female": false, "blouse": null, "trous": null}
	var ar = rng.randf()
	L.age = "kid" if ar < 0.10 else ("elder" if ar < 0.30 else "adult")
	var br = rng.randf()
	# body
	# 0.9.8.1: the body never depends on the disease, so a patient keeps the same look before and after treatment
	# (balloonhead = the patient's own body with a scaled head bone; lostshadow = own clothes with the body hidden).
	# 0.9.7: the rocker suit (white + one purple leg + gold belt) read as a wrong-tinted trouser leg -> not used for patients
	if br < 0.50: L.glb = "patient_a"
	elif br < 0.76: L.glb = "nurse"
	else: L.glb = "receptionist"
	if OS.get_environment("LOOK_GLB") != "": L.glb = OS.get_environment("LOOK_GLB")
	L.female = L.glb in ["nurse", "receptionist"]
	# outfit
	match L.glb:
		"patient_a": L.tex = "res://assets/chars/var/pa_%02d.jpg" % (rng.randi() % NPA)
		"rocker": L.tint = SOFT[rng.randi() % SOFT.size()].lerp(Color.WHITE, 0.45)
		"orderly": L.tex = "res://assets/chars/var/od_%02d.jpg" % (rng.randi() % 8)
		"nurse": L.tex = "res://assets/chars/var/nu_%02d.jpg" % (rng.randi() % 10)
		"receptionist":
			L.blouse = SOFT[rng.randi() % SOFT.size()]; L.trous = TROUS[rng.randi() % TROUS.size()]
	if vip and L.glb == "patient_a": L.tex = "res://assets/chars/var/pa_14.jpg"
	# hair
	var hc: Color = HAIR_COLS[rng.randi() % HAIR_COLS.size()]
	if L.age == "elder": hc = GREY[rng.randi() % GREY.size()]
	L.hcol = hc
	if L.glb == "patient_a":
		var hr = rng.randf()
		L.bald = hr < (0.34 if L.age == "elder" else 0.18)
		L.beard = (not L.bald) and hr > (0.82 if L.age != "kid" else 2.0)
	if L.glb == "receptionist": L.hair = rng.randi() % 3
	if OS.get_environment("LOOK_GLB") != "": L.hair = int(e.id) % 3; L.age = "adult"
	# build
	var sc = 0.94 + rng.randf() * 0.12
	if L.female: sc *= 0.96
	match L.age:
		"kid": sc = 0.70 + rng.randf() * 0.1; L.head_k = 1.22
		"elder": sc *= 0.96; L.stoop = 0.12 + rng.randf() * 0.14
	L.scale = sc
	if dis == "balloonhead": L.head_k = 1.8
	var bd = rng.randf()
	if L.age != "kid":
		if bd < 0.17: L.shape = Vector3(1.2 + rng.randf() * 0.08, 1.0, 1.26 + rng.randf() * 0.1)
		elif bd < 0.32: L.shape = Vector3(0.84 + rng.randf() * 0.05, 1.0, 0.8 + rng.randf() * 0.05)
		else: L.shape = Vector3(0.97 + rng.randf() * 0.06, 1.0, 0.97 + rng.randf() * 0.06)
	return L

static func apply(p: CharPuppet, L: Dictionary) -> void:
	p.shape = L.shape; p.stoop = L.stoop; p.head_k = L.head_k
	if p.model == null: return
	p.model.scale = Vector3(L.shape.x * L.scale, L.scale, L.shape.z * L.scale)
	# hair meshes
	for mi in p.model.find_children("*", "MeshInstance3D", true, false):
		var n = str(mi.name)
		if n.begins_with("Reception_Badge") and not p.is_staff: mi.visible = false
		if L.glb == "patient_a":
			if n == "Hair_Beard": mi.visible = (not L.bald) and L.beard
			elif n == "Hair_Buzzed": mi.visible = (not L.bald) and not L.beard
		if n.begins_with("Hair_") or n == "Eyebrows":
			if L.glb == "receptionist" and n.begins_with("Hair_Neat"):
				mi.visible = _recep_hair_vis(n, L.hair)
			_tint_mat(mi, L.hcol if n != "Eyebrows" else L.hcol.lerp(Color(0.4, 0.4, 0.4), 0.5))
		if L.glb == "receptionist" and L.blouse != null: _tint_by_mat(mi, {"Reception_Blouse": L.blouse, "Reception_Collar": L.blouse.lightened(0.35), "Reception_Navy": L.trous, "Reception_Teal": L.trous.lightened(0.15)})

static func _tint_by_mat(mi: MeshInstance3D, mp: Dictionary) -> void:
	for si in mi.mesh.get_surface_count():
		var m = mi.get_surface_override_material(si)
		if m == null: m = mi.mesh.surface_get_material(si)
		if m is StandardMaterial3D and mp.has(m.resource_name):
			var d: StandardMaterial3D = m.duplicate()
			d.albedo_color = mp[m.resource_name]
			mi.set_surface_override_material(si, d)

static func _recep_hair_vis(n: String, v: int) -> bool:
	match v:
		0: return n in ["Hair_NeatBun", "Hair_NeatBunWrap_-1", "Hair_NeatBunWrap_0", "Hair_NeatBunWrap_1", "Hair_NeatForelock"]
		1: return n in ["Hair_NeatCap", "Hair_NeatForelock"]
	return n in ["Hair_NeatCap"]

static func _tint_mat(mi: MeshInstance3D, col: Color) -> void:
	for si in mi.mesh.get_surface_count():
		var m = mi.get_surface_override_material(si)
		if m == null: m = mi.mesh.surface_get_material(si)
		if m is StandardMaterial3D:
			var d: StandardMaterial3D = m.duplicate()
			d.albedo_color = col
			mi.set_surface_override_material(si, d)
