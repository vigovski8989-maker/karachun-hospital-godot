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
		for c in skel.get_children():
			if c is MeshInstance3D:
				c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if tint != null and str(c.name).to_lower().contains("cloth"):
					for si in c.mesh.get_surface_count():
						var mat = c.mesh.surface_get_material(si)
						if mat is StandardMaterial3D:
							var d: StandardMaterial3D = mat.duplicate()
							d.albedo_color = tint
							c.set_surface_override_material(si, d)
	play("Idle_Loop")

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
const MATT_H := {"bed": 0.61, "scanner": 0.64, "autopsy": 0.9, "elchair": 0.5}
var lie_k = 0.0
var head_scale = 1.0
var pill: Node3D
var shock_t = 0.0
var sep_off = Vector3.ZERO
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
var hose: MeshInstance3D
var pelvis_h = 0.95
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
	var moving = e.get("path") != null and e.path.size() > 0 and v > 0.03
	var want_lie = 0.0
	var lie_h = 0.61
	var hs_target = 1.0
	var show_pill = false
	var show_ticket = false
	var want_mask = false
	var hose_to = null
	model.position = Vector3.ZERO
	seated = vs != null
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
		if pose == "lie":
			var b = _bed_of(view, sp)
			var lk = 1.0 if vs.ph == "sat" else (k if vs.ph == "down" else 1.0 - k)
			if b:
				var bk = str(b.t.get("k"))
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
					tgt -= fwd * 0.75 * kk
					view.set_room_k(e.get("room"), kk, true)
				else: sat0 = -1.0
			want_lie = ease01((lk - 0.25) / 0.75)
			anim = "Sitting_Idle" if want_lie < 0.5 else ("Sitting_Enter" if vs.ph == "down" else "Sitting_Exit")
			if want_lie > 0.5: anim = "Idle"; spd = 0.06   # near-still body on the mattress (slow breathing sway only)
		else:
			anim = "Sitting_Idle" if vs.ph == "sat" else ("Sitting_Enter" if vs.ph == "down" else "Sitting_Exit")
			if vs.ph != "sat": spd = 1.3 / T
			if vs.ph == "sat" and (st == "treat" or (is_staff and st == "work" and _patient_in_room(sim, e))): anim = "Sitting_Talking"
			# seated slightly back into the chair (seat frame)
			var bk2 = (0.34 if kind == "receptionist" else 0.12) * (1.0 if vs.ph == "sat" else k if vs.ph == "down" else 1.0 - k)
			tgt += Vector3(sin(yaw), 0, cos(yaw)) * -bk2
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
				"diag", "xray", "cardio", "electro", "reboot", "genetics", "inflate", "pump":
					# explain -> operate the console/machine -> report back
					anim = "Interact" if qq > .18 and qq < .82 else "Idle_Talking"
					spd = 0.7
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
					anim = "Idle"
					var mach = view.machine_of(r2.id, ["pumpmachine", "inflator"])
					if mach: hose_to = mach
					if r2.type == "inflate": hs_target = 1.0 + .35 * sin(minf(1.0, q2 / .7) * PI)
					elif str(e.get("dis")) in ["balloonhead", "cloudhead"]: hs_target = lerpf(1.0, 1.0 / 1.35, minf(1.0, q2 / .8))
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
	lie_k = want_lie if absf(want_lie - lie_k) < 0.02 else lerpf(lie_k, want_lie, minf(1.0, gdt * 6.0 + 0.0001))
	if lie_k > 0.001:
		model.rotation.x = -lie_k * PI / 2.0
		model.position = Vector3(0, lie_k * (lie_h + 0.1), lie_k * pelvis_h * 0.9)
	else:
		model.rotation.x = 0.0
	position = tgt
	rotation.y = yaw
	if show_pill or pill: _pill().visible = show_pill
	if want_mask or mask: _mask().visible = want_mask
	if show_ticket or ticket: _ticket().visible = show_ticket or (ticket != null and ticket.visible and st != "treat" and st != "dead" and st != "leave" and vs == null)
	play(anim, spd)
	frame_i += 1
	acc += gdt * cur_speed
	if frame_i % lod_every == 0:
		ap.advance(acc)
		acc = 0.0
	# head scale (pump/inflate): applied after the animation pose
	head_scale = lerpf(head_scale, hs_target, minf(1.0, gdt * 4.0 + 0.0001))
	if skel and head_idx >= 0 and absf(head_scale - 1.0) > 0.005:
		skel.set_bone_pose_scale(head_idx, Vector3.ONE * head_scale)
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
	var B = head_world() + Vector3(0, 0.17 * head_scale, 0)
	var M = A.lerp(B, .5); M.y = maxf(A.y, B.y) + .35
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

func _patient_in_room(sim, s: Dictionary) -> bool:
	var r = sim.room_by_id(s.get("room"))
	return r != null and r.busy != null
