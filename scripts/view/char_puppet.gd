# Character puppet: follows a sim entity (position/yaw owned by the sim body model), picks animations from sim state.
# AnimationPlayer (cheaper than AnimationTree) with manual advance in GAME time; far/offscreen LOD advances less often.
class_name CharPuppet
extends Node3D

static var _lib: AnimationLibrary
const WALK_SPEED := 0.975   # m/s of Walk_Loop at scale 1 (1.3 m per 1.333 s)
const SEAT_T := {"sit": 1.2, "wc": .8, "lie": 2.6}

var model: Node3D
var ap: AnimationPlayer
var skel: Skeleton3D
var cur = ""
var cur_speed = 1.0
var eid = -1
var is_staff = false
var kind = ""
var acc = 0.0
var lod_every = 1
var frame_i = 0
var props = {}
var lie_t = 0.0
var react_t = -1.0
var last_state = ""
var head_idx = -1
var hip_idx = -1

static func lib() -> AnimationLibrary:
	if _lib == null:
		var src: Node = load("res://assets/anim/UAL1_Standard.glb").instantiate()
		var a: AnimationPlayer = src.find_child("AnimationPlayer", true, false)
		_lib = a.get_animation_library("").duplicate(true)
		for n in _lib.get_animation_list():
			var an = _lib.get_animation(n)
			if n.ends_with("Loop") or n in ["Idle", "Walk", "Walk_Formal", "Idle_Talking", "Sitting_Idle", "Sitting_Talking", "Jog_Fwd", "Dance", "Push", "Crouch_Idle", "Driving"]:
				an.loop_mode = Animation.LOOP_LINEAR
			# strip root translation so the sim owns position (no double motion)
			for ti in range(an.get_track_count() - 1, -1, -1):
				var path = str(an.track_get_path(ti))
				if an.track_get_type(ti) == Animation.TYPE_POSITION_3D and (path.ends_with(":root")):
					an.remove_track(ti)
		src.free()
	return _lib

func setup(glb: String, tint = null, scale_k := 1.0) -> void:
	model = load(glb).instantiate()
	add_child(model)
	model.scale = Vector3.ONE * scale_k
	skel = model.find_child("Skeleton3D", true, false)
	ap = model.find_child("AnimationPlayer", true, false)
	if ap == null:
		ap = AnimationPlayer.new()
		model.add_child(ap)
	ap.root_node = ap.get_path_to(model)
	if ap.has_animation_library(""): ap.remove_animation_library("")
	ap.add_animation_library("", lib())
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ap.playback_default_blend_time = 0.25
	if skel:
		head_idx = skel.find_bone("Head")
		hip_idx = skel.find_bone("pelvis")
		if hip_idx >= 0: pelvis_h = skel.get_bone_global_rest(hip_idx).origin.y * scale_k
		thigh_l = skel.find_bone("thigh_l"); thigh_r = skel.find_bone("thigh_r")
		for c in skel.get_children():
			if c is MeshInstance3D:
				c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if (tint != null or cloth_tex != null) and str(c.name).to_lower().contains("cloth"):
					for si in c.mesh.get_surface_count():
						var mat = c.mesh.surface_get_material(si)
						if mat is StandardMaterial3D:
							var d: StandardMaterial3D = mat.duplicate()
							if tint != null: d.albedo_color = tint
							if cloth_tex != null: d.albedo_texture = cloth_tex
							c.set_surface_override_material(si, d)
	# glTF export left the skin at metallic=1 -> almost black diffuse ("smoked skin"); make it a normal dielectric
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var m = mi.get_surface_override_material(si)
			if m == null: m = mi.mesh.surface_get_material(si)
			if m is StandardMaterial3D and m.metallic > 0.5:
				var d: StandardMaterial3D = m.duplicate()
				d.metallic = 0.0; d.roughness = 0.8; d.metallic_specular = 0.28
				skin_mats.append(d)
				mi.set_surface_override_material(si, d)
	# shoes are painted onto the foot geometry of every skinned single-surface mesh (body AND clothes: the UBC
	# outfits model the feet inside the trousers mesh, which used to get the shirt tint) -> skin_shoe.gdshader
	if model.find_child("*Shoes*", true, false) == null:
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			if mi.skin == null or mi.mesh == null or mi.mesh.get_surface_count() != 1: continue
			var m = mi.get_surface_override_material(0)
			if m == null: m = mi.mesh.surface_get_material(0)
			if not m is StandardMaterial3D: continue
			var bm = _shoe_mesh(glb + ":" + str(mi.name), mi)
			if bm == null: continue
			mi.mesh = bm
			var sm = ShaderMaterial.new()
			sm.shader = SKIN_SHADER
			shoe_sms.append([sm, m])
			mi.set_surface_override_material(0, sm)
	_sync_body()
	play("Idle_Loop")

const SKIN_SHADER = preload("res://shaders/skin_shoe.gdshader")
var shoe_sms = []   # [ShaderMaterial, StandardMaterial3D proxy holding texture/tone/emission]
static var _shoe_meshes = {}
const FOOT_BONES := ["foot_l", "foot_r", "ball_l", "ball_r", "ball_leaf_l", "ball_leaf_r"]

# bake the shoe mask into vertex COLOR (r = shoe, g = sole, b = welt stripe) and puff the foot out a few mm so it reads as a shoe
static func _shoe_mesh(key: String, mi: MeshInstance3D) -> ArrayMesh:
	if _shoe_meshes.has(key): return _shoe_meshes[key]
	var src: ArrayMesh = mi.mesh
	var a = src.surface_get_arrays(0)
	var V: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var N: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var Bn = a[Mesh.ARRAY_BONES]
	var W = a[Mesh.ARRAY_WEIGHTS]
	if Bn == null or W == null or V.size() == 0:
		_shoe_meshes[key] = null; return null
	var per: int = Bn.size() / V.size()
	var foot = {}
	var calf = {}
	for i in mi.skin.get_bind_count():
		var nm = str(mi.skin.get_bind_name(i))
		if nm in FOOT_BONES: foot[i] = true
		if nm.begins_with("calf"): calf[i] = true
	var C = PackedColorArray(); C.resize(V.size())
	var V2 = V.duplicate()
	var mx = 0.0
	for vi in V.size():
		var wf = 0.0
		var wc = 0.0
		for j in per:
			var b = int(Bn[vi * per + j]); var w = float(W[vi * per + j])
			if foot.has(b): wf += w
			elif calf.has(b): wc += w
		var y = V[vi].y
		var mk = clampf((wf - 0.2) / 0.3, 0.0, 1.0)
		if y < 0.125 and (wf + wc) > 0.5: mk = maxf(mk, clampf((0.125 - y) / 0.02, 0.0, 1.0))   # ankle collar
		var sole = clampf((0.032 - y) / 0.012, 0.0, 1.0) * mk
		var welt = clampf(1.0 - absf(y - 0.042) / 0.008, 0.0, 1.0) * mk
		C[vi] = Color(mk, sole, welt, 1.0)
		mx = maxf(mx, mk)
		if mk > 0.0 and N.size() == V.size():
			var n = N[vi]
			n.y = maxf(n.y, -0.2) if y < 0.02 else n.y
			V2[vi] = V[vi] + n * 0.009 * mk
	if mx <= 0.0:
		_shoe_meshes[key] = null; return null
	a[Mesh.ARRAY_VERTEX] = V2
	a[Mesh.ARRAY_COLOR] = C
	for ci in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		a[ci] = null
	var am = ArrayMesh.new()
	for bi in src.get_blend_shape_count(): am.add_blend_shape(src.get_blend_shape_name(bi))
	am.blend_shape_mode = src.blend_shape_mode
	var bsa = src.surface_get_blend_shape_arrays(0)
	var flags = src.surface_get_format(0) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, bsa, {}, flags)
	if am.get_surface_count() == 0:
		_shoe_meshes[key] = null; return null
	_shoe_meshes[key] = am
	return am

func _sync_body() -> void:
	for pr in shoe_sms:
		var sm: ShaderMaterial = pr[0]
		var px: StandardMaterial3D = pr[1]
		sm.set_shader_parameter("tex", px.albedo_texture)
		sm.set_shader_parameter("tone", Vector3(px.albedo_color.r, px.albedo_color.g, px.albedo_color.b))
		sm.set_shader_parameter("has_nrm", px.normal_enabled and px.normal_texture != null)
		if px.normal_texture: sm.set_shader_parameter("nrm", px.normal_texture)
		var e = px.emission * px.emission_energy_multiplier if px.emission_enabled else Color.BLACK
		sm.set_shader_parameter("emis", Vector3(e.r, e.g, e.b))

var skin_mats = []
var healed_look = false
var badge: Node3D
# multipliers on the UBC tan skin texture (>1 = lighter): fair, light, light-olive, tan, brown, dark
const SKIN_TONES := [Color(1.45, 1.32, 1.2), Color(1.35, 1.2, 1.08), Color(1.22, 1.12, 0.98), Color(1.08, 1.0, 0.92), Color(0.82, 0.7, 0.6), Color(0.58, 0.47, 0.4), Color(1.4, 1.25, 1.15)]
static var _pat_tex = {}
const PAT_TINT := {"spotty": Color(1.0, 0.7, 0.7), "pixel": Color(0.85, 0.7, 1.0), "zebra": Color(0.75, 0.75, 0.75), "soapsneeze": Color(0.9, 0.97, 1.0)}

# per-person look: skin tone, shoes, and visible disease symptoms (view only)
var dis_k = ""
var cue_vs = null
var rot_saved := {}
var shape := Vector3.ONE   # per-person build (pelvis x/z scale)
var stoop := 0.0
var head_k := 1.0
var cloth_tex: Texture2D
var cue := {}   # DisCue state (0.9.6)
func set_look(tone: Color, shoe: Color, dis: String) -> void:
	dis_k = dis
	for m in skin_mats:
		m.albedo_color = tone
	if dis != "":
		var pt = _pattern_tex(dis, skin_mats[0].albedo_texture if skin_mats.size() > 0 else null)
		for m in skin_mats:
			if pt: m.albedo_texture = pt
			elif dis in PAT_TINT: m.albedo_color = tone * PAT_TINT[dis]
			match dis:
				"glowskin":
					m.emission_enabled = true; m.emission = Color(0.75, 1.0, 0.35); m.emission_energy_multiplier = 0.55
					m.albedo_color = Color(0.9, 1.0, 0.75)
				"bluescreen": m.albedo_color = Color(0.45, 0.62, 1.0)
				"lowbattery": m.albedo_color = tone.darkened(0.25) * Color(0.85, 0.9, 1.0)
				"grumpliver", "lazyheart": m.albedo_color = tone * Color(1.0, 0.95, 0.7)
				"fizzyblood", "drumheart", "lovesickheart": m.albedo_color = tone * Color(1.0, 0.86, 0.86)
	_sync_body()
	_shoes(shoe)
	if dis == "tail": _tail()
	if dis != "": DisCue.build(self, dis)

func _shoes(col: Color) -> void:
	var sole = Color(0.93, 0.92, 0.88) if col.v < 0.75 else Color(0.25, 0.24, 0.23)
	var lace = col.lerp(Color.WHITE, 0.55) if col.v < 0.75 else Color(0.55, 0.6, 0.68)
	for pr in shoe_sms:
		pr[0].set_shader_parameter("shoe", col)
		pr[0].set_shader_parameter("sole", sole)
		pr[0].set_shader_parameter("lace", lace)

func _attach_rest(nm: String, node: Node3D, bone: String, xf: Transform3D) -> void:
	if props.has(nm): return
	var ba = BoneAttachment3D.new()
	ba.bone_name = bone
	skel.add_child(ba)
	node.transform = xf
	ba.add_child(node)
	props[nm] = ba

func _tail() -> void:
	if skel == null: return
	var n = Node3D.new()
	var m = Geo.mat(Color(0.55, 0.38, 0.24), 0.8)
	for i in 5:
		var c = CylinderMesh.new(); c.top_radius = 0.035 - i * 0.004; c.bottom_radius = 0.04 - i * 0.004; c.height = 0.14; c.radial_segments = 8
		var mi = Geo.mi(n, c, m, Vector3(0, -0.02 - i * 0.07, -0.12 - i * 0.05), 0.0, false)
		mi.rotation.x = -0.6 - i * 0.15
	var P = skel.get_bone_global_rest(skel.find_bone("pelvis"))
	_attach_rest("tail", n, "pelvis", P.affine_inverse() * Transform3D(Basis(), P.origin))
	tail_node = n
var tail_node: Node3D

# skin pattern for skin diseases (spots / pixels / stripes), drawn once into a copy of the skin texture
func _pattern_tex(dis: String, base: Texture2D) -> Texture2D:
	if not dis in ["spotty", "pixel", "zebra", "soapsneeze"] or base == null: return null
	if _pat_tex.has(dis): return _pat_tex[dis]
	var img: Image = base.get_image()
	if img == null: return null
	if img.is_compressed(): img.decompress()
	if img.is_compressed(): return null   # no CPU decoder for this VRAM format in the export template -> tint fallback
	img.convert(Image.FORMAT_RGBA8)
	img.resize(512, 512, Image.INTERPOLATE_BILINEAR)
	var rng = RandomNumberGenerator.new(); rng.seed = hash(dis)
	match dis:
		"spotty":
			for i in 420:
				var cx = rng.randi_range(0, 511); var cy = rng.randi_range(0, 511); var r = rng.randi_range(4, 8)
				var c = Color(0.85, 0.08, 0.1)
				img.fill_rect(Rect2i(cx - r, cy - r / 2, r * 2, r), c)
				img.fill_rect(Rect2i(cx - r / 2, cy - r, r, r * 2), c)
		"pixel":
			var pal = [Color(0.55, 0.2, 0.85), Color(0.1, 0.75, 0.55), Color(0.95, 0.4, 0.7), Color(0.2, 0.45, 0.95)]
			for i in 700:
				var cx = rng.randi_range(0, 31) * 16; var cy = rng.randi_range(0, 31) * 16
				img.fill_rect(Rect2i(cx, cy, 14, 14), pal[i % pal.size()])
		"zebra":
			for y in range(0, 512, 26):
				img.fill_rect(Rect2i(0, y, 512, 11), Color(0.1, 0.09, 0.09))
		"soapsneeze":
			for i in 260:
				var cx = rng.randi_range(0, 511); var cy = rng.randi_range(0, 511)
				img.fill_rect(Rect2i(cx - 3, cy - 3, 7, 7), Color(0.75, 0.9, 1.0))
	var t = ImageTexture.create_from_image(img)
	_pat_tex[dis] = t
	return t

func anim_name(n: String) -> String:
	if ap.has_animation(n): return n
	var alt = n.replace("_Loop", "")
	if ap.has_animation(alt): return alt
	return "Idle_Loop" if ap.has_animation("Idle_Loop") else "Idle"

func play(n: String, spd := 1.0, blend := 0.25) -> void:
	n = anim_name(n)
	cur_speed = spd
	if n == cur: return
	cur = n
	ap.play(n, blend, 1.0)

func head_world() -> Vector3:
	if skel and head_idx >= 0:
		return skel.global_transform * skel.get_bone_global_pose(head_idx).origin
	return global_position + Vector3(0, 1.7, 0)

func attach_prop(name: String, node: Node3D, bone := "Head", offset := Vector3.ZERO, rot := Vector3.ZERO) -> void:
	if props.has(name) or skel == null: return
	var ba = BoneAttachment3D.new()
	ba.bone_name = bone
	skel.add_child(ba)
	node.position = offset
	node.rotation = rot
	ba.add_child(node)
	props[name] = ba

# ---------- pose layer (port of r3d.js poseOf + procFx/v43Give/mach46/hose semantics) ----------
const SLIDE := 0.5
const MATT_H := {"bed": 0.61, "scanner": 0.64, "autopsy": 0.9, "elchair": 0.5}
var lie_k = 0.0
var head_scale = 1.0
var pill: Node3D
var shock_t = 0.0
var sep_off = Vector3.ZERO
const CHAIRS := ["chair_plain", "chair_office", "elchair", "chair", "sofa", "armchair"]
var loose_off = Vector3.ZERO
var seated = false
var greet_at = null
var shock_at = Vector3.ZERO
var ticket: Node3D
var mask: Node3D
func _mask() -> Node3D:
	if mask == null:
		mask = Node3D.new()
		var g = Geo.mat(Color("#5fae9a"), .8)
		Geo.box(mask, Vector3(.15, .07, .03), g, Vector3(0, .025, .1), .01)     # face mask
		Geo.box(mask, Vector3(.2, .06, .21), g, Vector3(0, .19, -.01), .025)           # surgical cap
		attach_prop("mask", mask, "Head", Vector3.ZERO)
		mask.visible = false
	return mask
func _ticket() -> Node3D:
	if ticket == null:
		ticket = Node3D.new()
		Geo.box(ticket, Vector3(.08, .005, .11), Geo.mat(Color("#fff7d6"), .8), Vector3.ZERO, .0)
		Geo.box(ticket, Vector3(.05, .006, .02), Geo.mat(Color("#2f7fd0"), .8), Vector3(0, 0, .03), .0)
		attach_prop("ticket", ticket, "hand_r", Vector3(0, .07, .04), Vector3(0, 0, PI / 2))
		ticket.visible = false
	return ticket
var clip_l: Node3D
var clip_r: Node3D
var clip_w = 0.0
func _clipboard(left: bool) -> Node3D:
	var c = clip_l if left else clip_r
	if c == null:
		c = Node3D.new()
		Geo.box(c, Vector3(.2, .012, .27), Geo.mat(Color("#8a5a2b"), .7), Vector3.ZERO, .0)
		Geo.box(c, Vector3(.17, .006, .22), Geo.mat(Color("#fafafa"), .8), Vector3(0, .009, -.01), .0)
		Geo.box(c, Vector3(.07, .02, .03), Geo.mat(Color("#b0b0b0"), .4, .6), Vector3(0, .012, .12), .0)
		attach_prop("clip_l" if left else "clip_r", c, "hand_l" if left else "hand_r", Vector3(0, .06, .06), Vector3(0.3, 0, PI / 2 * (1 if left else -1)))
		c.visible = false
		if left: clip_l = c
		else: clip_r = c
	return c
var hose: MeshInstance3D
# root offset in front of the seat tile centre so the pelvis lands ~0.10 m in front of the backrest face.
# Measured (harness/measure.gd): backrest face z -0.14 (chair/bench), -0.18 (office), -0.10 (sofa, elchair);
# UAL Sitting_Idle puts the pelvis 0.33 m behind the root.
const SIT_F := {"bench": .29, "chair": .29, "sofa": .33, "wc": .36, "elchair": .33, "chair_office": .25, "stool": .19}
const STAND_F := {"bench": .72, "chair": .72, "sofa": .78, "wc": .7, "elchair": .78, "chair_office": .7, "stool": .66}
const SEAT_H := {"sofa": .52, "bench": .46, "wc": .44, "elchair": .50, "chair": .50, "chair_office": .50, "stool": .5}
var _vs_ref = null
var _vs_from = Vector3.ZERO
var _vs_via = null
var _seat_w = 0.0
var _seat_h = 0.5
var _gy = 0.0
var thigh_l = -1
var thigh_r = -1
var lab_sit = false
static var _bed_sides = {}

# a body standing on a solid item tile (sofa / desk after getting up, or a path that ends on the item): move to the
# closest free floor tile in the same room (prefer where we came from)
func _nearest_free(sim, view, pos: Vector3, prefer) -> Vector3:
	var r0 = sim.roomAt(int(floor(pos.x)), int(floor(pos.z)))
	var best = pos
	var bd = 1e9
	var cx = int(floor(pos.x)); var cz = int(floor(pos.z))
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var x = cx + dx; var z = cz + dz
			if not sim.walk(x, z): continue
			var it = view.item_at_tile(x, z)
			if it != null and not it.get("soft") and str(it.k) != "plant": continue
			if it != null and str(it.k) in CHAIRS: continue
			var c = Vector3(x + .5, 0, z + .5)
			# closest point of the tile to pos (stay near the item edge, not tile centre)
			var q = Vector3(clampf(pos.x, x + .3, x + .7), 0, clampf(pos.z, z + .3, z + .7))
			var d = q.distance_to(pos) + (0.0 if sim.roomAt(x, z) == r0 else 1.5)
			if prefer != null: d += 0.35 * q.distance_to(prefer)
			if d < bd: bd = d; best = q
	return best
var _vs_side = Vector3.ZERO
var _vs_side_ref = null

# chairs pulled up to a desk/counter: the tile in front is solid, so get in from the side (free floor, same room)
func _side_approach(sim, view, A: Vector3, f: Vector3) -> Vector3:
	var fx = int(floor(A.x + f.x * .9)); var fz = int(floor(A.z + f.z * .9))
	var it = view.item_at_tile(fx, fz) if view else null
	if sim.walk(fx, fz) and (it == null or it.get("soft")): return Vector3.ZERO
	var r0 = sim.roomAt(int(floor(A.x)), int(floor(A.z)))
	for sd in [Vector3(-f.z, 0, f.x), Vector3(f.z, 0, -f.x)]:
		var sx = int(floor(A.x + sd.x * .9)); var sz = int(floor(A.z + sd.z * .9))
		var it2 = view.item_at_tile(sx, sz) if view else null
		if sim.walk(sx, sz) and sim.roomAt(sx, sz) == r0 and (it2 == null or it2.get("soft")): return sd
	return Vector3.ZERO

static func dir_yaw(d) -> float:
	match int(d if d != null else 1):
		0: return PI / 2
		1: return 0.0
		2: return -PI / 2
		_: return PI

func _clip_len(n: String) -> float:
	var a = ap.get_animation(anim_name(n))
	return a.length if a else 1.0

static func _polyline(pts: Array, t: float) -> Vector3:
	var tot = 0.0
	for i in range(1, pts.size()): tot += pts[i - 1].distance_to(pts[i])
	if tot < 1e-4: return pts[pts.size() - 1]
	var u = t * tot
	for i in range(1, pts.size()):
		var d = pts[i - 1].distance_to(pts[i])
		if u <= d or i == pts.size() - 1: return pts[i - 1].lerp(pts[i], clampf(u / maxf(d, 1e-4), 0, 1))
		u -= d
	return pts[pts.size() - 1]

func _seat_kind(sim, e: Dictionary, sp, pose: String) -> String:
	if pose == "wc" or sp.get("seat") == "wc": return "wc"
	if sp.get("bench") or sp.get("seat") == "bench": return "bench"
	var r = sim.room_by_id(e.get("room"))
	if r and r.get("it"):
		for t in r.it:
			if int(t.x) == int(sp.x) and int(t.y) == int(sp.y):
				var kk = str(t.get("k", ""))
				if "elchair" in kk: return "elchair"
				if "sofa" in kk: return "sofa"
				if "chair_office" in kk: return "chair_office"
				if "chair" in kk: return "chair"
	return str(sp.get("seat")) if sp.get("seat") else "chair"

# which side of the bed has two free tiles to stand on (45.x v43BedSide)
func _bed_side(sim, b) -> int:
	var t = b.t
	var key = str(t.get_instance_id() if t is Object else hash(t))
	if _bed_sides.has(key): return _bed_sides[key]
	var r = null
	for rr in sim.S.rooms:
		if rr.get("it") and rr.it.has(t): r = rr; break
	var sd = 0
	if r:
		var fp = t.get("fp") if t.get("fp") else sim.fpOf(t.k)
		var I = sim.inner(r)
		var az = int(fp[1]) >= int(fp[0])
		var blk = {}
		for q in r.it:
			if q != t:
				for tt in sim.tilesOf(q.x, q.y, q.get("fp") if q.get("fp") else sim.fpOf(q.k)): blk[str(tt[0]) + "," + str(tt[1])] = true
		var ok = func(sg: int) -> bool:
			var ts = [[t.x - 1 if sg < 0 else t.x + fp[0], t.y], [t.x - 1 if sg < 0 else t.x + fp[0], t.y + fp[1] - 1]] if az else [[t.x, t.y - 1 if sg < 0 else t.y + fp[1]], [t.x + fp[0] - 1, t.y - 1 if sg < 0 else t.y + fp[1]]]
			for q in ts:
				if not (q[0] >= I.x and q[1] >= I.y and q[0] < I.x + I.w and q[1] < I.y + I.h) or blk.has(str(q[0]) + "," + str(q[1])): return false
			return true
		var cx = I.x + I.w / 2.0
		var cy = I.y + I.h / 2.0
		var pref = (1 if cx >= t.x + fp[0] / 2.0 else -1) if az else (1 if cy >= t.y + fp[1] / 2.0 else -1)
		sd = pref if ok.call(pref) else (-pref if ok.call(-pref) else 0)
	_bed_sides[key] = sd
	return sd

func _bed_pose(sim, b, sp, L: float, cur: Vector3) -> Dictionary:
	# 0.9.4: walk to the bed side (near the middle), sit on the edge with the back to the mattress, then swing the legs in
	# while lying back: yaw turns onto the bed's long axis, legs straighten (leg bones -> rest) in sync with the tilt.
	var t = b.t
	var fp = t.get("fp") if t.get("fp") else sim.fpOf(t.k)
	var az = int(fp[1]) >= int(fp[0])
	var sd = _bed_side(sim, b)
	var C = Vector3(t.x + fp[0] / 2.0, 0, t.y + fp[1] / 2.0)
	var sv = Vector3(sd, 0, 0) if az else Vector3(0, 0, sd)
	var Y0 = b.piv.rotation.y
	var foot = Vector3(sin(Y0), 0, cos(Y0))          # +Z of the bed = foot end (headboard / scanner ring at -Z)
	var P0 = Vector3(float(sp.x) + .5, 0, float(sp.y) + .5)
	var Ss = C + sv * .92 + foot * .2
	var E = C + sv * .42 + foot * .2
	var yaw_out = atan2(sv.x, sv.z)
	var o = {"pos": cur, "yaw": yaw_out, "anim": "Sitting_Idle", "spd": 1.0, "lie": 0.0, "w": 0.0}
	if L < .4:
		var a = L / .4
		var K = P0.lerp(Ss, .5) + sv * .25
		o.pos = _polyline([P0, K, Ss], ease01(a))
		var dv = o.pos - position
		o.anim = "Walk"; o.spd = 1.1
		if a > .9:
			o.anim = "Idle"
			o.yaw = lerp_angle(rotation.y, yaw_out, .35)
		elif Vector2(dv.x, dv.z).length() > .002: o.yaw = atan2(dv.x, dv.z)
	elif L < .6:
		var k = ease01((L - .4) / .2)
		o.pos = Ss.lerp(E, k); o.anim = "Sitting_Enter" if _vs_ref and _vs_ref.ph == "down" else "Sitting_Exit"
		o.spd = 1.4; o.w = k
	else:
		var u = ease01((L - .6) / .4)
		o.pos = E.lerp(C, u)
		o.yaw = lerp_angle(yaw_out, Y0, u)
		o.lie = u; o.w = 1.0
		o.anim = "Sitting_Idle"; o.spd = 0.5
	return o
var pelvis_h = 0.95
var lie_direct = false
var _last_free = null
# 0.9.7: disease icon sits just above its own head and comes and goes (shown ~2.6 s of every 7 s), never parked in the air
# 0.9.7: some staff idles stand with feet far apart -> bring each foot to ~11 cm from the body centre line
func _narrow_legs() -> void:
	DisCue._undo(self)
	var sk = skel
	var tl = sk.find_bone("thigh_l"); var tr = sk.find_bone("thigh_r")
	var fl = sk.find_bone("foot_l"); var fr = sk.find_bone("foot_r")
	if tl < 0 or tr < 0 or fl < 0 or fr < 0: return
	var fwd: Vector3 = (sk.global_basis.inverse() * global_basis * Vector3(0, 0, 1)).normalized()
	var side: Vector3 = Vector3.UP.cross(fwd).normalized()
	var mid = (sk.get_bone_global_pose(tl).origin + sk.get_bone_global_pose(tr).origin) * 0.5
	for pr in [[tl, fl], [tr, fr]]:
		var hip = sk.get_bone_global_pose(pr[0]).origin
		var before = (sk.get_bone_global_pose(pr[1]).origin - mid).dot(side)
		var L = maxf(0.3, hip.distance_to(sk.get_bone_global_pose(pr[1]).origin))
		var want = 0.11 * signf(before)
		if absf(before) <= 0.13: continue
		var ang = clampf(atan((absf(before) - absf(want)) / L), 0.0, 0.3)
		DisCue._rot(self, sk.get_bone_name(pr[0]), fwd, ang)
		var after = (sk.get_bone_global_pose(pr[1]).origin - mid).dot(side)
		if absf(after) > absf(before): DisCue._rot(self, sk.get_bone_name(pr[0]), fwd, -2.0 * ang)

static var _dbg_anim = OS.get_environment("DBGANIM") != ""
func badge_tick(alive: bool) -> void:
	if badge == null: return
	var ph = fmod(Time.get_ticks_msec() / 1000.0 + float(eid % 97) * 1.37, 7.0)
	var a = clampf(ph / 0.4, 0.0, 1.0) * (1.0 - clampf((ph - 2.6) / 0.4, 0.0, 1.0))
	badge.visible = alive and a > 0.01
	badge.modulate.a = a
	badge.global_position = head_world() + Vector3(0, 0.22 + 0.1 * head_scale * head_k, 0)

func is_fixed() -> bool:
	return (seated or lab_sit) and (_seat_w > 0.3 or lie_k > 0.05)
# view-only walk (lab nurse goes round the counter): sim position stays at the staff spot
var vw_pos = null
var vw_pts = []
var vw_goal = ""
var vw_planned_pv = false
var vw_home = Vector3.ZERO
var vw_arrived = false
var vw_arr_t = 0.0
var vw_home_pts = []

func _tile_pts(sim, from: Vector3, gx: int, gy: int) -> Array:
	var pth = sim.path(int(floor(from.x)), int(floor(from.z)), gx, gy)
	if pth == null: return []
	var o = []
	for q in pth: o.append(Vector3(float(q.x) + .5, 0, float(q.y) + .5))
	return o

func _los(sim, a: Vector3, b: Vector3) -> bool:
	var n = int(ceil(a.distance_to(b) / 0.2))
	for i in range(1, n):
		var q = a.lerp(b, float(i) / n)
		for o in [Vector3.ZERO, Vector3(.28, 0, 0), Vector3(-.28, 0, 0), Vector3(0, 0, .28), Vector3(0, 0, -.28)]:
			if not sim.walk(int(floor(q.x + o.x)), int(floor(q.z + o.z))): return false
	return true

func _smooth(sim, pts: Array) -> Array:
	if pts.size() < 3: return pts
	var o = [pts[0]]
	var i = 0
	while i < pts.size() - 1:
		var j = pts.size() - 1
		while j > i + 1 and not _los(sim, pts[i], pts[j]): j -= 1
		o.append(pts[j]); i = j
	return o

# lab: stand at the patient's right side (arm side), planned from the room's patient spot
func _vw_go_patient(sim, home: Vector3, r, pv = null, view = null) -> void:
	vw_goal = "pat"; vw_arrived = false; vw_arr_t = 0.0
	vw_planned_pv = pv != null
	var sp = sim.spotPatient(r)
	var py = dir_yaw(sp.get("dir"))
	var P = Vector3(float(sp.x) + .5, 0, float(sp.y) + .5)
	if pv != null:
		# the patient's real place (the room can have been re-laid out while they walked in)
		py = pv.rotation.y
		P = Vector3(pv.position.x, 0, pv.position.z) - Vector3(sin(py), 0, cos(py)) * (float(SIT_F.stool) * pv._seat_w)
	var f = Vector3(sin(py), 0, cos(py))
	var right = Vector3(-cos(py), 0, sin(py))       # character's right = local -X
	var best = []
	if pv != null:
		# 0.9.5: stand next to the patient's draw hand (wherever the arm rests), on a free tile, not inside the patient
		var hw: Vector3 = pv.hand_world("hand_r")
		var room0 = sim.roomAt(int(floor(home.x)), int(floor(home.z)))
		var cands = []
		for i in 8:
			var an = TAU * i / 8.0
			var c = Vector3(hw.x + cos(an) * 0.6, 0, hw.z + sin(an) * 0.6)
			var cx = int(floor(c.x)); var cz = int(floor(c.z))
			if not sim.walk(cx, cz) or sim.roomAt(cx, cz) != room0: continue
			var itc = view.item_at_tile(cx, cz) if view else null
			if itc != null and not itc.get("soft"): continue
			if Vector2(c.x - P.x, c.z - P.z).length() < 0.5: continue
			# keep clear of the walls / furniture neighbours so the body does not clip: tile centre pull
			cands.append([home.distance_to(c), c])
		cands.sort_custom(func(a, b): return a[0] < b[0])
		for cd in cands:
			var c2: Vector3 = cd[1]
			var gx2 = int(floor(c2.x)); var gz2 = int(floor(c2.z))
			var pts2 = _tile_pts(sim, home, gx2, gz2)
			if pts2.is_empty() and (gx2 != int(floor(home.x)) or gz2 != int(floor(home.z))): continue
			pts2.push_front(home); pts2.append(c2)
			pts2 = _smooth(sim, pts2); pts2.pop_front()
			best = pts2
			break
	# the patient's draw arm is the right one: the nurse works from that side
	var sides = [1.0, -1.0]
	for sgn in sides:
		if not best.is_empty(): break
		var goal = P + right * (0.56 * sgn) + f * 0.12
		var gx = int(floor(goal.x)); var gz = int(floor(goal.z))
		if not sim.walk(gx, gz) or sim.roomAt(gx, gz) != sim.roomAt(int(floor(home.x)), int(floor(home.z))): continue
		var pts = _tile_pts(sim, home, gx, gz)
		if pts.is_empty() and (gx != int(floor(home.x)) or gz != int(floor(home.z))): continue
		pts.push_front(home)
		pts.append(goal)
		pts = _smooth(sim, pts)
		pts.pop_front()
		best = pts
		break
	if best.is_empty():
		var d = P - home
		best = [home + Vector3(d.x, 0, d.z).normalized() * .3]
	vw_pts = best
	if vw_pos == null: vw_pos = home; vw_home = home
	vw_home_pts = best.duplicate(); vw_home_pts.reverse(); vw_home_pts.append(vw_home)

var vw_face = Vector3.INF
# 0.9.5: scanner operator stands beside the gantry panel (view-only walk from the staff spot)
func _vw_go_scanner(sim, view, home: Vector3, r) -> bool:
	var m = view.machine_of(r.id, ["scanner"]) if view else null
	if m == null: return false
	var piv: Node3D = m.piv
	var T: Transform3D = piv.global_transform
	var room_rect = sim.roomAt(int(floor(home.x)), int(floor(home.z)))
	for sgn in [1.0, -1.0]:
		var g: Vector3 = T * Vector3(.95 * sgn, 0, -.3)
		var gx = int(floor(g.x)); var gz = int(floor(g.z))
		if not sim.walk(gx, gz) or sim.roomAt(gx, gz) != room_rect: continue
		var it = view.item_at_tile(gx, gz)
		if it != null and not it.get("soft"): continue
		var pts = _tile_pts(sim, home, gx, gz)
		if pts.is_empty() and (gx != int(floor(home.x)) or gz != int(floor(home.z))): continue
		pts.push_front(home); pts.append(Vector3(g.x, 0, g.z))
		pts = _smooth(sim, pts); pts.pop_front()
		vw_goal = "pat"; vw_arrived = false; vw_arr_t = 0.0; vw_planned_pv = true
		vw_pts = pts
		vw_face = T * Vector3(0, 0, -.1)
		if vw_pos == null: vw_pos = home; vw_home = home
		vw_home_pts = pts.duplicate(); vw_home_pts.reverse(); vw_home_pts.append(vw_home)
		return true
	return false

func _vw_go_home(_sim, home: Vector3) -> void:
	vw_goal = "home"; vw_arrived = false
	vw_pts = vw_home_pts.duplicate() if not vw_home_pts.is_empty() else [home]
	if vw_pts.size() > 0: vw_pts[vw_pts.size() - 1] = home

func _vw_step(gdt: float) -> Vector3:
	var before: Vector3 = vw_pos
	var left = 1.6 * gdt
	while left > 0.0 and not vw_pts.is_empty():
		var nx: Vector3 = vw_pts[0]
		var d = vw_pos.distance_to(nx)
		if d <= left:
			vw_pos = nx; left -= d; vw_pts.pop_front()
		else:
			vw_pos = vw_pos + (nx - vw_pos) / d * left; left = 0.0
	if vw_pts.is_empty(): vw_arrived = true
	return vw_pos - before
var _lie_h = 0.61
const LEG_BONES := ["thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r"]
var _leg_idx = []

# lying: legs go straight (blend leg bones to the rest pose) in sync with the tilt -> no "legs in the air"
func _straighten_legs(u: float) -> void:
	if skel == null: return
	if _leg_idx.is_empty():
		for n in LEG_BONES: _leg_idx.append(skel.find_bone(n))
	for i in _leg_idx:
		if i < 0: continue
		var q: Quaternion = skel.get_bone_pose_rotation(i)
		skel.set_bone_pose_rotation(i, q.slerp(skel.get_bone_rest(i).basis.get_rotation_quaternion(), clampf(u, 0, 1)))

# lying: put the pelvis on the mattress centre (measured from the current pose, any clip / model scale)
func _place_lying() -> void:
	if skel == null or hip_idx < 0: return
	var n: Node = skel
	var chain = Transform3D()
	while n != model and n != null:
		chain = (n as Node3D).transform * chain if n is Node3D else chain
		n = n.get_parent()
	var pl: Vector3 = chain * skel.get_bone_global_pose(hip_idx).origin
	var R = Basis(Vector3(1, 0, 0), -lie_k * PI / 2.0) * Basis.from_scale(model.scale)
	var d_sit = Basis.from_scale(model.scale) * pl + Vector3(0, _gy, 0)
	var d_lie = Vector3(0, _lie_h + 0.085, 0)
	model.position = d_sit.lerp(d_lie, lie_k) - R * pl
var death_hold = false
var slide = 0.0
var sat0 = -1.0

static func ease01(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func procQ(p) -> float:
	if p == null or p.state != "treat": return -1.0
	var T: float = p.get("tT") if p.get("tT") else maxf(0.001, float(p.get("t", 1.0)))
	return clampf(1.0 - float(p.t) / T, 0.0, 1.0)

func _pill() -> Node3D:
	if pill == null:
		pill = Node3D.new()
		Geo.box(pill, Vector3(.09, .06, .05), Geo.mat(Color.WHITE, .6), Vector3.ZERO, .005)
		Geo.box(pill, Vector3(.092, .018, .052), Geo.mat(Color("#e23a3a"), .6), Vector3(0, .02, 0), .002)
		attach_prop("pill", pill, "hand_r", Vector3(0, .08, .03))
		pill.visible = false
	return pill

# returns {node, t, r} of the bed/scanner item the seat spot belongs to
func _bed_of(view, sp):
	if sp == null or sp.get("at") == null or view == null or view.wb == null: return null
	for rid in view.wb.items_nodes:
		for it in view.wb.items_nodes[rid]:
			var t = it.t
			if int(t.x) == int(sp.at.x) and int(t.y) == int(sp.at.y) and str(t.get("k", "")) in ["bed", "scanner", "autopsy"]:
				return it
	return null

func sync(sim, e: Dictionary, gdt: float, view) -> void:
	var tgt = Vector3(float(e.x) + 0.5, 0.0, float(e.y) + 0.5)
	var yaw: float = e.get("yaw", 0.0)
	var anim = "Idle"
	var spd = 1.0
	var st: String = e.state
	var v: float = e.get("v", 0.0)
	var vs = e.get("vs")
	cue_vs = vs
	var moving = e.get("path") != null and e.path.size() > 0 and v > 0.03
	var want_lie = 0.0
	var lie_h = 0.61
	var hs_target = 1.0
	var show_pill = false
	var show_ticket = false
	var want_mask = false
	var hose_to = null
	var show_tube = false
	reach_r = Vector3.INF; reach_world = Vector3.INF; reach_w = 0.0; reach_left = false; clip_w = 0.0
	seated = vs != null
	lab_sit = false
	shock_t = maxf(0.0, shock_t - gdt)
	if st == "dead":
		anim = "Death01"
		if e.get("body") == "carry": tgt.y = 0.95
		if cur == anim_name("Death01") and ap.current_animation_position >= ap.current_animation_length - 0.08: spd = 0.0
	elif vs:
		var pose: String = vs.pose
		var T: float = SEAT_T.get(pose, 0.9)
		var k: float = clampf(float(vs.t) / T, 0.0, 1.0)
		var sp = vs.get("sp")
		if not is_same(vs, _vs_ref):
			_vs_ref = vs; _vs_from = position - sep_off; _vs_via = null
		if pose == "lie":
			var b = _bed_of(view, sp)
			var lk = 1.0 if vs.ph == "sat" else (k if vs.ph == "down" else 1.0 - k)
			var bk = str(b.t.get("k")) if b else ""
			if b and (bk.begins_with("bed") or bk == "scanner") and _bed_side(sim, b) != 0:
				# v43 bed: walk to the bed side, sit on the edge (back to the bed), swing in and lie down; reverse to get up
				var r = _bed_pose(sim, b, sp, lk, tgt)
				tgt = r.pos; yaw = r.yaw; anim = r.anim; spd = r.spd; want_lie = r.lie; lie_h = MATT_H.get(bk, .61)
				_seat_w = r.w; _seat_h = lie_h - .05
				lie_direct = true
				if bk == "scanner":
					# CT table slides into the gantry with the patient (procFx sc46), only while fully lying
					var fwd = Vector3(sin(b.piv.rotation.y), 0, cos(b.piv.rotation.y))
					if st == "treat" and vs.ph == "sat":
						if sat0 < 0: sat0 = 0.0
						sat0 += gdt
						var kk = ease01(sat0 / 0.9) * ease01((float(e.t) - SEAT_T.lie) / 0.9)
						tgt -= fwd * SLIDE * kk
						view.set_room_k(e.get("room"), kk, true)
					else:
						sat0 = -1.0
						view.set_room_k(e.get("room"), 0.0, true)
			elif b:
				lie_h = MATT_H.get(bk, 0.61)
				var bc = b.piv.position
				var byaw = b.piv.rotation.y
				var fwd = Vector3(sin(byaw), 0, cos(byaw))
				if bk == "scanner": bc += fwd * 0.1
				tgt = tgt.lerp(bc, ease01(lk * 1.6))
				yaw = lerp_angle(yaw, byaw, ease01(lk * 1.4))
				# CT table slides into the gantry with the patient (procFx sc46)
				if bk == "scanner" and st == "treat" and vs.ph == "sat":
					if sat0 < 0: sat0 = 0.0
					sat0 += gdt
					var kk = ease01(sat0 / 0.9) * ease01((float(e.t) - SEAT_T.lie) / 0.9)
					tgt -= fwd * SLIDE * kk
					view.set_room_k(e.get("room"), kk, true)
				else: sat0 = -1.0
				# 45.x: straight lie-back onto the table from standing (never "sitting on air" beside it)
				want_lie = ease01(lk * 1.4)
				anim = "Idle"; spd = 0.35
				_seat_w = 0.0
			else:
				_seat_w = 0.0
				want_lie = ease01(lk * 1.4); anim = "Idle"; spd = 0.35
		else:
			# v43 natural sitting: walk to a point in front of the seat, turn, lower onto the cushion (and back)
			var sk = _seat_kind(sim, e, sp, pose)
			var syaw = dir_yaw(sp.get("dir") if sp.get("dir") != null else e.get("dir"))
			var f = Vector3(sin(syaw), 0, cos(syaw))
			var A = Vector3(float(sp.x) + .5, 0, float(sp.y) + .5)
			var M = A + f * float(SIT_F.get(sk, .2))
			var SD = float(STAND_F.get(sk, .65))
			var Sx = A + f * SD
			if not is_same(_vs_side_ref, vs):
				_vs_side_ref = vs; _vs_side = _side_approach(sim, view, A, f)
			if _vs_side != Vector3.ZERO: Sx = A + _vs_side * (.5 if (_vs_from - A).length() < .8 else .62) + f * .06
			_seat_h = float(SEAT_H.get(sk, .5))
			if vs.ph == "down":
				if _vs_via == null and _vs_side != Vector3.ZERO: _vs_via = Vector3.INF
				if _vs_via == null:
					var along = (_vs_from - A).dot(f)
					_vs_via = (A + Vector3(-f.z, 0, f.x) * 1.05 + f * SD) if along < SD * .45 and (_vs_from - Sx).length() > .3 else Vector3.INF
				if k < .42:
					var a2 = ease01(k / .42)
					var pts = [_vs_from, Sx] if _vs_via == Vector3.INF else [_vs_from, _vs_via, Sx]
					tgt = _polyline(pts, a2)
					var dv = tgt - position
					var walking = (tgt - Sx).length() > .05
					anim = "Walk" if walking else "Idle"
					spd = 0.8
					yaw = atan2(dv.x, dv.z) if walking and Vector2(dv.x, dv.z).length() > .002 else lerp_angle(rotation.y, syaw, minf(1.0, gdt * 10.0))
					_seat_w = 0.0
				else:
					var b2 = ease01((k - .42) / .58)
					tgt = Sx.lerp(M, b2); yaw = syaw
					anim = "Sitting_Enter"; spd = _clip_len("Sitting_Enter") / maxf(.2, T * .58)
					_seat_w = b2
			elif vs.ph == "up":
				yaw = syaw
				anim = "Sitting_Exit"; spd = _clip_len("Sitting_Exit") / maxf(.2, T * .8)
				tgt = M if k < .3 else M.lerp(Sx, ease01((k - .3) / .45))
				_seat_w = 1.0 - ease01(k / .75)
			else:
				tgt = M; yaw = syaw; _seat_w = 1.0
				anim = "Sitting_Idle"
				if st == "treat" or (is_staff and st == "work" and _patient_in_room(sim, e)): anim = "Sitting_Talking"
	elif e.get("oa") or e.get("wash"):
		anim = "Interact"
	elif moving:
		anim = "Walk_Formal" if kind == "doctor" else "Walk"
		if v > 1.9: anim = "Jog_Fwd"
		spd = clampf(v / (WALK_SPEED if anim != "Jog_Fwd" else 2.6), 0.35, 1.8)
	elif e.get("turning"):
		anim = "Walk"; spd = 0.5
	elif is_staff and e.get("mop"):
		anim = "Push"
	elif is_staff and e.type == "handyman" and st == "do":
		anim = "Fixing_Kneeling"
	elif is_staff and e.type == "orderly" and st == "pick":
		anim = "Crouch_Idle"
	elif is_staff and st == "work":
		var r = sim.room_by_id(e.get("room"))
		var p = null
		if r:
			for q in sim.S.pats:
				if q.get("room") == r.id and q.state == "treat": p = q; break
			if p == null and r.type == "lab":
				for q in sim.S.pats:
					if q.get("room") == r.id and q.state == "enter":
						if vw_goal != "pat": _vw_go_patient(sim, tgt, r)
						break
		if p:
			var qq = procQ(p)
			# face the patient (lying patients: their body centre on the bed/table)
			var pv = view.puppets.get(p.id) if view else null
			var pp = pv.position if pv else Vector3(float(p.x) + .5, 0, float(p.y) + .5)
			var dpp = pp - tgt
			if Vector2(dpp.x, dpp.z).length() > 0.15: yaw = lerp_angle(rotation.y, atan2(dpp.x, dpp.z), minf(1.0, gdt * 5.0 + 0.05))
			match r.type:
				"pharmacy":
					anim = "Interact" if qq > .4 and qq < .86 else "Idle_Talking"
					show_pill = qq > .3 and qq < .8
				"surgery", "transplant":
					# operating: hands busy over the table the whole time, short pause at the end
					anim = "Interact" if qq > .08 and qq < .92 else "Idle_Talking"
					spd = 0.8
					want_mask = true
				"inflate", "pump":
					# 0.9.7: doctor walks to the machine's other side, faces the patient across it and works the panel
					anim = "Idle"
					spd = 0.7
					var stg2 = view.machine_stage(r.id, ["pumpmachine", "inflator"]) if view else null
					if stg2 and qq < .9:
						if vw_goal != "pat":
							if vw_pos == null: vw_pos = tgt; vw_home = tgt
							var pts = _tile_pts(sim, vw_pos, int(floor(stg2.doc.x)), int(floor(stg2.doc.z)))
							pts.push_front(vw_pos); pts.append(stg2.doc)
							pts = _smooth(sim, pts); pts.pop_front()
							vw_pts = pts; vw_goal = "pat"; vw_arrived = false; vw_arr_t = 0.0
							vw_home_pts = pts.duplicate(); vw_home_pts.reverse(); vw_home_pts.append(vw_home)
						if vw_goal == "pat" and vw_pts.is_empty():
							vw_arrived = true; vw_arr_t += gdt
							# face between the patient and the camera, so the face and the panel hand read from the default view
							var dfp = stg2.pat - vw_pos
							var ty2 = lerp_angle(atan2(dfp.x, dfp.z), PI / 4.0, 0.45)
							yaw = lerp_angle(rotation.y, ty2, minf(1.0, gdt * 6.0 + 0.05))
							if Vector3(stg2.panel.x, 0, stg2.panel.z).distance_to(vw_pos) < 1.0:
								reach_world = stg2.panel
								var lp = (Basis(Vector3.UP, yaw).inverse() * (stg2.panel - vw_pos))
								reach_left = lp.x > 0.0
								reach_w = ease01(vw_arr_t / .4) * ease01((qq - .16) / .08) * (1.0 - ease01((qq - .78) / .06))
							clip_w = ease01(vw_arr_t / .4)
					elif vw_goal == "pat": _vw_go_home(sim, tgt)
				"diag", "xray", "cardio", "electro", "reboot", "genetics":
					# explain -> operate the console/machine -> report back
					anim = "Interact" if qq > .18 and qq < .82 else "Idle_Talking"
					spd = 0.7
					if r.type == "diag" and view:
						# 0.9.5: the operator walks over to the gantry panel while the patient is being scanned
						if qq < .86:
							if vw_goal != "pat": _vw_go_scanner(sim, view, vw_pos if vw_pos != null else tgt, r)
							if vw_goal == "pat" and vw_arrived and vw_face != Vector3.INF:
								var df = vw_face - (vw_pos if vw_pos != null else tgt)
								yaw = lerp_angle(rotation.y, atan2(df.x, df.z), minf(1.0, gdt * 6.0 + 0.05))
						elif vw_goal == "pat": _vw_go_home(sim, tgt)
				"lab":
					# 0.9.4: the nurse walks round the counter to the patient's right side, draws blood there, walks back
					anim = "Idle_Talking"
					spd = 0.6
					if pv and qq < .84:
						if vw_goal != "pat" or (not vw_planned_pv and vw_arrived): _vw_go_patient(sim, vw_pos if vw_pos != null else tgt, r, pv, view)
						if vw_goal == "pat" and vw_arrived:
							vw_arr_t += gdt
							var hw = pv.hand_world("hand_r")
							var dh = hw - tgt
							if vw_pos != null: dh = hw - vw_pos
							yaw = lerp_angle(rotation.y, atan2(dh.x, dh.z), minf(1.0, gdt * 6.0 + 0.05))
							anim = "Interact"
							show_tube = vw_arr_t > .5
							reach_world = hw + Vector3(0, .06, 0)
							reach_w = ease01(vw_arr_t / .5) * ease01((qq - .14) / .08) * (1.0 - ease01((qq - .74) / .08))
					elif vw_goal == "pat": _vw_go_home(sim, tgt)
				"ward", "icu", "derma":
					anim = "Interact" if fmod(qq * 3.0, 1.0) < .35 else "Idle"
				_:
					anim = "Idle_Talking" if e.type == "doctor" else "Interact"
	elif st == "treat" and not is_staff:
		var r2 = sim.room_by_id(e.get("room"))
		var q2 = procQ(e)
		anim = "Idle_Talking"
		if r2:
			view.set_room_k(r2.id, ease01(q2 / .12) * (1.0 - ease01((q2 - .88) / .12)), false)
			match r2.type:
				"pharmacy":
					if q2 > .6 and q2 < .92: anim = "Interact"
					show_pill = q2 >= .8
				"pump", "inflate":
					# 0.9.7: step up beside the machine, side-on to it; hose on the head; head visibly swells / shrinks
					anim = "Idle"
					var mach = view.machine_of(r2.id, ["pumpmachine", "inflator"])
					var stg = view.machine_stage(r2.id, ["pumpmachine", "inflator"])
					if stg:
						var spot = tgt
						var kin = clampf(q2 / .12, 0, 1) if q2 < .5 else clampf((1.0 - q2) / .1, 0, 1)
						var dv = stg.pat - spot
						tgt = spot.lerp(stg.pat, ease01(kin))
						if kin > 0.0 and kin < 1.0 and dv.length() > 0.05:
							anim = "Walk"; spd = 0.75
							yaw = atan2(dv.x, dv.z) if q2 < .5 else atan2(-dv.x, -dv.z)
						else:
							# half-turned to the camera so face, hose and swelling head read from the default view
							var dc = stg.c - stg.pat
							var ty = lerp_angle(atan2(dc.x, dc.z), PI / 4.0, 0.72)
							yaw = lerp_angle(rotation.y, ty, minf(1.0, gdt * 6.0 + 0.05))
					var on = q2 > .16 and q2 < .86
					if mach and on: hose_to = mach
					var u = clampf((q2 - .18) / .62, 0, 1)
					if r2.type == "inflate" or not str(e.get("dis")) in ["balloonhead", "cloudhead"]:
						hs_target = 1.0 + .9 * sin(u * PI) + .06 * sin(u * 40.0) * float(on)
					else: hs_target = lerpf(1.0, 1.0 / maxf(1.0, head_k), ease01(u)) + .05 * sin(u * 40.0) * float(on)
				"xray", "reboot":
					var mk = "xray" if r2.type == "xray" else "rebootpod"
					var m2 = view.machine_of(r2.id, [mk])
					if m2:
						var c = m2.piv.position
						var spot = tgt
						var kin = clampf(q2 / .15, 0, 1) if q2 < .5 else clampf((1.0 - q2) / .15, 0, 1)
						tgt = spot.lerp(c, kin)
						var dv = (c - spot)
						if kin > 0.0 and kin < 1.0 and dv.length() > 0.05:
							# real steps in/out: walk clip at matching speed, facing the travel direction
							anim = "Walk"; spd = 0.75
							yaw = atan2(dv.x, dv.z) if q2 < .5 else atan2(-dv.x, -dv.z)
						else:
							anim = "Idle"
							if kin >= 1.0: yaw = atan2(-dv.x, -dv.z) if dv.length() > 0.05 else m2.piv.rotation.y
				"electro":
					anim = "Hit_Chest" if fmod(float(e.t), 1.2) < 0.33 else "Idle"
				"psych":
					anim = "Idle_Talking"
				"lab":
					# blood draw: sit on the stool, lay the right arm on the counter, nurse takes blood from the vein
					lab_sit = true; _seat_h = .5
					var fl = Vector3(sin(yaw), 0, cos(yaw))
					if q2 < .12:
						_seat_w = ease01(q2 / .12); anim = "Sitting_Enter"; spd = 1.3
					elif q2 > .9:
						_seat_w = 1.0 - ease01((q2 - .9) / .1); anim = "Sitting_Exit"; spd = 1.3
					else:
						_seat_w = 1.0; anim = "Sitting_Idle"
						reach_r = Vector3(-0.1, 0.92, 0.62); reach_w = ease01((q2 - .14) / .08) * (1.0 - ease01((q2 - .82) / .06))
					tgt += fl * (float(SIT_F.stool) * _seat_w)
				"reception":
					# ticket hand-off: reach over the counter at q .45-.7, ticket in hand afterwards
					if q2 > .45 and q2 < .7: anim = "Interact"
					show_ticket = q2 >= .6
	elif st == "leave" and e.get("react") and float(e.react.get("t", 9)) < 2.75:
		# REACT46: look (1.0) -> dance (to 2.3) -> settle
		var rt = float(e.react.t)
		anim = "Idle_Talking" if rt < 1.0 else ("Dance" if rt < 2.3 else "Idle")
	elif shock_t > 0.0 and not moving:
		anim = "Hit_Head" if shock_t > 1.15 else "Idle"
		var d = shock_at - tgt
		if d.length() > 0.2: yaw = atan2(d.x, d.z)
	elif is_staff and st == "work" and _patient_in_room(sim, e):
		anim = "Idle_Talking"
	elif is_staff and not moving and kind in ["nurse", "doctor", "receptionist"]:
		# friendly staff: turn to a patient passing close by and say hello
		if frame_i % 12 == 0:
			greet_at = null
			for q in sim.S.pats:
				if q.state == "dead" or q.get("vs"): continue
				var dq = Vector2(float(q.x) - float(e.x), float(q.y) - float(e.y))
				if dq.length() < 1.4: greet_at = Vector3(float(q.x) + .5, 0, float(q.y) + .5); break
		if greet_at != null:
			anim = "Idle_Talking"
			var dg = greet_at - tgt
			if dg.length() > 0.2: yaw = lerp_angle(rotation.y, atan2(dg.x, dg.z), minf(1.0, gdt * 6.0))
	# lie blend: rotate the whole model around X onto the mattress (no lie clip in UAL1); pelvis over bed centre
	if lie_direct: lie_k = want_lie
	else: lie_k = want_lie if absf(want_lie - lie_k) < 0.02 else lerpf(lie_k, want_lie, minf(1.0, gdt * 6.0 + 0.0001))
	lie_direct = false
	if not seated and not lab_sit: _seat_w = 0.0
	# seat height (45.x legs()): lift/lower the body so the hips land on the real cushion height
	var gy_want = 0.0
	if _seat_w > 0.001 and thigh_l >= 0:
		var ty = (skel.get_bone_global_pose(thigh_l).origin.y + skel.get_bone_global_pose(thigh_r).origin.y) * 0.5 * model.scale.y
		gy_want = clampf((_seat_h + .08 - ty) * _seat_w, -.3, .3)
	_gy = lerpf(_gy, gy_want, minf(1.0, gdt * 12.0 + 0.0001))
	_lie_h = lie_h
	if lie_k > 0.001:
		model.rotation.x = -lie_k * PI / 2.0
		_place_lying()
	else:
		model.rotation.x = 0.0
		model.position = Vector3(0, _gy, 0)
	if dis_k == "rubberknee" and moving and lie_k < .05: model.position.y += absf(sin(Time.get_ticks_msec() * .009)) * .1
	if dis_k == "jellyspine" and lie_k < .05: model.rotation.z = sin(Time.get_ticks_msec() * .006) * .07
	if badge: badge_tick(st != "dead")
	# 0.9.7: people standing in the reception line face the desk
	if not is_staff and vs == null and st == "queue" and not moving and e.get("wsp") != null and e.get("dir") != null:
		yaw = lerp_angle(rotation.y, dir_yaw(e.dir), minf(1.0, gdt * 6.0 + 0.05))
	# view-side: a walking body stops at the edge of solid furniture instead of walking through it
	if vs == null and lie_k < 0.05 and vw_pos == null and view and st != "dead":
		var tx = int(floor(tgt.x)); var tz = int(floor(tgt.z))
		var it = view.item_at_tile(tx, tz)
		var bad = it != null and not it.get("soft") and str(it.k) != "plant"
		# 0.9.8.1: soft chairs are walkable in the sim (a seat spot sits on them) but nobody may stand or walk inside one
		if it != null and str(it.k) in CHAIRS and not seated: bad = true
		if bad:
			tgt = _nearest_free(sim, view, tgt, _last_free)
			if anim == "Walk" or anim == "Walk_Formal": anim = "Idle"
		else:
			_last_free = tgt
	if vw_pos != null:
		if vw_goal == "pat" and not (is_staff and (st == "work" or st == "idle")): _vw_go_home(sim, tgt)
		if vw_goal == "home" and vw_pts.is_empty(): vw_pts = [tgt]
		var mv = _vw_step(gdt)
		if mv.length() > 0.0005:
			anim = "Walk"; spd = 0.95
			yaw = lerp_angle(rotation.y, atan2(mv.x, mv.z), minf(1.0, gdt * 10.0 + 0.1))
			reach_w = 0.0; show_tube = false
		elif vw_goal == "home":
			vw_pos = null; vw_goal = ""
		if vw_pos != null: tgt = vw_pos
	# 0.9.7: reception overflow waits outside the entrance as a loose group, not a row on the facade line
	var lw = Vector3.ZERO
	if not is_staff and vs == null and st == "queue" and e.get("wsp") != null and float(e.y) >= float(sim.S.h - 1) - 0.01:
		var hsh = (eid * 2654435761) % 1000
		lw = Vector3((float(hsh % 10) / 9.0 - 0.5) * 0.7, 0, 0.5 + float(hsh / 10 % 10) / 9.0 * 1.6)
	loose_off = loose_off.lerp(lw, minf(1.0, gdt * 1.5))
	tgt += loose_off
	position = tgt
	rotation.y = yaw
	if show_pill or pill: _pill().visible = show_pill
	if show_tube or tube: _tube().visible = show_tube
	if want_mask or mask: _mask().visible = want_mask
	if clip_w > 0.01 or clip_l or clip_r:
		var cl = clip_w > 0.01 and not reach_left
		var cr = clip_w > 0.01 and reach_left
		if cl or clip_l: _clipboard(true).visible = cl
		if cr or clip_r: _clipboard(false).visible = cr
	if show_ticket or ticket: _ticket().visible = show_ticket or (ticket != null and ticket.visible and st != "treat" and st != "dead" and st != "leave" and vs == null)
	if not cue.is_empty():
		spd = DisCue.speed(self, spd, anim.begins_with("Walk"))
		DisCue.tick(self, gdt, anim.begins_with("Walk"))
	if _dbg_anim and is_staff and st == "work" and frame_i % 20 == 0: print("DBGANIM ", e.type, " ", anim, " cur ", cur, " spd ", snappedf(spd, .01), " vw ", vw_goal, " ", vw_pts.size(), " sep ", sep_off)
	play(anim, spd)
	frame_i += 1
	acc += gdt * cur_speed
	if frame_i % lod_every == 0:
		ap.advance(acc)
		acc = 0.0
		if lie_k > 0.001: _straighten_legs(lie_k)
		elif _seat_w > 0.6 and cur == "Sitting_Idle" and reach_w < 0.01: _sit_tweak(ease01((_seat_w - 0.6) / 0.4))
		if not cue.is_empty() or stoop != 0.0 or shape != Vector3.ONE or head_k != 1.0: DisCue.pose(self)
		elif is_staff and not moving and lie_k < 0.01 and cur in [anim_name("Idle"), anim_name("Idle_Talking")]: _narrow_legs()
		if reach_w > 0.01:
			var tw = reach_world if reach_world != Vector3.INF else (global_transform * reach_r if reach_r != Vector3.INF else Vector3.INF)
			if tw != Vector3.INF:
				if reach_left: _reach("upperarm_l", "hand_l", tw, reach_w)
				else: _reach("upperarm_r", "hand_r", tw, reach_w)
		if clip_w > 0.01:
			# the free hand holds a clipboard in front of the chest
			var o = "r" if reach_left else "l"
			var sgn = -1.0 if o == "r" else 1.0
			var cw = global_transform * Vector3(sgn * 0.1, 1.08, 0.3)
			var fwd2 = global_basis * Vector3(0, 0, 1)
			var side2 = global_basis * Vector3(sgn, 0, 0)
			var pole = skel.global_basis.inverse() * (Vector3(0, -1, 0) - fwd2 * 0.4 + side2 * 0.5)
			_ik2("upperarm_" + o, "hand_" + o, skel.global_transform.affine_inverse() * cw, clip_w, pole)
	if lie_k > 0.001: _place_lying()
	# head scale (pump/inflate): applied after the animation pose
	head_scale = lerpf(head_scale, hs_target, minf(1.0, gdt * 4.0 + 0.0001))
	if skel and head_idx >= 0 and absf(head_scale - 1.0) > 0.005:
		var hk2 = head_k * head_scale
		skel.set_bone_pose_scale(head_idx, Vector3(hk2 / shape.x, hk2, hk2 / shape.z))
	_hose(hose_to)

func _hose(mach) -> void:
	if mach == null:
		if hose: hose.visible = false
		return
	if hose == null:
		hose = MeshInstance3D.new()
		hose.mesh = ImmediateMesh.new()
		hose.material_override = Geo.mat(Color("#3a6ea5"), 0.5)
		hose.top_level = true
		add_child(hose)
	hose.visible = true
	var A = mach.piv.global_transform * Vector3(0, 1.15, .4)
	var B = head_world() + Vector3(0, 0.2 * head_scale * head_k, 0)
	var M = A.lerp(B, .5); M.y = maxf(A.y, B.y) + .08
	var im: ImmediateMesh = hose.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var N = 12
	var prev = []
	for i in N + 1:
		var t = float(i) / N
		var p = A.lerp(M, t).lerp(M.lerp(B, t), t)
		var ring = []
		for j in 6:
			var an = TAU * j / 6.0
			ring.append(p + Vector3(cos(an) * .03, sin(an) * .03, 0).rotated(Vector3.UP, 0.0) + Vector3(0, 0, sin(an) * .03))
		if i > 0:
			for j in 6:
				var a0 = prev[j]; var a1 = prev[(j + 1) % 6]; var b0 = ring[j]; var b1 = ring[(j + 1) % 6]
				for q in [a0, b0, a1, a1, b0, b1]: im.surface_add_vertex(q)
		prev = ring
	im.surface_end()

var reach_r = Vector3.INF
var reach_world = Vector3.INF
var reach_w = 0.0
var reach_left = false
var tube: Node3D
func _tube() -> Node3D:
	if tube == null:
		tube = Node3D.new()
		Geo.box(tube, Vector3(.025, .1, .025), Geo.mat(Color("#c81e2a"), .3), Vector3.ZERO, .008)
		Geo.box(tube, Vector3(.03, .025, .03), Geo.mat(Color("#7a2be0"), .5), Vector3(0, .06, 0), .006)
		attach_prop("tube", tube, "hand_r", Vector3(0, .08, .03))
		tube.visible = false
	return tube

func hand_world(b: String) -> Vector3:
	var i = skel.find_bone(b) if skel else -1
	if i < 0: return global_position + Vector3(0, 1.0, 0)
	return skel.global_transform * skel.get_bone_global_pose(i).origin

# two-step aim: upper arm, then forearm, point at a world target (weight w) -> arm reaches out straight
func _reach(upper: String, hand: String, target: Vector3, w: float) -> void:
	if skel == null: return
	var ui = skel.find_bone(upper)
	var li = skel.find_bone(upper.replace("upperarm", "lowerarm"))
	var hi = skel.find_bone(hand)
	if ui < 0 or li < 0 or hi < 0: return
	var T = skel.global_transform.affine_inverse() * target
	_aim(ui, li, T, w)
	_aim(li, hi, T, w)

# two-bone arm IK: hand bone origin to target T (skeleton space), elbow bends towards `pole` (skeleton-space direction)
func _ik2(upper: String, hand: String, T: Vector3, w: float, pole: Vector3) -> void:
	var ui = skel.find_bone(upper)
	var li = skel.find_bone(upper.replace("upperarm", "lowerarm"))
	var hi = skel.find_bone(hand)
	if ui < 0 or li < 0 or hi < 0: return
	var S: Vector3 = skel.get_bone_global_pose(ui).origin
	var E: Vector3 = skel.get_bone_global_pose(li).origin
	var W: Vector3 = skel.get_bone_global_pose(hi).origin
	var L1 = S.distance_to(E); var L2 = E.distance_to(W)
	var dv = T - S
	var d = clampf(dv.length(), absf(L1 - L2) + 0.02, L1 + L2 - 0.01)
	if dv.length() < 1e-4: return
	var a = dv.normalized()
	var a1 = (L1 * L1 - L2 * L2 + d * d) / (2.0 * d)
	var h = sqrt(maxf(L1 * L1 - a1 * a1, 0.0))
	var pp = pole - a * pole.dot(a)
	if pp.length() < 1e-4: return
	var Ep = S + a * a1 + pp.normalized() * h
	var Tt = S + a * d
	_aim(ui, li, Ep, w)
	# the forearm bone now starts at the (moved) elbow: aim at the target
	_aim(li, hi, Tt, w)

# seated, relaxed: hands rest on the thighs, knees closer together (Sitting_Idle hovers the hands and splays the legs)
func _sit_tweak(w: float) -> void:
	if skel == null: return
	var ti_l = skel.find_bone("thigh_l"); var ti_r = skel.find_bone("thigh_r")
	var ca_l = skel.find_bone("calf_l"); var ca_r = skel.find_bone("calf_r")
	var fo_l = skel.find_bone("foot_l"); var fo_r = skel.find_bone("foot_r")
	if ti_l < 0 or ti_r < 0 or ca_l < 0 or ca_r < 0 or fo_l < 0 or fo_r < 0: return
	var hl = skel.get_bone_global_pose(ti_l).origin; var hr = skel.get_bone_global_pose(ti_r).origin
	var lat = (hl - hr); if lat.length() < 1e-4: return
	var hip_w = lat.length(); lat = lat.normalized()
	var C = (hl + hr) * 0.5
	for pair in [[ti_l, ca_l, fo_l, 1.0], [ti_r, ca_r, fo_r, -1.0]]:
		var K: Vector3 = skel.get_bone_global_pose(pair[1]).origin
		var F: Vector3 = skel.get_bone_global_pose(pair[2]).origin
		var off = (K - C).dot(lat) * pair[3]
		var want = hip_w * 0.5 * 1.1
		if off <= want: continue
		var dk = lat * (off - want) * pair[3]
		_aim(pair[0], pair[1], K - dk * w, 1.0)
		var K2: Vector3 = skel.get_bone_global_pose(pair[1]).origin
		_aim(pair[1], pair[2], F + (K2 - K), 1.0)
	# hands on the thighs
	var up = Vector3.UP
	var back_x = skel.global_transform.basis.inverse() * (global_transform.basis * Vector3(0, 0, -1))
	for side in [[ "upperarm_l", "hand_l", ca_l, 1.0], ["upperarm_r", "hand_r", ca_r, -1.0]]:
		var Kn: Vector3 = skel.get_bone_global_pose(side[2]).origin
		var Hp: Vector3 = skel.get_bone_global_pose(side[2] if false else (ti_l if side[3] > 0 else ti_r)).origin
		var tgt = Hp.lerp(Kn, 0.62) + (skel.global_transform.basis.inverse() * Vector3(0, 0.1, 0))
		_ik2(side[0], side[1], tgt, w, lat * side[3] + back_x * 0.6 + (skel.global_transform.basis.inverse() * Vector3(0, -0.4, 0)))

func _aim(bi: int, ci: int, T: Vector3, w: float) -> void:
	var g: Transform3D = skel.get_bone_global_pose(bi)
	var c: Transform3D = skel.get_bone_global_pose(ci)
	var v1 = c.origin - g.origin
	var v2 = T - g.origin
	if v1.length() < 1e-4 or v2.length() < 1e-4: return
	var q = Quaternion.IDENTITY.slerp(Quaternion(v1.normalized(), v2.normalized()), clampf(w, 0, 1))
	rot_global(skel, bi, q)

# 0.9.8.1: apply a skeleton-space rotation to a bone by changing ONLY its local rotation.
# set_bone_global_pose() re-decomposed the (parent-scaled) basis every frame; the error went into the bone's pose SCALE,
# which the animation never rewrites, so arm bones grew without bound (seated patients' arms reached 1e17 m:
# the long "wing" planks seen on Adreno phones). Rotation-only keeps scale untouched and normalised.
static func rot_global(sk: Skeleton3D, bi: int, q: Quaternion) -> void:
	if not q.is_finite(): return
	var par = sk.get_bone_parent(bi)
	var P: Basis = sk.get_bone_global_pose(par).basis.orthonormalized() if par >= 0 else Basis()
	var ql = Quaternion(P.inverse() * Basis(q.normalized()) * P)
	var nr = (ql * sk.get_bone_pose_rotation(bi)).normalized()
	if nr.is_finite(): sk.set_bone_pose_rotation(bi, nr)

func _patient_in_room(sim, s: Dictionary) -> bool:
	var r = sim.room_by_id(s.get("room"))
	return r != null and r.busy != null
