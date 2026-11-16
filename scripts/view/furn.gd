# Procedural furniture / machines (front faces +Z before rotation). Footprint-aware; built from rounded boxes.
class_name Furn
extends RefCounted

static var M := {}

static func m(name: String) -> StandardMaterial3D:
	if M.has(name): return M[name]
	var c = {
		"wood": [Color(0.62, 0.45, 0.30), 0.55, 0.0], "wood_d": [Color(0.42, 0.29, 0.19), 0.5, 0.0], "white": [Color(0.93, 0.94, 0.95), 0.45, 0.0],
		"steel": [Color(0.72, 0.75, 0.78), 0.3, 0.7], "dark": [Color(0.18, 0.19, 0.22), 0.5, 0.2], "blue": [Color(0.30, 0.52, 0.80), 0.5, 0.0],
		"teal": [Color(0.25, 0.65, 0.62), 0.5, 0.0], "green": [Color(0.30, 0.62, 0.32), 0.7, 0.0], "red": [Color(0.80, 0.25, 0.22), 0.5, 0.0],
		"cream": [Color(0.95, 0.90, 0.78), 0.6, 0.0], "fabric": [Color(0.42, 0.55, 0.72), 0.85, 0.0], "fabric_r": [Color(0.70, 0.33, 0.30), 0.85, 0.0],
		"glass": [Color(0.70, 0.88, 0.95, 0.45), 0.05, 0.0], "screen": [Color(0.15, 0.55, 0.75), 0.2, 0.0], "pot": [Color(0.74, 0.42, 0.28), 0.7, 0.0],
		"leaf": [Color(0.24, 0.55, 0.25), 0.8, 0.0], "yellow": [Color(0.95, 0.80, 0.25), 0.5, 0.0], "black": [Color(0.08, 0.08, 0.09), 0.4, 0.0],
		"paper": [Color(0.97, 0.97, 0.92), 0.9, 0.0], "orange": [Color(0.95, 0.55, 0.18), 0.5, 0.0], "pink": [Color(0.95, 0.62, 0.72), 0.6, 0.0],
		"purple": [Color(0.55, 0.38, 0.75), 0.5, 0.0], "water": [Color(0.35, 0.70, 0.95, 0.6), 0.05, 0.0], "mattress": [Color(0.88, 0.92, 0.96), 0.8, 0.0],
	}
	var v = c.get(name, [Color.MAGENTA, 0.5, 0.0])
	var mm = Geo.mat(v[0], v[1], v[2])
	if v[0].a < 1.0:
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mm.cull_mode = BaseMaterial3D.CULL_DISABLED
	if name == "screen":
		mm.emission_enabled = true; mm.emission = Color(0.2, 0.7, 0.9); mm.emission_energy_multiplier = 0.8
	M[name] = mm
	return mm

static func B(p: Node3D, s: Vector3, mat: String, pos: Vector3, r := 0.03) -> MeshInstance3D:
	return Geo.box(p, s, m(mat), pos, r)
static func C(p: Node3D, rt: float, rb: float, h: float, mat: String, pos: Vector3, seg := 16) -> MeshInstance3D:
	return Geo.cyl(p, rt, rb, h, m(mat), pos, seg)
static func SP(p: Node3D, r: float, mat: String, pos: Vector3, sy := 1.0) -> MeshInstance3D:
	return Geo.sphere(p, r, m(mat), pos, sy)

static func dir_yaw(d) -> float:
	match int(d if d != null else 1):
		0: return PI / 2
		1: return 0.0
		2: return -PI / 2
		_: return PI

# Build item k with footprint fp (already rotated by dir) at tile (x,y). Returns the Node3D.
static func build(parent: Node3D, k: String, x: int, y: int, fp: Array, dir) -> Node3D:
	var n = Node3D.new()
	n.name = k
	parent.add_child(n)
	n.position = Vector3(x + fp[0] / 2.0, 0, y + fp[1] / 2.0)
	n.rotation.y = dir_yaw(dir)
	# local footprint in front-facing frame (w along X, d along Z)
	var w: float = fp[0]
	var d: float = fp[1]
	if dir != null and (int(dir) == 0 or int(dir) == 2):
		w = fp[1]; d = fp[0]
	match k:
		"desk", "recdesk", "chiefdesk": _desk(n, w, d, k)
		"chair_office": _chair(n, true)
		"chair_plain": _chair(n, false)
		"cabinet": _cabinet(n)
		"shelf": _shelf(n)
		"bookcase": _bookcase(n, w)
		"scanner": _scanner(n, w, d)
		"tubes", "labbench": _labbench(n, w, k == "tubes")
		"bed": _bed(n, w, d)
		"bench": _bench(n, w)
		"plant": _plant(n)
		"radiator": _radiator(n)
		"bin": _bin(n)
		"soda": _soda(n)
		"wc": _wc(n)
		"sink": _sink(n)
		"coffee": _coffee(n)
		"sofa": _sofa(n, w)
		"pumpmachine": _pump(n)
		"xray": _xray(n)
		"dnaseq": _dnaseq(n)
		"elchair": _elchair(n)
		"rebootpod": _pod(n)
		"inflator": _inflator(n)
		"uvlamp": _uvlamp(n)
		"morguefridge": _morguefridge(n, w)
		"autopsy": _autopsy(n, w)
		"organfridge": _organfridge(n)
		"readdesk": _readdesk(n)
		"aquarium": _aquarium(n)
		"noticeboard": _noticeboard(n)
		_: B(n, Vector3(w * 0.8, 0.6, d * 0.8), "cream", Vector3(0, 0.3, 0))
	return n

static func _desk(n, w, d, k) -> void:
	var top = "wood" if k != "recdesk" else "white"
	if k == "recdesk":
		B(n, Vector3(w * 0.96, 1.0, 0.18), "teal", Vector3(0, 0.5, 0.32))
		B(n, Vector3(w * 0.98, 0.05, 0.42), "white", Vector3(0, 1.03, 0.22))
		B(n, Vector3(w * 0.96, 0.04, 0.6), "wood", Vector3(0, 0.74, -0.05))
		B(n, Vector3(0.45, 0.32, 0.03), "black", Vector3(-0.35, 0.95, -0.12))
		B(n, Vector3(0.42, 0.28, 0.01), "screen", Vector3(-0.35, 0.95, -0.105))
		B(n, Vector3(0.4, 0.02, 0.14), "dark", Vector3(-0.35, 0.765, 0.02))
		return
	B(n, Vector3(w * 0.92, 0.05, d * 0.72), top, Vector3(0, 0.74, 0))
	for sx in [-1, 1]:
		B(n, Vector3(0.05, 0.72, d * 0.66), "wood_d", Vector3(sx * (w * 0.46 - 0.04), 0.36, 0))
	B(n, Vector3(w * 0.88, 0.4, 0.03), "wood_d", Vector3(0, 0.5, -d * 0.33))
	if k == "chiefdesk":
		B(n, Vector3(0.3, 0.02, 0.22), "paper", Vector3(0.3, 0.775, 0.05))
		C(n, 0.04, 0.04, 0.12, "steel", Vector3(-0.5, 0.82, 0.0))
	else:
		B(n, Vector3(0.42, 0.3, 0.03), "black", Vector3(-0.3, 0.93, -0.18))
		B(n, Vector3(0.38, 0.26, 0.01), "screen", Vector3(-0.3, 0.93, -0.165))
		B(n, Vector3(0.25, 0.02, 0.18), "paper", Vector3(0.35, 0.775, 0.05))

static func _chair(n, office: bool) -> void:
	if office:
		C(n, 0.25, 0.25, 0.04, "dark", Vector3(0, 0.06, 0), 10)
		C(n, 0.03, 0.03, 0.38, "steel", Vector3(0, 0.25, 0), 8)
		B(n, Vector3(0.46, 0.08, 0.44), "dark", Vector3(0, 0.46, 0))
		B(n, Vector3(0.44, 0.5, 0.07), "dark", Vector3(0, 0.75, -0.21))
	else:
		B(n, Vector3(0.42, 0.06, 0.42), "wood", Vector3(0, 0.45, 0))
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				B(n, Vector3(0.04, 0.45, 0.04), "wood_d", Vector3(sx * 0.18, 0.22, sz * 0.18), 0.01)
		B(n, Vector3(0.42, 0.42, 0.05), "wood", Vector3(0, 0.7, -0.19))

static func _cabinet(n) -> void:
	B(n, Vector3(0.7, 1.5, 0.5), "cream", Vector3(0, 0.75, -0.15))
	for i in 3:
		B(n, Vector3(0.6, 0.02, 0.01), "steel", Vector3(0, 0.4 + i * 0.45, 0.105))

static func _shelf(n) -> void:
	B(n, Vector3(0.8, 1.8, 0.4), "white", Vector3(0, 0.9, -0.25))
	var cols = ["red", "blue", "yellow", "green", "orange", "pink"]
	for i in 4:
		B(n, Vector3(0.76, 0.03, 0.36), "steel", Vector3(0, 0.3 + i * 0.42, -0.22))
		for j in 4:
			C(n, 0.05, 0.05, 0.16, cols[(i + j) % cols.size()], Vector3(-0.27 + j * 0.18, 0.4 + i * 0.42, -0.2), 8)

static func _bookcase(n, w) -> void:
	B(n, Vector3(w * 0.9, 2.0, 0.4), "wood_d", Vector3(0, 1.0, -0.28))
	var cols = ["red", "blue", "green", "cream", "purple", "orange"]
	for i in 4:
		for j in int(w * 7):
			B(n, Vector3(0.09, 0.32, 0.26), cols[(i * 3 + j) % cols.size()], Vector3(-w * 0.42 + 0.06 + j * 0.12, 0.38 + i * 0.45, -0.22), 0.005)

static func _scanner(n, w, d) -> void:
	# lying scanner: bed + ring gantry (MRI style)
	B(n, Vector3(0.7, 0.55, d * 0.9), "white", Vector3(0, 0.28, 0.05))
	B(n, Vector3(0.6, 0.08, d * 0.85), "mattress", Vector3(0, 0.6, 0.1))
	var ring = C(n, 0.62, 0.62, 0.5, "white", Vector3(0, 0.8, -d * 0.35), 28)
	ring.rotation.x = PI / 2
	var hole = C(n, 0.4, 0.4, 0.52, "dark", Vector3(0, 0.8, -d * 0.35), 24)
	hole.rotation.x = PI / 2
	B(n, Vector3(0.3, 0.12, 0.02), "screen", Vector3(0.4, 1.1, -d * 0.35 + 0.27))

static func _labbench(n, w, tubes: bool) -> void:
	B(n, Vector3(w * 0.94, 0.9, 0.6), "white", Vector3(0, 0.45, -0.15))
	B(n, Vector3(w * 0.96, 0.04, 0.64), "dark", Vector3(0, 0.92, -0.15))
	var cols = ["red", "blue", "yellow", "green", "purple"]
	for i in 6:
		C(n, 0.03, 0.03, 0.22, cols[i % cols.size()], Vector3(-w * 0.38 + i * w * 0.14, 1.05, -0.2), 8)
	if not tubes:
		B(n, Vector3(0.3, 0.35, 0.25), "steel", Vector3(w * 0.3, 1.12, -0.25))

static func _bed(n, w, d) -> void:
	B(n, Vector3(0.9, 0.08, d * 0.94), "steel", Vector3(0, 0.45, 0))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			C(n, 0.025, 0.025, 0.45, "steel", Vector3(sx * 0.4, 0.22, sz * d * 0.42), 8)
	B(n, Vector3(0.84, 0.14, d * 0.88), "mattress", Vector3(0, 0.56, 0.02))
	B(n, Vector3(0.6, 0.1, 0.3), "white", Vector3(0, 0.68, -d * 0.36))
	B(n, Vector3(0.92, 0.5, 0.05), "steel", Vector3(0, 0.7, -d * 0.47))
	B(n, Vector3(0.84, 0.03, d * 0.5), "blue", Vector3(0, 0.64, d * 0.18))

static func _bench(n, w) -> void:
	for i in int(w):
		var x = -w / 2.0 + 0.5 + i
		B(n, Vector3(0.88, 0.08, 0.46), "teal", Vector3(x, 0.44, 0.02))
		B(n, Vector3(0.88, 0.42, 0.07), "teal", Vector3(x, 0.72, -0.2))
	for sx in [-1, 1]:
		B(n, Vector3(0.05, 0.42, 0.42), "steel", Vector3(sx * (w / 2.0 - 0.06), 0.21, 0))

static func _plant(n) -> void:
	C(n, 0.2, 0.15, 0.36, "pot", Vector3(0, 0.18, 0), 14)
	SP(n, 0.3, "leaf", Vector3(0, 0.62, 0), 1.2)
	SP(n, 0.2, "leaf", Vector3(0.12, 0.85, 0.05))

static func _radiator(n) -> void:
	for i in 7:
		B(n, Vector3(0.08, 0.6, 0.14), "white", Vector3(-0.3 + i * 0.1, 0.42, -0.36), 0.02)

static func _bin(n) -> void:
	C(n, 0.17, 0.14, 0.45, "steel", Vector3(0, 0.23, 0), 14)
	C(n, 0.18, 0.18, 0.03, "dark", Vector3(0, 0.46, 0), 14)

static func _soda(n) -> void:
	B(n, Vector3(0.75, 1.8, 0.6), "red", Vector3(0, 0.9, -0.15))
	B(n, Vector3(0.5, 1.0, 0.02), "glass", Vector3(-0.08, 1.15, 0.155))
	B(n, Vector3(0.12, 0.3, 0.02), "screen", Vector3(0.26, 1.2, 0.155))

static func _wc(n) -> void:
	C(n, 0.17, 0.13, 0.4, "white", Vector3(0, 0.2, 0.05), 16)
	C(n, 0.21, 0.21, 0.04, "white", Vector3(0, 0.42, 0.05), 18)
	B(n, Vector3(0.45, 0.42, 0.18), "white", Vector3(0, 0.62, -0.3))

static func _sink(n) -> void:
	B(n, Vector3(0.55, 0.12, 0.4), "white", Vector3(0, 0.82, -0.25))
	C(n, 0.06, 0.08, 0.76, "white", Vector3(0, 0.38, -0.32), 10)
	C(n, 0.015, 0.015, 0.18, "steel", Vector3(0, 0.95, -0.38), 6)
	B(n, Vector3(0.45, 0.55, 0.02), "glass", Vector3(0, 1.45, -0.44))

static func _coffee(n) -> void:
	B(n, Vector3(0.7, 0.9, 0.5), "wood_d", Vector3(0, 0.45, -0.2))
	B(n, Vector3(0.35, 0.45, 0.32), "black", Vector3(0, 1.13, -0.25))
	C(n, 0.04, 0.035, 0.09, "white", Vector3(0.2, 0.95, -0.1), 10)

static func _sofa(n, w) -> void:
	B(n, Vector3(w * 0.94, 0.42, 0.75), "fabric", Vector3(0, 0.21, -0.05))
	B(n, Vector3(w * 0.94, 0.5, 0.2), "fabric", Vector3(0, 0.65, -0.35))
	for sx in [-1, 1]:
		B(n, Vector3(0.16, 0.6, 0.75), "fabric", Vector3(sx * (w * 0.47 - 0.08), 0.3, -0.05))
	for i in int(w):
		B(n, Vector3(0.8, 0.1, 0.6), "fabric", Vector3(-w / 2.0 + 0.5 + i, 0.47, 0.0), 0.05)

static func _pump(n) -> void:
	B(n, Vector3(0.7, 1.2, 0.6), "teal", Vector3(0, 0.6, -0.2))
	C(n, 0.18, 0.18, 0.5, "steel", Vector3(0, 1.45, -0.2), 14)
	B(n, Vector3(0.3, 0.2, 0.02), "screen", Vector3(0, 0.9, 0.105))

static func _xray(n) -> void:
	B(n, Vector3(0.8, 2.0, 0.12), "white", Vector3(0, 1.0, -0.4))
	B(n, Vector3(0.65, 1.4, 0.03), "screen", Vector3(0, 1.1, -0.33))
	C(n, 0.06, 0.06, 2.2, "steel", Vector3(0.45, 1.1, 0.0), 8)
	B(n, Vector3(0.3, 0.3, 0.4), "white", Vector3(0.45, 1.6, 0.1))

static func _dnaseq(n) -> void:
	B(n, Vector3(0.8, 1.0, 0.6), "purple", Vector3(0, 0.5, -0.15))
	B(n, Vector3(0.5, 0.5, 0.4), "glass", Vector3(0, 1.25, -0.15))
	for i in 5:
		SP(n, 0.04, ["red", "blue", "yellow", "green", "white"][i], Vector3(-0.12 + i * 0.06, 1.1 + i * 0.07, -0.15))

static func _elchair(n) -> void:
	B(n, Vector3(0.62, 0.45, 0.6), "dark", Vector3(0, 0.22, 0))
	B(n, Vector3(0.58, 0.1, 0.55), "red", Vector3(0, 0.5, 0))
	B(n, Vector3(0.58, 0.8, 0.12), "red", Vector3(0, 0.9, -0.26))
	C(n, 0.2, 0.22, 0.18, "steel", Vector3(0, 1.45, -0.12), 14)
	for sx in [-1, 1]:
		B(n, Vector3(0.08, 0.25, 0.5), "dark", Vector3(sx * 0.31, 0.65, 0))

static func _pod(n) -> void:
	C(n, 0.42, 0.45, 0.12, "steel", Vector3(0, 0.06, -0.05), 22)
	var g = C(n, 0.4, 0.4, 2.0, "glass", Vector3(0, 1.1, -0.05), 22)
	C(n, 0.44, 0.44, 0.12, "steel", Vector3(0, 2.15, -0.05), 22)
	B(n, Vector3(0.2, 0.3, 0.05), "screen", Vector3(0.42, 1.2, 0.0))

static func _inflator(n) -> void:
	B(n, Vector3(0.7, 0.8, 0.6), "orange", Vector3(0, 0.4, -0.2))
	C(n, 0.15, 0.15, 0.7, "steel", Vector3(0.2, 1.15, -0.2), 12)
	var hose = C(n, 0.03, 0.03, 0.8, "dark", Vector3(-0.1, 1.2, -0.05), 8)
	hose.rotation.z = 0.6

static func _uvlamp(n) -> void:
	C(n, 0.03, 0.03, 1.9, "steel", Vector3(-0.3, 0.95, -0.3), 8)
	B(n, Vector3(0.7, 0.08, 0.4), "purple", Vector3(-0.05, 1.85, 0.0))
	var mm = m("purple")
	mm.emission_enabled = true; mm.emission = Color(0.6, 0.3, 1.0); mm.emission_energy_multiplier = 0.4

static func _morguefridge(n, w) -> void:
	B(n, Vector3(w * 0.95, 1.9, 0.7), "steel", Vector3(0, 0.95, -0.12))
	for i in 3:
		for j in 2:
			B(n, Vector3(w * 0.4, 0.5, 0.02), "white", Vector3(-w * 0.22 + j * w * 0.44, 0.4 + i * 0.6, 0.235))

static func _autopsy(n, w) -> void:
	B(n, Vector3(w * 0.85, 0.08, 0.75), "steel", Vector3(0, 0.85, 0))
	C(n, 0.08, 0.12, 0.82, "steel", Vector3(0, 0.41, 0), 12)

static func _organfridge(n) -> void:
	B(n, Vector3(0.7, 1.3, 0.6), "white", Vector3(0, 0.65, -0.15))
	B(n, Vector3(0.5, 0.6, 0.02), "glass", Vector3(0, 0.85, 0.155))
	B(n, Vector3(0.2, 0.2, 0.2), "red", Vector3(0, 0.8, -0.1))

static func _readdesk(n) -> void:
	B(n, Vector3(0.85, 0.05, 0.65), "wood", Vector3(0, 0.74, 0))
	C(n, 0.04, 0.06, 0.72, "wood_d", Vector3(0, 0.36, 0), 8)
	B(n, Vector3(0.3, 0.04, 0.22), "red", Vector3(0.1, 0.78, 0.05))
	C(n, 0.02, 0.02, 0.4, "steel", Vector3(-0.3, 0.95, -0.2), 6)

static func _aquarium(n) -> void:
	B(n, Vector3(0.85, 0.7, 0.5), "wood_d", Vector3(0, 0.35, -0.2))
	B(n, Vector3(0.8, 0.6, 0.45), "water", Vector3(0, 1.0, -0.2))
	SP(n, 0.05, "orange", Vector3(0.1, 1.0, -0.15), 0.6)
	SP(n, 0.05, "yellow", Vector3(-0.15, 1.1, -0.2), 0.6)

static func _noticeboard(n) -> void:
	B(n, Vector3(0.8, 0.6, 0.04), "wood", Vector3(0, 1.5, -0.46))
	B(n, Vector3(0.2, 0.25, 0.01), "paper", Vector3(-0.2, 1.52, -0.435))
	B(n, Vector3(0.2, 0.2, 0.01), "yellow", Vector3(0.15, 1.55, -0.435))
