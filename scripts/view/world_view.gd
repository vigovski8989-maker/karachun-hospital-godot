# 3D world built from the sim state: floors, walls (cutaway on the camera side), doors, furniture, corridor items,
# litter, characters. Static parts are merged per material (few draw calls); rebuilt only when the layout changes.
class_name WorldView
extends Node3D

const WALL_H := 2.3
const WALL_LOW := 0.38
const WALL_T := 0.22

var sim
var static_root: Node3D
var dyn_root: Node3D
var chars_root: Node3D
var doors = {}          # room id -> {leaf: Node3D, side}
var puppets = {}        # entity id -> CharPuppet
var sig = ""
var mats = {}
var litter_mm: MultiMeshInstance3D
var vomit_mm: MultiMeshInstance3D
var cam: Camera3D
var labels = {}
var machine_fx = {}
var wb: WorldBuild

func _ready() -> void:
	static_root = Node3D.new(); static_root.name = "Static"; add_child(static_root)
	dyn_root = Node3D.new(); dyn_root.name = "Dyn"; add_child(dyn_root)
	chars_root = Node3D.new(); chars_root.name = "Chars"; add_child(chars_root)
	_mats()
	litter_mm = _mk_mm(Color(0.55, 0.5, 0.42), Vector3(0.22, 0.02, 0.16))
	vomit_mm = _mk_mm(Color(0.6, 0.68, 0.18), Vector3(0.38, 0.015, 0.3))

func _mk_mm(col: Color, size: Vector3) -> MultiMeshInstance3D:
	var mmi = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm = BoxMesh.new(); bm.size = size
	mm.mesh = bm
	mmi.multimesh = mm
	mmi.material_override = Geo.mat(col, 0.8)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi

func _mats() -> void:
	var fl = ShaderMaterial.new(); fl.shader = load("res://shaders/floor.gdshader")
	fl.set_shader_parameter("tile", 1.0)
	mats.floor = fl
	var gr = ShaderMaterial.new(); gr.shader = load("res://shaders/grass.gdshader")
	mats.grass = gr
	var pw = ShaderMaterial.new(); pw.shader = load("res://shaders/paint.gdshader")
	pw.set_shader_parameter("col", Vector3(0.93, 0.91, 0.86))
	mats.wall = pw
	mats.wall_top = Geo.mat(Color(0.55, 0.58, 0.62), 0.6)
	mats.skirt = Geo.mat(Color(0.35, 0.42, 0.5), 0.5)
	mats.door = Geo.mat(Color(0.62, 0.45, 0.30), 0.5)
	mats.frame = Geo.mat(Color(0.85, 0.86, 0.88), 0.4, 0.3)
	mats.lot = Geo.mat(Color(1.0, 0.88, 0.45, 0.22), 0.9)
	mats.lot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mats.hole = Geo.mat(Color(0.25, 0.35, 0.22), 0.95)
	mats.outer = Geo.mat(Color(0.72, 0.66, 0.58), 0.8)

func layout_sig() -> String:
	var S: Dictionary = sim.S
	var s = str(S.lv, ":", S.w, "x", S.h, ":")
	for r in S.rooms: s += str(r.id, ",")
	s += ":" + str(S.items.size())
	for l in S.get("lots", []): s += ("1" if l.own else "0")
	return s

func sync(gdt: float) -> void:
	if sim == null or sim.S.is_empty(): return
	var ns = layout_sig()
	if ns != sig:
		sig = ns
		rebuild()
		_tiles = {}
	_sync_doors(gdt)
	_sync_litter()
	_sync_chars(gdt)
	_anim_rooms(gdt)
	_tick_emotes(gdt)
	_sync_labels()

# tile -> room furniture item (for view-side "don't walk through furniture" and seat approach)
var _tiles = {}
var _tiles_n = -1
func item_at_tile(x: int, y: int):
	var tn = sim.S.rooms.size() * 100000 + sim.S.items.size()
	if _tiles.is_empty() or _tiles_n != tn:
		_tiles = {"_": true}; _tiles_n = tn
		for r in sim.S.rooms:
			for t in r.get("it", []):
				var fp = t.get("fp") if t.get("fp") else sim.fpOf(t.k)
				for tt in sim.tilesOf(t.x, t.y, fp): _tiles[tt[1] * 10000 + tt[0]] = t
		# 0.9.6: corridor items too (benches, bins, vending...) so walkers never step up onto a bench seat
		for i in sim.S.items:
			var fp2 = i.get("fp") if i.get("fp") != null else sim.fpOf(i.type)
			var w = {"k": str(i.type), "soft": false, "corr": true}
			for tt in sim.tilesOf(i.x, i.y, fp2): _tiles[tt[1] * 10000 + tt[0]] = w
	return _tiles.get(y * 10000 + x)

func rebuild() -> void:
	for c in static_root.get_children(): c.queue_free()
	for c in dyn_root.get_children(): c.queue_free()
	doors.clear(); labels.clear(); machine_fx.clear(); _stage.clear()
	var S: Dictionary = sim.S
	var W: int = S.w
	var H: int = S.h
	var tmp = Node3D.new()
	static_root.add_child(tmp)
	# ground beyond the 8-tile grass margin
	var g = MeshInstance3D.new(); var gp = PlaneMesh.new(); gp.size = Vector2(W + 80, H + 80)
	g.mesh = gp; g.material_override = mats.grass; g.position = Vector3(W / 2.0, -0.03, H / 2.0)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	static_root.add_child(g)
	tmp.queue_free()
	wb = WorldBuild.new()
	wb.build(sim, static_root, dyn_root)
	for l in S.get("lots", []):
		if not l.own:
			_flat(dyn_root, Rect2(l.x, l.y, l.w, l.h), mats.lot, 0.01)
			var lab = Label3D.new()
			lab.text = "Участок $" + str(int(l.price))
			lab.font_size = 64; lab.pixel_size = 0.01; lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lab.modulate = Color(1, 0.9, 0.5); lab.outline_size = 10
			lab.position = Vector3(l.x + l.w / 2.0, 0.6, l.y + l.h / 2.0)
			dyn_root.add_child(lab)
	for r in S.rooms:
		if r.get("par"): continue
		var lab2 = Label3D.new()
		lab2.text = sim.drm(r.type).name
		lab2.font_size = 40; lab2.pixel_size = 0.006; lab2.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab2.outline_size = 12; lab2.outline_modulate = Color(0.08, 0.18, 0.24, 0.95)
		# 0.9.6: a plaque on a short post standing on the wall top (readable, attached to the wall)
		var post = MeshInstance3D.new(); var pm = BoxMesh.new(); pm.size = Vector3(.07, .16, .07)
		post.mesh = pm; post.position = Vector3(r.x + r.w / 2.0, WorldBuild.HB + .08, r.y + WorldBuild.TH / 2.0)
		var pmat = StandardMaterial3D.new(); pmat.albedo_color = Color(0.08, 0.18, 0.24); post.material_override = pmat
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dyn_root.add_child(post)
		lab2.set_meta("maxw", maxf(1.2, r.w - 0.3)); lab2.set_meta("hb", WorldBuild.HB + .14)
		lab2.font = UIKit.font_800
		lab2.modulate = Color(1, 1, 1, 0.92)
		lab2.width = 400; lab2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# middle of the back wall, just above the wall top: never on top of people (0.9.5)
		lab2.position = Vector3(r.x + r.w / 2.0, WorldBuild.HB + 0.4, r.y + WorldBuild.TH / 2.0)
		dyn_root.add_child(lab2)
		labels[r.id] = lab2
		if r.type == "lab": _lab_stool(r)
	_lab_zoom = -1.0
	var ent = Label3D.new()
	ent.text = "Больница «Карачун»"
	ent.font_size = 48; ent.pixel_size = 0.008; ent.billboard = BaseMaterial3D.BILLBOARD_ENABLED; ent.outline_size = 12
	ent.modulate = Color(1, 0.95, 0.7)
	ent.position = Vector3(S.ent.x + 0.5, 1.0, H + 3.6)   # on the lawn, away from the walking crowd
	ent.font = UIKit.font_800
	dyn_root.add_child(ent)
	labels["ent"] = ent

func _lab_stool(r) -> void:
	var sp = sim.spotPatient(r)
	var yw = CharPuppet.dir_yaw(sp.get("dir"))
	var f = Vector3(sin(yw), 0, cos(yw))
	var c = Vector3(float(sp.x) + .5, 0, float(sp.y) + .5) - f * 0.14
	var n = Node3D.new(); n.position = c
	var mt = Geo.mat(Color(0.25, 0.27, 0.3), 0.4, 0.5)
	var seat = Geo.mat(Color(0.2, 0.45, 0.75), 0.55)
	var cy = CylinderMesh.new(); cy.top_radius = .19; cy.bottom_radius = .19; cy.height = .06; cy.radial_segments = 16
	Geo.mi(n, cy, seat, Vector3(0, .47, 0), 0.0)
	var lg = CylinderMesh.new(); lg.top_radius = .03; lg.bottom_radius = .03; lg.height = .44; lg.radial_segments = 8
	Geo.mi(n, lg, mt, Vector3(0, .23, 0), 0.0)
	var bs = CylinderMesh.new(); bs.top_radius = .17; bs.bottom_radius = .2; bs.height = .03; bs.radial_segments = 16
	Geo.mi(n, bs, mt, Vector3(0, .015, 0), 0.0)
	dyn_root.add_child(n)

func _sync_doors(_gdt: float) -> void:
	if wb == null: return
	for r in sim.S.rooms:
		var leaf = wb.doors.get(r.id)
		if leaf == null: continue
		# 0.9.6: swing ~100 deg AWAY from whoever is walking through (latched until closed) -> the leaf never cuts an arm
		var dop = minf(1.0, float(r.get("dop", 0.0)))
		var base = float(leaf.get_meta("base"))
		var sg = float(leaf.get_meta("sg", 0.0))
		if dop < 0.02: sg = 0.0
		elif sg == 0.0:
			var B0 = Basis(Vector3.UP, base)
			var C0 = leaf.position + B0 * Vector3(.37, 0, 0)
			var nrm = B0 * Vector3(0, 0, 1)
			var best = null; var bd = 9.0
			for e in sim.S.pats + sim.S.staff:
				var d = absf(float(e.x) + .5 - C0.x) + absf(float(e.y) + .5 - C0.z)
				if d < bd: bd = d; best = e
			sg = 1.0
			if best != null:
				var side = (Vector3(float(best.x) + .5, 0, float(best.y) + .5) - C0).dot(nrm)
				var tip = (Basis(Vector3.UP, base + 1.0) * Vector3(.74, 0, 0)).dot(nrm)
				sg = -1.0 if side * tip > 0 else 1.0
		leaf.set_meta("sg", sg)
		var t = ease(dop, 0.6) * 1.75
		leaf.rotation.y = base + (sg if sg != 0.0 else -1.0) * t

func _sync_litter() -> void:
	var lit: Array = sim.S.litter
	var a = []
	var b = []
	for l in lit:
		if l.get("v"): b.append(l)
		else: a.append(l)
	_fill_mm(litter_mm, a)
	_fill_mm(vomit_mm, b)

func _fill_mm(mmi: MultiMeshInstance3D, arr: Array) -> void:
	var mm = mmi.multimesh
	if mm.instance_count != arr.size(): mm.instance_count = arr.size()
	for i in arr.size():
		var l = arr[i]
		var h = float(hash(str(i))) 
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, fmod(float(l.x) * 7.3 + float(l.y) * 3.1, TAU)), Vector3(float(l.x) + 0.5, 0.012, float(l.y) + 0.5)))

const BIG := ["balloonhead", "cloudhead", "statichair", "flathead"]
const INV := ["lostshadow"]
# 45.x drew these skin diseases with a bandaged "mummy" body (looked like an untextured mannequin);
# 0.9.2 shows them as a normal patient with the symptom painted on the skin instead
const MUM := []
const DIS_ICON := {"pixel": "👾", "yawn": "🥱", "nosewhistle": "🎶", "giggles": "🤭", "grumpliver": "😤", "squareeyes": "🔲", "balloonhead": "🎈", "echo": "🔁", "rubberknee": "🦘", "puffytoes": "🦶", "selfiesyndrome": "🤳", "blinknose": "🔴", "drumheart": "🥁", "soapsneeze": "🫧", "jellyspine": "🍮", "lostshadow": "👻", "fizzyblood": "🥤", "twistedtongue": "👅", "cloudhead": "☁️", "hiccupclock": "⏰", "glowskin": "✨", "spotty": "🍄", "zebra": "🦓", "tail": "🐒", "flathead": "🥞", "deflated": "🫠", "statichair": "⚡", "lowbattery": "🪫", "bluescreen": "💻", "looping": "🔂", "lazyheart": "🫀", "wanderliver": "🧳", "chattykidney": "💬", "bagpipelungs": "🎵", "gourmetstomach": "🦪", "lovesickheart": "💘", "sneezykidney": "🤧"}
const SHOES := [Color(0.13, 0.11, 0.1), Color(0.36, 0.22, 0.13), Color(0.93, 0.93, 0.92), Color(0.18, 0.3, 0.55), Color(0.55, 0.12, 0.12), Color(0.5, 0.45, 0.4)]
const ROCK := ["echo", "giggles", "drumheart", "looping", "bagpipelungs", "hiccupclock"]
const STAFF_GLB := {"doctor": "doctor", "nurse": "nurse", "receptionist": "receptionist", "handyman": "orderly", "orderly": "orderly"}
const STAFF_TINT := {"handyman": Color(0.3, 0.45, 0.85), "orderly": null}

func _make_puppet(e: Dictionary, staff: bool) -> CharPuppet:
	var p = CharPuppet.new()
	chars_root.add_child(p)
	var glb = "patient_a"
	var tint = null
	var dis_look = ""
	var L: Dictionary = {}
	if staff:
		glb = STAFF_GLB.get(e.type, "patient_a")
		tint = STAFF_TINT.get(e.type)
		p.kind = e.type
	else:
		var dis: String = "" if e.get("healed") else str(e.get("dis", ""))
		dis_look = dis
		L = LookPool.roll(e, dis, bool(e.get("vip", false)))
		glb = L.glb; tint = L.tint
		if L.tex != "": p.cloth_tex = load(L.tex)
		p.kind = "patient"
	p.is_staff = staff
	p.eid = e.id
	p.setup("res://assets/chars/%s.glb" % glb, tint, float(L.scale) if not L.is_empty() else 1.0)
	if not L.is_empty(): LookPool.apply(p, L)
	var hsh: int = absi(hash(int(e.id) * 7919 + 13))
	var tone: Color = CharPuppet.SKIN_TONES[hsh % CharPuppet.SKIN_TONES.size()]
	var shoe: Color = SHOES[(hsh / 7) % SHOES.size()]
	if staff:
		shoe = Color(0.95, 0.95, 0.95) if e.type == "nurse" else (Color(0.1, 0.1, 0.1) if e.type in ["doctor", "receptionist"] else Color(0.2, 0.2, 0.22))
	p.set_look(tone, shoe, dis_look)
	p.healed_look = (e.get("healed") == true)
	if not staff and dis_look != "" and DIS_ICON.has(dis_look):
		# 0.9.5 used emoji text: some phones draw missing glyphs as white rectangles -> bundled icon textures
		var bl = Sprite3D.new()
		bl.texture = load("res://assets/icons/%s.png" % dis_look)
		bl.pixel_size = 0.0022
		bl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bl.shaded = false; bl.double_sided = true; bl.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		bl.position = Vector3(0, 2.0, 0)
		p.add_child(bl)
		p.badge = bl
	if glb == "invisible":
		for mi in p.find_children("*", "MeshInstance3D", true, false):
			if not "Clothes" in str(mi.name): mi.visible = false
		p.attach_prop("hat", _hat(), "Head", Vector3(0, 0.16, 0))
		p.attach_prop("glasses", _glasses(), "Head", Vector3(0, 0.09, 0.105))
	if staff and e.type == "receptionist":
		p.attach_prop("glasses", _glasses(), "Head", Vector3(0, 0.09, 0.105))
	if staff and e.type == "nurse":
		p.attach_prop("cap", _nurse_cap(), "Head", Vector3(0, 0.22, 0.0))
	return p

static func _shirt_hue(h: float) -> float:
	# skip skin-like browns/oranges so a shirt never reads as a bare torso
	return fmod(h + 160.0, 360.0) if h > 8.0 and h < 50.0 else h

func _glasses() -> Node3D:
	var n = Node3D.new()
	var fm = Geo.mat(Color(0.08, 0.08, 0.1), 0.3, 0.4)
	var gl = Geo.mat(Color(0.8, 0.9, 1.0, 0.35), 0.05)
	gl.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for sx in [-1, 1]:
		var t = TorusMesh.new(); t.inner_radius = 0.028; t.outer_radius = 0.036; t.rings = 16; t.ring_segments = 6
		var r = Geo.mi(n, t, fm, Vector3(sx * 0.045, 0, 0), 0.0, false)
		r.rotation.x = PI / 2
		var lens = CylinderMesh.new(); lens.top_radius = 0.03; lens.bottom_radius = 0.03; lens.height = 0.004; lens.radial_segments = 14
		var l = Geo.mi(n, lens, gl, Vector3(sx * 0.045, 0, 0), 0.0, false)
		l.rotation.x = PI / 2
	Geo.box(n, Vector3(0.025, 0.006, 0.006), fm, Vector3(0, 0.005, 0), 0.002)
	for sx in [-1, 1]:
		Geo.box(n, Vector3(0.006, 0.006, 0.11), fm, Vector3(sx * 0.08, 0.005, -0.055), 0.002)
	return n

func _hat() -> Node3D:
	var n = Node3D.new()
	var m = Geo.mat(Color(0.12, 0.12, 0.14), 0.7)
	Geo.cyl(n, 0.16, 0.16, 0.012, m, Vector3.ZERO, 20)
	Geo.cyl(n, 0.095, 0.1, 0.13, m, Vector3(0, 0.07, 0), 18)
	return n

func _nurse_cap() -> Node3D:
	var n = Node3D.new()
	var w = Geo.mat(Color(0.97, 0.97, 0.97), 0.6)
	var red = Geo.mat(Color(0.85, 0.15, 0.15), 0.5)
	Geo.box(n, Vector3(0.2, 0.07, 0.12), w, Vector3(0, 0, 0.02), 0.02)
	Geo.box(n, Vector3(0.05, 0.016, 0.004), red, Vector3(0, 0.0, 0.082), 0.001)
	Geo.box(n, Vector3(0.016, 0.05, 0.004), red, Vector3(0, 0.0, 0.082), 0.001)
	return n

func _sync_chars(gdt: float) -> void:
	var seen = {}
	var cp: Vector3 = cam.global_position if cam else Vector3.ZERO
	var focus = Vector3.ZERO
	if cam and cam.has_method("get_focus"): focus = cam.get_focus()
	var zoom: float = cam.size if cam else 20.0
	var vs = get_viewport().get_visible_rect().size
	_tall = maxf(1.0, vs.y / maxf(1.0, vs.x)) if cam and cam.keep_aspect == Camera3D.KEEP_WIDTH else 1.0
	_scale_labels(zoom)
	for e in sim.S.pats:
		_sync_one(e, false, gdt, seen, focus, zoom)
	for e in sim.S.staff:
		_sync_one(e, true, gdt, seen, focus, zoom)
	for id in puppets.keys():
		if not seen.has(id):
			puppets[id].queue_free()
			puppets.erase(id)
	_separate(gdt)

# visual-only personal space: standing/walking bodies closer than MIN_SEP are eased apart (sim positions untouched),
# so two people never render inside each other at doors / queues
const MIN_SEP := 0.7
func _separate(gdt: float) -> void:
	_separate_pass(gdt, 0)

func _separate_pass(gdt: float, pass_i: int) -> void:
	var arr = []
	for id in puppets:
		var p: CharPuppet = puppets[id]
		if p.visible and p.lie_k < 0.05: arr.append(p)
	var push = {}
	for i in arr.size():
		var a: CharPuppet = arr[i]
		var fa = a.is_fixed()
		for j in range(i + 1, arr.size()):
			var b: CharPuppet = arr[j]
			var dx = b.position.x - a.position.x
			var dz = b.position.z - a.position.z
			if absf(dx) > MIN_SEP or absf(dz) > MIN_SEP: continue
			var d = sqrt(dx * dx + dz * dz)
			if d >= MIN_SEP: continue
			var fb = b.is_fixed()
			if fa and fb: continue
			var n = Vector3(dx, 0, dz) / d if d > 0.001 else Vector3(1, 0, 0).rotated(Vector3.UP, float(a.eid * 7 + b.eid))
			var k = (MIN_SEP - d) * 0.5
			var ka = 0.0 if fa else (k * 2.0 if fb else k)
			var kb = 0.0 if fb else (k * 2.0 if fa else k)
			push[a] = push.get(a, Vector3.ZERO) - n * ka
			push[b] = push.get(b, Vector3.ZERO) + n * kb
	for p in arr:
		if pass_i == 1:
			if not p.is_fixed(): p.position += _free_push(p.position, push.get(p, Vector3.ZERO).limit_length(0.3)) * 0.6
			continue
		if p.is_fixed():
			p.sep_off = p.sep_off.lerp(Vector3.ZERO, minf(1.0, gdt * 10.0 + 0.1))
			p.position += p.sep_off
			continue
		var tgt: Vector3 = push.get(p, Vector3.ZERO)
		if tgt.length() > 0.55: tgt = tgt.normalized() * 0.55
		tgt = _free_push(p.position, tgt)
		p.sep_off = p.sep_off.lerp(tgt, minf(1.0, 0.3 + gdt * 8.0))
		p.position += p.sep_off
	if pass_i == 0: _separate_pass(gdt, 1)

# never push a body through a wall or into solid furniture
func _free_push(pos: Vector3, off: Vector3) -> Vector3:
	if off.length() < 0.001: return off
	var r0 = sim.roomAt(int(floor(pos.x)), int(floor(pos.z)))
	for o in [off, Vector3(off.x, 0, 0), Vector3(0, 0, off.z), off * 0.5]:
		var q = pos + o
		var tx = int(floor(q.x)); var tz = int(floor(q.z))
		if tx == int(floor(pos.x)) and tz == int(floor(pos.z)): return o
		if sim.walk(tx, tz) and sim.roomAt(tx, tz) == r0:
			var it = item_at_tile(tx, tz)
			if it == null or it.get("soft"): return o
	return Vector3.ZERO

var _tall = 1.0
var audit_all = false   # debug audit: every puppet visible + full-rate animation
var _lab_zoom = -1.0
func _scale_labels(zoom: float) -> void:
	# room names keep a readable, constant on-screen size (portrait: zoom = visible width in metres)
	if absf(zoom - _lab_zoom) < 0.05: return
	_lab_zoom = zoom
	var ps = clampf(zoom * 0.0007, 0.002, 0.02)
	var ps_wall = minf(ps, 0.016)
	for k in labels:
		var l = labels[k]
		if is_instance_valid(l):
			l.pixel_size = ps_wall if l.has_meta("maxw") else ps
			if l.has_meta("maxw"):
				var tw = maxf(1.0, l.get_aabb().size.x)
				if tw > l.get_meta("maxw"): l.pixel_size = ps_wall * l.get_meta("maxw") / tw
				l.position.y = float(l.get_meta("hb")) + maxf(0.12, l.get_aabb().size.y / 2.0)

func _sync_one(e: Dictionary, staff: bool, gdt: float, seen: Dictionary, focus: Vector3, zoom: float) -> void:
	var id: int = e.id
	seen[id] = true
	var p: CharPuppet = puppets.get(id)
	if p != null and not staff and (e.get("healed") == true) != p.healed_look:
		# healed: back to a plain patient (no symptoms), as 45.x mkPat(p.healed)
		var pos = p.position; var ry = p.rotation.y
		p.queue_free(); puppets.erase(id)
		p = _make_puppet(e, staff); puppets[id] = p
		p.position = pos; p.rotation.y = ry
	if p == null:
		p = _make_puppet(e, staff)
		puppets[id] = p
	var d = Vector2(float(e.x) - focus.x, float(e.y) - focus.z).length()
	var vis = d < zoom * 1.6 * _tall or audit_all
	p.visible = vis
	p.lod_every = 1 if (d < zoom * 0.7 or audit_all) else (2 if vis else 8)
	p.sync(sim, e, gdt, self)

func _sync_labels() -> void:
	pass

# ---------- room machine animation (port of r3d animRooms) ----------
var room_k = {}       # room id -> target k this frame (from patients in treatment)
var room_kk = {}      # smoothed
var anim_t = 0.0
func set_room_k(rid, k: float, direct: bool) -> void:
	if rid == null: return
	room_k[rid] = {"k": k, "d": direct}

var emotes = []
func _emote(pos: Vector3, txt: String) -> void:
	var key = {"💀": "x_skull", "💚": "x_heart_green"}.get(txt, "x_sparkle")
	var l = Sprite3D.new()
	l.texture = load("res://assets/icons/%s.png" % key)
	l.pixel_size = 0.005
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.shaded = false; l.no_depth_test = true
	l.position = pos + Vector3(0, 2.0, 0)
	add_child(l)
	emotes.append({"n": l, "t": 0.0})


func _tick_emotes(gdt: float) -> void:
	for i in range(emotes.size() - 1, -1, -1):
		var m = emotes[i]
		if not is_instance_valid(m.n):
			emotes.remove_at(i); continue
		m.t += gdt
		m.n.position.y += gdt * 0.5
		m.n.modulate.a = clampf(2.0 - m.t, 0.0, 1.0)
		if m.t > 2.0:
			m.n.queue_free(); emotes.remove_at(i)

func on_died(id) -> void:
	if not puppets.has(id): return
	var body: Node3D = puppets[id]
	_emote(body.position, "💀")
	for k in puppets:
		if k == id: continue
		var q = puppets[k]
		if q.position.distance_to(body.position) < 4.5:
			q.shock_t = 1.6
			q.shock_at = body.position

func on_healed(id) -> void:
	if puppets.has(id): _emote(puppets[id].position, "💚")

func machine_of(rid, keys: Array):
	if wb == null or not wb.items_nodes.has(rid): return null
	for it in wb.items_nodes[rid]:
		if str(it.t.get("k", "")) in keys: return it
	return null

# 0.9.7: pump / inflate staging: patient right beside the machine (sideways to it), doctor on the other side facing
# the patient and the panel. View-only; cached per machine node.
var _stage := {}
func machine_stage(rid, keys: Array):
	var m = machine_of(rid, keys)
	if m == null: return null
	var kid = m.piv.get_instance_id()
	if _stage.has(kid): return _stage[kid]
	var T: Transform3D = m.piv.global_transform
	var c = T * Vector3.ZERO
	var r0 = sim.roomAt(int(floor(c.x)), int(floor(c.z)))
	var ok = func(v: Vector3) -> bool:
		var tx = int(floor(v.x)); var tz = int(floor(v.z))
		if not sim.walk(tx, tz) or sim.roomAt(tx, tz) != r0: return false
		var it = item_at_tile(tx, tz)
		return it == null or it.get("soft") or is_same(it, m.t)
	var res = null
	# prefer the patient on the camera-near side (bigger x+z) so the treatment reads from the default camera
	var sides = [1.0, -1.0]
	var sx = T.basis.x
	if sx.x + sx.z < 0: sides = [-1.0, 1.0]
	for sg in sides:
		var pp = T * Vector3(.62 * sg, 0, .22)
		if not ok.call(pp): continue
		var dd = T * Vector3(-.58 * sg, 0, .58)
		if not ok.call(dd): dd = T * Vector3(-.62 * sg, 0, .3)
		if not ok.call(dd): dd = T * Vector3(-.3 * sg, 0, .8)
		if not ok.call(dd): dd = T * Vector3(.3 * sg, 0, .95)
		res = {"pat": Vector3(pp.x, 0, pp.z), "doc": Vector3(dd.x, 0, dd.z), "c": Vector3(c.x, 0, c.z), "panel": T * Vector3(-.1 * sg, 1.12, .36), "T": T}
		break
	if res == null:
		var pp2 = T * Vector3(0, 0, .7); var dd2 = T * Vector3(.75, 0, .7)
		res = {"pat": Vector3(pp2.x, 0, pp2.z), "doc": Vector3(dd2.x, 0, dd2.z), "c": Vector3(c.x, 0, c.z), "panel": T * Vector3(.25, 1.05, .32), "T": T}
	_stage[kid] = res
	return res

func _anim_rooms(gdt: float) -> void:
	if wb == null: return
	anim_t += gdt
	for rid in wb.parts:
		var P = wb.parts[rid]
		if P.is_empty(): continue
		var a = room_k.get(rid)
		var k = a.k if a else 0.0
		var kk = k if (a and a.d) else lerpf(room_kk.get(rid, 0.0), k, minf(1.0, gdt * 4.0))
		room_kk[rid] = kk
		var act = a != null
		var now = anim_t * 1000.0
		for name in P:
			for mi in P[name]:
				var base: Transform3D = mi.get_meta("base_xf")
				match name:
					"slide":
						mi.global_transform = Transform3D(base.basis, base.origin - base.basis.z.normalized() * CharPuppet.SLIDE * kk)
					"glow", "uv", "xglow":
						var m = _own_mat(mi)
						if m:
							var e = .4 + ((.6 + .6 * sin(now / 120.0)) if act else 0.0)
							if name == "uv": e = 1.6 if act else .3
							if name == "xglow": e = (.8 + .4 * sin(now / 90.0)) if act else .2
							m.emission_energy_multiplier = e
					"needle":
						mi.global_transform = base * Transform3D(Basis(Vector3(0, 0, 1), sin(now / 200.0) * .9 if act else 0.0), Vector3.ZERO)
					"spark":
						mi.visible = (not act) or randf() < .6
					"podglass":
						var m2 = _own_mat(mi)
						if m2: m2.albedo_color.a = .25 + (.35 * absf(sin(now / 300.0)) if act else 0.0)
					"fish":
						mi.global_transform = Transform3D(base.basis, base.origin + base.basis.x.normalized() * sin(now / 900.0 + mi.get_index() * 2) * .12)
	room_k.clear()

func _own_mat(mi: MeshInstance3D) -> StandardMaterial3D:
	if mi.has_meta("own_mat"): return mi.get_meta("own_mat")
	var m = mi.mesh.surface_get_material(0)
	if m == null: return null
	var d: StandardMaterial3D = m.duplicate()
	mi.set_surface_override_material(0, d)
	mi.set_meta("own_mat", d)
	return d

func puppet_at_screen(screen_pos: Vector2, max_px := 40.0):
	if cam == null: return null
	var best = null
	var bd = max_px
	for id in puppets:
		var p: CharPuppet = puppets[id]
		if not p.visible: continue
		var sp = cam.unproject_position(p.global_position + Vector3(0, 0.9, 0))
		var dd = sp.distance_to(screen_pos)
		if dd < bd:
			bd = dd; best = id
	return best
func _flat(parent: Node3D, rc: Rect2, m: Material, y: float) -> void:
	var mi = MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = rc.size
	mi.mesh = pm; mi.material_override = m; mi.position = Vector3(rc.position.x + rc.size.x / 2.0, y, rc.position.y + rc.size.y / 2.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)

