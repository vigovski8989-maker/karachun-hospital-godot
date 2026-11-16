# Port of r3d.js buildStatic0 (45.x INTERIOR46): floors (FL46 finishes), walls (tall back / cut front, wainscot, windows),
# door leaves, reception portal/windows, furniture prefabs (furn46/*.scn exported from furn_i46.js) + decor46Room,
# plot fence; then merges static meshes by material and 12x12 m chunk (few draw calls, frustum culling still works).
class_name WorldBuild
extends RefCounted

const HB := 1.7
const HF := 0.32
const TH := 0.22
const CHUNK := 12.0
const NFP := {"scanner": [1, 2], "bed": [1, 2]}
const NF2 := ["recdesk", "desk", "tubes", "sofa", "labbench", "morguefridge", "autopsy", "bookcase", "chiefdesk", "bench"]
const FL46 := {"gp": ["vinyl", 0xe3efdf], "paygp": ["wood", 0xfff6ee], "diag": ["vinyl", 0xe8e2f1], "lab": ["tile", 0xeef3f5], "pharmacy": ["tile", 0xf6eeee], "ward": ["vinyl", 0xdef0ec], "psych": ["wood", 0xf6e8da], "pump": ["vinyl", 0xdde9f2], "toilet": ["tile", 0xe8f0f5], "staffroom": ["wood", 0xffffff], "cardio": ["vinyl", 0xf3e2e8], "surgery": ["tile", 0xe3f3ee], "icu": ["vinyl", 0xe3eff5], "xray": ["vinyl", 0xe3e8ee], "genetics": ["vinyl", 0xeee3f3], "electro": ["vinyl", 0xf4efdc], "reboot": ["vinyl", 0xe0edf6], "inflate": ["vinyl", 0xf6e7e1], "derma": ["vinyl", 0xece3f4], "research": ["tile", 0xe9f4ec], "morgue": ["tile", 0xe1ebf0], "transplant": ["tile", 0xe0f3ee], "library": ["wood", 0xe8d2b8], "chief": ["wood", 0xe2c8aa]}
const DL46 := {
	"gp": [["sinkPoster", "posterHeart", "filing", "posterEye", "clockSan", "tallcab"], ["lowPlant", "radiator"]],
	"paygp": [["bookshelf", "posterArt", "filing", "trophy", "clockSan"], ["lowWood", "radiator"]],
	"diag": [["console", "posterBrain", "tallcab", "sinkPoster"], ["radiator", "lowBoxes"]],
	"lab": [["shelfwall", "sinkPoster", "posterDNA", "tallcab"], ["lowBoxes"]],
	"pharmacy": [["shelfwall", "posterPills", "tallcab", "counter"], ["lowBoxes", "radiator"]],
	"ward": [["vitals", "linen", "posterLogo", "tv", "vitals"], ["radiator", "lowPlant"]],
	"psych": [["bookshelf", "posterBrain", "plant", "posterArt"], ["lowWood", "lowBooks"]],
	"pump": [["posterLungs", "oxygen", "tallcab", "trolley"], ["radiator"]],
	"inflate": [["posterLungs", "tallcab", "oxygen", "trolley"], ["radiator"]],
	"toilet": [["mirror", "posterWash", "mirror"], ["radiator"]],
	"staffroom": [["kitchen", "fridge", "cooler", "whiteboard", "tv"], ["lowWood", "radiator"]],
	"cardio": [["vitals", "posterHeart", "defib", "trolley"], ["radiator", "lowBoxes"]],
	"surgery": [["sinkPoster", "oxygen", "vitals", "trolley", "tallcab"], ["lowBoxes"]],
	"icu": [["vitals", "oxygen", "vitals", "trolley", "defib"], ["radiator"]],
	"xray": [["lightbox", "posterSkel", "apron", "console"], ["radiator"]],
	"genetics": [["shelfwall", "posterDNA", "whiteboard", "counter"], ["lowBoxes"]],
	"electro": [["posterWarn", "tallcab", "console"], ["radiator"]],
	"reboot": [["console", "posterWarn", "tallcab"], ["radiator"]],
	"derma": [["sinkPoster", "posterSkin", "trolley", "tallcab"], ["radiator"]],
	"research": [["whiteboard", "shelfwall", "bookshelf", "posterDNA"], ["lowBoxes"]],
	"morgue": [["steelcab", "sinkPoster", "steelcab", "posterSkel"], ["lowBoxes"]],
	"transplant": [["sinkPoster", "vitals", "oxygen", "trolley", "tallcab"], ["lowBoxes"]],
	"library": [["bookshelf", "bookshelf", "clockSan", "bookshelf", "posterArt"], ["lowBooks"]],
	"chief": [["bookshelf", "posterArt", "trophy", "filing"], ["lowWood", "lowBooks"]],
}

static var prefabs := {}
static var mats := {}

var sim
var root: Node3D          # static merged meshes go here
var live: Node3D          # temp: all instanced geometry before merge
var dyn: Node3D           # kept dynamic nodes (door leaves, named parts)
var doors := {}           # room id -> leaf Node3D
var parts := {}           # room id (or "corr") -> {name: [MeshInstance3D]}
var items_nodes := {}     # room id -> [{t, piv}]
var wall_v := PackedVector3Array()
var wall_n := PackedVector3Array()
var wall_c := PackedColorArray()
var wall_uv := PackedVector2Array()
var rwall_v := PackedVector3Array()
var rwall_n := PackedVector3Array()
var rwall_c := PackedColorArray()
var rwall_uv := PackedVector2Array()
var rec_wall := false

static func prefab(k: String) -> Node3D:
	if not prefabs.has(k):
		var p = "res://furn46/%s.scn" % k
		prefabs[k] = load(p) if ResourceLoader.exists(p) else null
	var ps: PackedScene = prefabs[k]
	if ps == null:
		if k != "cabinet": return prefab("cabinet")
		return Node3D.new()
	return ps.instantiate()

static func hexc(h: int) -> Color:
	return Color8((h >> 16) & 255, (h >> 8) & 255, h & 255)

static func mixw(c: Color, k: float) -> Color: return c.lerp(Color.WHITE, k)

static func vc_mat(key: String, rough: float, metal: float, tex: String = "") -> StandardMaterial3D:
	if mats.has(key): return mats[key]
	var m = StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	if tex != "":
		m.albedo_texture = load(tex)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats[key] = m
	return m

static func dir_yaw(d) -> float:
	match int(d):
		0: return PI / 2
		1: return 0.0
		2: return -PI / 2
		3: return PI
	return 0.0

func build(s, parent_static: Node3D, parent_dyn: Node3D) -> void:
	sim = s
	root = parent_static
	dyn = parent_dyn
	live = Node3D.new()
	root.add_child(live)
	_floors()
	_walls_and_rooms()
	# corridor items
	for t in sim.S.items: place_furn(t, null, "corr")
	_fence()
	_flush_walls()
	_merge()
	live.queue_free()

# ---------- floors ----------
func _floors() -> void:
	var S = sim.S
	var W: int = S.w
	var H: int = S.h
	var groups = {}   # kind -> [V, C, UV]
	var grass = hexc(0x86b46a)
	var grass2 = hexc(0x7aa960)
	var pathc = hexc(0xbab3a6)
	var roomgrid = {}
	for r in S.rooms:
		if r.get("par"): continue
		for y in range(r.y, r.y + r.h):
			for x in range(r.x, r.x + r.w): if not roomgrid.has(y * W + x): roomgrid[y * W + x] = r
	for v in range(-8, H + 8):
		for u in range(-8, W + 8):
			var in_map = u >= 0 and v >= 0 and u < W and v < H and not sim.isHole(u, v)
			var kind = "plain"
			var col: Color
			if not in_map:
				col = pathc if (absi(u - S.ent.x) < 1 and v >= H) else (grass if (u + v) & 1 else grass2)
			else:
				var r = roomgrid.get(v * W + u)
				if r and r.type == "reception":
					kind = "rec"; col = hexc(0xf3efe6)
				elif r:
					var f = FL46.get(r.type)
					if f: kind = f[0]; col = hexc(f[1]) * Color(.93, .93, .93, 1)   # keep white floors below clipping
					else: kind = "vinyl"; col = mixw(Color(sim.drm(r.type).get("color", "#cccccc")), .35)
				else:
					kind = "terr"; col = hexc(0xf2efe9) if (u + v) & 1 else hexc(0xebe7df)
			if not groups.has(kind): groups[kind] = [PackedVector3Array(), PackedColorArray(), PackedVector2Array()]
			var g = groups[kind]
			var y0 = 0.0
			# Godot front face = clockwise seen from above (+Y): (u,v),(u+1,v),(u+1,v+1)
			for q in [[u, v, 0, 0], [u + 1, v, 1, 0], [u + 1, v + 1, 1, 1], [u, v, 0, 0], [u + 1, v + 1, 1, 1], [u, v + 1, 0, 1]]:
				g[0].append(Vector3(q[0], y0, q[1])); g[1].append(col); g[2].append(Vector2(q[2], q[3]))
	for kind in groups:
		var g = groups[kind]
		var m: Material
		match kind:
			"plain": m = vc_mat("fl_plain", 0.95, 0.0)
			"rec": m = vc_mat("fl_rec", 0.48, 0.0, "res://assets/tex/rec7_tile.png")
			"terr": m = vc_mat("fl_terr", 0.8, 0.0, "res://assets/tex/i46_terrazzo.png")
			"wood": m = vc_mat("fl_wood", 0.62, 0.0, "res://assets/tex/i46_wood.png")
			"tile": m = vc_mat("fl_tile", 0.42, 0.0, "res://assets/tex/i46_tile4.png")
			_: m = vc_mat("fl_vinyl", 0.5, 0.0, "res://assets/tex/i46_vinyl.png")
		var N = PackedVector3Array(); N.resize(g[0].size()); N.fill(Vector3.UP)
		_add_mesh(root, g[0], N, g[1], g[2], m, false)

func _add_mesh(parent: Node3D, V, N, C, UV, m: Material, shadow := true) -> MeshInstance3D:
	if V.size() == 0: return null
	var a = []; a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = V; a[Mesh.ARRAY_NORMAL] = N
	if C != null and C.size(): a[Mesh.ARRAY_COLOR] = C
	if UV != null and UV.size(): a[Mesh.ARRAY_TEX_UV] = UV
	var am = ArrayMesh.new(); am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mi = MeshInstance3D.new(); mi.mesh = am; mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

# ---------- walls ----------
# JS box(w,h,d,x,y,z,col): axis-aligned box from (x,y,z) to (x+w,y+h,z+d)
func box(w: float, h: float, d: float, x: float, y: float, z: float, col: Color) -> void:
	var V = rwall_v if rec_wall else wall_v
	var N = rwall_n if rec_wall else wall_n
	var C = rwall_c if rec_wall else wall_c
	var U = rwall_uv if rec_wall else wall_uv
	var x1 = x + w
	var y1 = y + h
	var z1 = z + d
	# 6 faces, each clockwise when viewed from outside (Godot front face)
	var faces = [
		[Vector3(1, 0, 0), [Vector3(x1, y, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z), Vector3(x1, y, z)]],
		[Vector3(-1, 0, 0), [Vector3(x, y, z), Vector3(x, y1, z), Vector3(x, y1, z1), Vector3(x, y, z1)]],
		[Vector3(0, 1, 0), [Vector3(x, y1, z), Vector3(x1, y1, z), Vector3(x1, y1, z1), Vector3(x, y1, z1)]],
		[Vector3(0, -1, 0), [Vector3(x, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z), Vector3(x, y, z)]],
		[Vector3(0, 0, 1), [Vector3(x, y, z1), Vector3(x, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y, z1)]],
		[Vector3(0, 0, -1), [Vector3(x1, y, z), Vector3(x1, y1, z), Vector3(x, y1, z), Vector3(x, y, z)]],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var q: Array = f[1]
		for i in [0, 1, 2, 0, 2, 3]:
			var p: Vector3 = q[i]
			V.append(p); N.append(n); C.append(col)
			# world-space planar uv (plaster texture repeats every 0.5 m)
			U.append(Vector2(p.x + p.z, p.y) * 2.0 if absf(n.y) < .5 else Vector2(p.x, p.z) * 2.0)

func _flush_walls() -> void:
	_add_mesh(root, wall_v, wall_n, wall_c, wall_uv, vc_mat("wall", 0.9, 0.0, "res://assets/tex/wall_plaster.png"))
	_add_mesh(root, rwall_v, rwall_n, rwall_c, rwall_uv, vc_mat("rwall", 0.88, 0.0))

func _walls_and_rooms() -> void:
	var S = sim.S
	var cap = hexc(0x5b4636)
	for r in S.rooms:
		parts[r.id] = {}
		items_nodes[r.id] = []
		if not r.get("par"):
			rec_wall = r.type == "reception"
			var rcol = Color(sim.drm(r.type).get("color", "#cccccc"))
			var wc = hexc(0xeee9de) if rec_wall else mixw(rcol, .52)
			var RH = 1.95 if rec_wall else HB
			var RC = hexc(0xb7c8cd) if rec_wall else hexc(0xa9b9be).lerp(rcol, .3)
			var wain = rcol.lerp(hexc(0x8fa3ab), .22).lerp(Color.WHITE, .18)
			var rail = hexc(0xeef2f1)
			var skirt = (rcol * 0.5).lerp(hexc(0x4c5c63), .55)
			skirt.a = 1.0
			for y in range(r.y, r.y + r.h):
				for x in range(r.x, r.x + r.w):
					var is_door = x == r.door.x and y == r.door.y
					if not sim.isWall(r, x, y) and not is_door: continue
					var sT = y == r.y
					var sL = x == r.x
					var sB = y == r.y + r.h - 1
					var sR = x == r.x + r.w - 1
					if is_door:
						_door(r, x, y, RH, wc)
						continue
					if sT or sL:
						if sT and sL:
							box(TH, RH, 1, x, 0, y, wc); box(TH, .04, 1, x, RH, y, RC)
							if rec_wall: box(.025, .075, 1, x + TH, 0, y, wc)
						var top = sT
						var wk = 2 if rec_wall else 3
						var has_win = (not sB and (x + y) % wk == 0) if not sT else (not sL and not sR and (x + y) % wk == 0)
						if has_win:
							var wy = .58
							var wh = RH - .78
							if top:
								box(.09, RH, TH, x, 0, y, wc); box(.09, RH, TH, x + .91, 0, y, wc); box(.82, wy, TH, x + .09, 0, y, wc); box(.82, RH - wy - wh, TH, x + .09, wy + wh, y, wc)
							else:
								box(TH, RH, .09, x, 0, y, wc); box(TH, RH, .09, x, 0, y + .91, wc); box(TH, wy, .82, x, 0, y + .09, wc); box(TH, RH - wy - wh, .82, x, wy + wh, y + .09, wc)
							var win = prefab("extra_receptionWindow")
							_fit_window(win, wh)
							if top: win.position = Vector3(x + .5, wy, y + TH)
							else:
								win.position = Vector3(x + TH, wy, y + .5); win.rotation.y = PI / 2
							live.add_child(win)
						elif top: box(1, RH, TH, x, 0, y, wc)
						else: box(TH, RH, 1, x, 0, y, wc)
						if not rec_wall:
							if top:
								box(1, .55, .012, x, 0, y + TH, wain); box(1, .032, .024, x, .55, y + TH, rail); box(1, .08, .026, x, 0, y + TH, skirt)
							else:
								box(.012, .55, 1, x + TH, 0, y, wain); box(.024, .032, 1, x + TH, .55, y, rail); box(.026, .08, 1, x + TH, 0, y, skirt)
						if top:
							box(1, .04, TH, x, RH, y, RC)
							if rec_wall: box(1, .075, .025, x, 0, y + TH, wc)
						else:
							box(TH, .04, 1, x, RH, y, RC)
							if rec_wall: box(.025, .075, 1, x + TH, 0, y, wc)
					if sB:
						box(1, HF, TH, x, 0, y + 1 - TH, wc); box(1, .03, TH, x, HF, y + 1 - TH, RC)
					if sR:
						box(TH, HF, 1, x + 1 - TH, 0, y, wc); box(TH, .03, 1, x + 1 - TH, HF, y, RC)
			if r.type == "reception":
				var l = OmniLight3D.new()
				l.light_color = Color(0.94, 0.97, 1.0); l.light_energy = 1.2; l.omni_range = 6.0
				l.position = Vector3(r.x + r.w * .45, 2.8, r.y + r.h * .45)
				dyn.add_child(l)
		# furniture
		var lay = r.get("it")
		if lay == null or lay.is_empty():
			var L = sim.layout(r)
			if L: lay = L.items
		for t in (lay if lay else []): place_furn(t, r, r.id)
		if not r.get("par") and r.type != "reception": decor46_room(r)
	rec_wall = false

# receptionWindow(w=.82,h) was exported with the default h=1.15; scale vertically to the real opening
func _fit_window(win: Node3D, wh: float) -> void:
	win.scale = Vector3(1, wh / 1.15, 1)

func _door(r, x: int, y: int, RH: float, wc: Color) -> void:
	var side = int(r.side)
	var back = side >= 2
	var hz = side == 0 or side == 2
	if r.type == "reception" and not back:
		var ox = x + 1 - TH if side == 1 else x
		var oz = y + 1 - TH if side == 0 else y
		var portal = prefab("extra_receptionEntrance")
		if hz: portal.position = Vector3(x, 0, oz + TH / 2)
		else:
			portal.position = Vector3(ox + TH / 2, 0, y + 1); portal.rotation.y = PI / 2
		live.add_child(portal)
		return
	var H = RH if back else HF
	var ox2 = x if side == 3 else (x + 1 - TH if side == 1 else x)
	var oz2 = y if side == 2 else (y + 1 - TH if side == 0 else y)
	if hz:
		box(.12, H, TH, x, 0, oz2, wc); box(.12, H, TH, x + .88, 0, oz2, wc)
		if back and RH > 2.1: box(1, RH - 2.05, TH, x, 2.05, oz2, wc)
	else:
		box(TH, H, .12, ox2, 0, y, wc); box(TH, H, .12, ox2, 0, y + .88, wc)
		if back and RH > 2.1: box(TH, RH - 2.05, 1, ox2, 2.05, y, wc)
	if back:
		var leaf = Node3D.new()
		var sy = minf(1.0, (RH - .03) / 2.0)
		var lm = Geo.box(leaf, Vector3(.74, 2.0 * sy, .05), Geo.mat(hexc(0x8fbfd8), 0.6), Vector3(.38, 0, 0), 0.01)
		lm.position.y = sy
		var hd = MeshInstance3D.new(); var sm = SphereMesh.new(); sm.radius = .04; sm.height = .08; sm.radial_segments = 8; sm.rings = 6
		hd.mesh = sm; hd.material_override = Geo.mat(hexc(0xd4af37), 0.3, 0.8); hd.position = Vector3(.68, 1, .05)
		leaf.add_child(hd)
		if hz: leaf.position = Vector3(x + .13, 0, oz2 + TH / 2)
		else:
			leaf.position = Vector3(ox2 + TH / 2, 0, y + .87); leaf.rotation.y = PI / 2
		leaf.set_meta("base", leaf.rotation.y)
		dyn.add_child(leaf)
		doors[r.id] = leaf

func _fence() -> void:
	var S = sim.S
	var fc = hexc(0xe9e2d2)
	for u in range(-1, S.w + 1):
		if absi(u - S.ent.x) < 1: continue
		box(1, .5, .12, u, 0, -1.1, fc)
	for v in range(-1, S.h):
		box(.12, .5, 1, -1.1, 0, v, fc)

# ---------- furniture ----------
func place_yaw(t, r) -> float:
	var k = t.get("k", t.get("type"))
	var fp = t.get("fp") if t.get("fp") else sim.fpOf(k)
	if t.get("dir") != null: return dir_yaw(t.dir)
	if r and k in ["desk", "recdesk", "chiefdesk"] and r.get("sp") and r.sp.get("staff"):
		var st = r.sp.staff
		var du = (t.x + fp[0] / 2.0) - (st.x + .5)
		var dv = (t.y + fp[1] / 2.0) - (st.y + .5)
		if absf(du) > absf(dv): return PI / 2 if du > 0 else -PI / 2
		return 0.0 if dv > 0 else PI
	var nfp = NFP.get(k)
	if nfp == null: nfp = sim.D.furn[k].fp if sim.D.furn.has(k) else fp
	if r == null: return 0.0
	var cx = t.x + fp[0] / 2.0
	var cy = t.y + fp[1] / 2.0
	var rx = r.x + r.w / 2.0
	var ry = r.y + r.h / 2.0
	var dsd = [[0, 1], [1, 0], [0, -1], [-1, 0]][int(r.get("side", 0))]
	var same = int(fp[0]) == int(nfp[0]) and int(fp[1]) == int(nfp[1])
	var sq = int(fp[0]) == int(fp[1])
	if sq:
		var du = rx - cx
		var dv = ry - cy
		if absf(du) < .01 and absf(dv) < .01: return atan2(dsd[0], dsd[1])
		if absf(du) > absf(dv): return PI / 2 if du > 0 else -PI / 2
		return 0.0 if dv > 0 else PI
	if same:
		var dv2 = ry - cy
		if absf(dv2) < .01: return PI if dsd[1] < 0 else 0.0
		return 0.0 if dv2 > 0 else PI
	var du2 = rx - cx
	if absf(du2) < .01: return -PI / 2 if dsd[0] < 0 else PI / 2
	return PI / 2 if du2 > 0 else -PI / 2

func place_furn(t, r, key) -> Node3D:
	var k = str(t.get("k", t.get("type")))
	var fp = t.get("fp") if t.get("fp") else sim.fpOf(k)
	var mk = k
	if r and r.type == "reception":
		if k == "cabinet": mk = "rec_cabinet"
		elif k == "noticeboard": mk = "rec_noticeboard"
		elif k == "plant": mk = "rec_plant"
		elif k == "chair_office": mk = "chair_office_v45"
	var g = prefab(mk)
	var nf = NFP.get(k)
	if nf == null: nf = fp if int(fp[0]) == int(fp[1]) else null
	if nf == null: nf = [2, 1] if k in NF2 else fp
	var piv = Node3D.new()
	piv.position = Vector3(t.x + fp[0] / 2.0, 0, t.y + fp[1] / 2.0)
	piv.rotation.y = place_yaw(t, r)
	g.position = Vector3(-nf[0] / 2.0, 0, -nf[1] / 2.0)
	piv.add_child(g)
	live.add_child(piv)
	# named animated parts stay dynamic (moved out of the merge set later)
	if not parts.has(key): parts[key] = {}
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("part"):
			var pn = str(mi.get_meta("part"))
			if not parts[key].has(pn): parts[key][pn] = []
			parts[key][pn].append(mi)
			mi.set_meta("keep", true)
	if items_nodes.has(key): items_nodes[key].append({"t": t, "piv": piv})
	return piv

func decor46_room(r) -> void:
	var L = DL46.get(r.type)
	if L == null: return
	var ti = 0
	var li = 0
	var dr = r.get("door") if r.get("door") else {"x": -9, "y": -9}
	var put = func(x: int, y: int, left: bool, win: bool, cnt: Array):
		var k = L[1][cnt[1] % L[1].size()] if win else L[0][cnt[0] % L[0].size()]
		if win: cnt[1] += 1
		else: cnt[0] += 1
		var g = prefab("decor_" + k)
		if left:
			g.position = Vector3(x, 0, y + 1); g.rotation.y = PI / 2
		else:
			g.position = Vector3(x, 0, y)
		live.add_child(g)
	var cnt = [0, 0]   # arrays are shared by reference inside lambdas
	for x in range(r.x + 1, r.x + r.w - 1):
		var y = r.y
		if dr.y == y and absi(dr.x - x) <= 1: continue
		put.call(x, y, false, (x + y) % 3 == 0, cnt)
	for y in range(r.y + 1, r.y + r.h - 1):
		var x = r.x
		if dr.x == x and absi(dr.y - y) <= 1: continue
		put.call(x, y, true, (x + y) % 3 == 0, cnt)
	var pl = prefab("rec_plant")
	pl.scale = Vector3.ONE * .8
	pl.position = Vector3(r.x + .4 - .4, 0, r.y + .4 - .4)
	live.add_child(pl)

# ---------- merge ----------
func _plain(m: Material) -> bool:
	if not m is StandardMaterial3D: return false
	var s: StandardMaterial3D = m
	return s.albedo_texture == null and s.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and not s.emission_enabled and s.cull_mode == BaseMaterial3D.CULL_BACK and s.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL

func _merge() -> void:
	# freeze item pivots into plain transform markers (pivot nodes are freed by merging)
	for rid in items_nodes:
		for it in items_nodes[rid]:
			var mk = Node3D.new()
			dyn.add_child(mk)
			mk.global_transform = it.piv.global_transform
			it.piv = mk
	var groups = {}
	var keep = []
	for mi in live.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("keep"):
			keep.append(mi); continue
		if mi.mesh == null: continue
		var xf: Transform3D = mi.global_transform if mi.is_inside_tree() else _gx(mi)
		var nb = xf.basis.inverse().transposed()
		var flip = xf.basis.determinant() < 0
		var c = xf.origin
		var chunk = str(int(floor(c.x / CHUNK)), ":", int(floor(c.z / CHUNK)))
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(si)
			if m == null: m = Geo.mat(Color(0.8, 0.8, 0.8))
			var plain = _plain(m)
			var gm: Material = m
			var col = Color.WHITE
			if plain:
				var s: StandardMaterial3D = m
				col = s.albedo_color
				gm = vc_mat("p_%.2f_%.1f" % [snappedf(s.roughness, .05), snappedf(s.metallic, .1)], snappedf(s.roughness, .05), snappedf(s.metallic, .1))
			var key = str(gm.get_instance_id(), "|", chunk)
			if not groups.has(key): groups[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "c": PackedColorArray(), "m": gm}
			var G = groups[key]
			var arr = mi.mesh.surface_get_arrays(si)
			var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nn = arr[Mesh.ARRAY_NORMAL]
			var uu = arr[Mesh.ARRAY_TEX_UV]
			var cc = arr[Mesh.ARRAY_COLOR]
			var idx = arr[Mesh.ARRAY_INDEX]
			var has_n = nn != null and nn.size() == vv.size()
			var has_u = uu != null and uu.size() == vv.size()
			var has_c = cc != null and cc.size() == vv.size()
			var order: PackedInt32Array
			if idx != null and idx.size() > 0: order = idx
			else:
				order = PackedInt32Array(); order.resize(vv.size())
				for i in vv.size(): order[i] = i
			var tri = order.size() / 3
			for t in tri:
				for j in ([0, 2, 1] if flip else [0, 1, 2]):
					var i = order[t * 3 + j]
					G.v.append(xf * vv[i])
					G.n.append((nb * (nn[i] if has_n else Vector3.UP)).normalized())
					G.uv.append(uu[i] if has_u else Vector2.ZERO)
					G.c.append(col * (cc[i] if has_c else Color.WHITE) if plain or has_c else Color.WHITE)
	for k in groups:
		var G = groups[k]
		_add_mesh(root, G.v, G.n, G.c, G.uv, G.m)
	# re-parent kept dynamic parts to dyn with their world transform
	for mi in keep:
		var xf = mi.global_transform if mi.is_inside_tree() else _gx(mi)
		mi.get_parent().remove_child(mi)
		dyn.add_child(mi)
		mi.global_transform = xf
		mi.set_meta("base_xf", xf)

func _gx(n: Node3D) -> Transform3D:
	var t = n.transform
	var p = n.get_parent()
	while p is Node3D:
		t = p.transform * t
		p = p.get_parent()
	return t
