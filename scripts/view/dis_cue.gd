class_name DisCue
extends RefCounted
# 0.9.6: every disease gets a distinct, readable VIEW-ONLY cue (prop / body change / periodic behaviour / puff).
# Nothing here touches the sim. A healed patient is rebuilt as a plain puppet, so the cue disappears on cure.
# beh: mv = behaviour (see bones()), per = [min,max] seconds between runs, dur = run length, ic = puff icon, at = puff anchor
const BEH := {
	"pixel": {"mv": "scratch", "per": [4, 8], "dur": 1.3, "ic": "pixel", "at": "head"},
	"yawn": {"mv": "yawn", "per": [3.5, 6], "dur": 2.2, "ic": "x_zzz", "at": "mouth"},
	"nosewhistle": {"mv": "none", "per": [1.4, 2.2], "dur": 0.1, "ic": "x_note", "at": "nose", "cont": true},
	"giggles": {"mv": "shake", "per": [2.5, 4.5], "dur": 1.8, "ic": "x_ha", "at": "mouth"},
	"grumpliver": {"mv": "belly", "per": [3, 5.5], "dur": 2.0, "ic": "x_anger", "at": "belly"},
	"squareeyes": {"mv": "grope", "per": [99, 99], "dur": 1, "ic": "x_question", "at": "head", "cont": true, "slow": 0.8},
	"balloonhead": {"mv": "none", "per": [99, 99], "dur": 1, "ic": "", "at": "head"},
	"echo": {"mv": "ear", "per": [3, 5], "dur": 2.0, "ic": "x_speech", "at": "mouth", "echo": true},
	"rubberknee": {"mv": "hop", "per": [2.5, 4], "dur": 0.9, "ic": "", "at": "head"},
	"puffytoes": {"mv": "none", "per": [99, 99], "dur": 1, "ic": "", "at": "head"},
	"selfiesyndrome": {"mv": "selfie", "per": [2.5, 4], "dur": 0.4, "ic": "x_camera", "at": "phone"},
	"blinknose": {"mv": "none", "per": [99, 99], "dur": 1, "ic": "", "at": "nose"},
	"drumheart": {"mv": "chest", "per": [2.5, 4], "dur": 1.6, "ic": "x_drum", "at": "chest", "beat": 7.0},
	"soapsneeze": {"mv": "sneeze", "per": [3, 5.5], "dur": 1.3, "ic": "x_bubbles", "at": "nose", "burst": 4},
	"jellyspine": {"mv": "none", "per": [99, 99], "dur": 1, "ic": "", "at": "head"},
	"lostshadow": {"mv": "none", "per": [99, 99], "dur": 1, "ic": "", "at": "head"},
	"fizzyblood": {"mv": "bend", "per": [3.5, 6], "dur": 1.7, "ic": "x_bubbles", "at": "mouth", "burst": 3},
	"twistedtongue": {"mv": "none", "per": [2.5, 4], "dur": 0.1, "ic": "x_tongue", "at": "mouth"},
	"cloudhead": {"mv": "none", "per": [0.12, 0.2], "dur": 0.1, "ic": "", "at": "head", "cont": true},
	"hiccupclock": {"mv": "hic", "per": [2, 3.5], "dur": 0.5, "ic": "x_clock", "at": "mouth"},
	"glowskin": {"mv": "none", "per": [0.7, 1.3], "dur": 0.1, "ic": "x_sparkle", "at": "chest", "cont": true},
	"spotty": {"mv": "scratch", "per": [3, 6], "dur": 1.4, "ic": "x_dizzy", "at": "head"},
	"zebra": {"mv": "none", "per": [99, 99], "dur": 1, "ic": "", "at": "head"},
	"tail": {"mv": "none", "per": [99, 99], "dur": 1, "ic": "", "at": "head"},
	"flathead": {"mv": "none", "per": [4, 6], "dur": 0.1, "ic": "x_dizzy", "at": "head", "cont": true},
	"deflated": {"mv": "none", "per": [2.5, 4], "dur": 0.1, "ic": "x_gas", "at": "belly", "cont": true, "slump": 0.3},
	"statichair": {"mv": "none", "per": [0.5, 1.1], "dur": 0.1, "ic": "x_spark", "at": "head", "cont": true},
	"lowbattery": {"mv": "yawn", "per": [4, 7], "dur": 2.4, "ic": "x_battery", "at": "head", "slow": 0.75, "slump": 0.28},
	"bluescreen": {"mv": "shake", "per": [3, 5], "dur": 0.7, "ic": "bluescreen", "at": "head"},
	"looping": {"mv": "wave", "per": [1.5, 2.5], "dur": 1.5, "ic": "looping", "at": "head"},
	"lazyheart": {"mv": "chest", "per": [3.5, 6], "dur": 2.4, "ic": "x_zzz", "at": "chest", "slow": 0.7, "slump": 0.18, "beat": 2.2},
	"wanderliver": {"mv": "ear", "per": [4, 6], "dur": 1.6, "ic": "x_suitcase", "at": "head"},
	"chattykidney": {"mv": "talk", "per": [0.9, 1.6], "dur": 1.0, "ic": "x_speech", "at": "mouth", "cont": true},
	"bagpipelungs": {"mv": "chest", "per": [1.1, 1.8], "dur": 1.0, "ic": "x_note", "at": "head", "cont": true, "beat": 3.0},
	"gourmetstomach": {"mv": "bend", "per": [3.5, 6], "dur": 1.8, "ic": "x_oyster", "at": "mouth"},
	"lovesickheart": {"mv": "chest", "per": [1.0, 1.8], "dur": 1.0, "ic": "x_heart", "at": "chest", "cont": true, "beat": 3.2},
	"diarrhea": {"mv": "belly", "per": [2.5, 4.5], "dur": 2.2, "ic": "x_gas", "at": "belly", "waddle": true, "slump": 0.12},
	"sneezykidney": {"mv": "sneeze", "per": [3, 5], "dur": 1.2, "ic": "x_sneeze", "at": "nose", "burst": 3, "hop": true},
}
static var _tex := {}
static var _drop_mesh: Mesh

static func icon(key: String) -> Texture2D:
	if not _tex.has(key):
		var path = "res://assets/icons/%s.png" % key
		_tex[key] = load(path) if ResourceLoader.exists(path) else null
	return _tex[key]

# ---------------------------------------------------------------- build
static func build(p: CharPuppet, dis: String) -> void:
	if not BEH.has(dis) or p.skel == null: return
	var b: Dictionary = BEH[dis]
	p.cue = {"d": dis, "b": b, "t": randf_range(0.5, float(b.per[0])), "u": -1.0, "env": 0.0, "fired": false, "puffs": [], "ph": randf() * 6.28,
		"ct": randf() * 0.5, "echo_n": 0}
	var m = Geo.mat
	match dis:
		"squareeyes":
			var n = Node3D.new()
			var fm = m.call(Color(0.05, 0.05, 0.07), 0.3, 0.3)
			var gl = m.call(Color(0.55, 0.8, 1.0, 0.5), 0.05); gl.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var wh = m.call(Color(0.97, 0.97, 0.97), 0.3)
			for sx in [-1, 1]:
				Geo.sphere(n, 0.03, wh, Vector3(sx * 0.037, 0.0, 0.0))       # bulging eyeballs
				Geo.sphere(n, 0.012, fm, Vector3(sx * 0.037, 0.0, 0.028))
				Geo.box(n, Vector3(0.07, 0.07, 0.01), fm, Vector3(sx * 0.04, 0, 0.05), 0.004)
				Geo.box(n, Vector3(0.054, 0.054, 0.012), gl, Vector3(sx * 0.04, 0, 0.05), 0.004)
			Geo.box(n, Vector3(0.03, 0.012, 0.012), fm, Vector3(0, 0.01, 0.05), 0.004)
			p.attach_prop("c_eyes", n, "Head", Vector3(0, 0.07, 0.07))
			# white cane: grip at the node origin, shaft along -Y (1 m); placed every pose frame by _cane() so the tip sweeps the floor
			var cane = Node3D.new()
			var cm = m.call(Color(0.96, 0.96, 0.94), 0.5)
			Geo.cyl(cane, 0.012, 0.012, 1.0, cm, Vector3(0, -0.5, 0), 8)
			for i in 3: Geo.cyl(cane, 0.0135, 0.0135, 0.09, m.call(Color(0.85, 0.1, 0.1), 0.5), Vector3(0, -0.93 + i * 0.16, 0), 8)
			Geo.cyl(cane, 0.02, 0.02, 0.12, m.call(Color(0.08, 0.08, 0.08), 0.6), Vector3(0, -0.02, 0), 8)
			Geo.sphere(cane, 0.02, m.call(Color(0.15, 0.15, 0.15), 0.6), Vector3(0, -1.0, 0))
			cane.top_level = true
			p.add_child(cane); c_set(p, "cane", cane)
		"blinknose":
			var n = Node3D.new()
			var rm = m.call(Color(1.0, 0.1, 0.08), 0.3); rm.emission_enabled = true; rm.emission = Color(1, 0.1, 0.05); rm.emission_energy_multiplier = 1.5
			Geo.sphere(n, 0.05, rm, Vector3.ZERO)
			p.attach_prop("c_nose", n, "Head", Vector3(0, 0.03, 0.115))
			p.cue.nose_mat = rm
		"cloudhead":
			var n = Node3D.new()
			var cm = m.call(Color(0.42, 0.45, 0.52), 0.9)
			for q in [[0, 0, 0, .13], [-.12, -.02, 0, .09], [.12, -.02, .02, .1], [.04, .05, -.06, .09], [-.05, .03, .07, .08]]:
				Geo.sphere(n, q[3], cm, Vector3(q[0], q[1], q[2]), 0.7)
			p.attach_prop("c_cloud", n, "Head", Vector3(0, 0.38, 0))
		"statichair":
			var n = Node3D.new()
			var hm = m.call(Color(0.95, 0.75, 0.15), 0.6)
			var rng = RandomNumberGenerator.new(); rng.seed = 7
			for i in 11:
				var c = CylinderMesh.new(); c.top_radius = 0.0; c.bottom_radius = 0.024; c.height = 0.26; c.radial_segments = 5
				var a = i * 2.4
				var mi = Geo.mi(n, c, hm, Vector3(cos(a) * 0.05, 0.05, sin(a) * 0.05), 0.0, false)
				mi.rotation = Vector3(sin(a) * 0.7, 0, -cos(a) * 0.7)
			p.attach_prop("c_hair", n, "Head", Vector3(0, 0.13, 0))
		"twistedtongue":
			var n = Node3D.new()
			var tm = m.call(Color(0.95, 0.35, 0.45), 0.5)
			Geo.cyl(n, 0.014, 0.014, 0.1, tm, Vector3(0, 0, 0.05), 8).rotation.x = PI / 2
			var t = TorusMesh.new(); t.inner_radius = 0.012; t.outer_radius = 0.034; t.rings = 12; t.ring_segments = 6
			var knot = Geo.mi(n, t, tm, Vector3(-0.025, 0, 0.115), 0.0, false); knot.rotation.x = PI / 2
			var knot2 = Geo.mi(n, t, tm, Vector3(0.025, 0, 0.115), 0.0, false); knot2.rotation.x = PI / 2
			p.attach_prop("c_tongue", n, "Head", Vector3(0, -0.035, 0.085))
		"selfiesyndrome":
			var n = Node3D.new()
			Geo.box(n, Vector3(0.075, 0.14, 0.012), m.call(Color(0.06, 0.06, 0.08), 0.3), Vector3.ZERO, 0.008)
			var sm = m.call(Color(0.4, 0.75, 1.0), 0.2); sm.emission_enabled = true; sm.emission = Color(0.3, 0.6, 1.0)
			Geo.box(n, Vector3(0.062, 0.12, 0.004), sm, Vector3(0, 0, 0.007), 0.003)
			p.attach_prop("c_phone", n, "hand_r", Vector3(0, 0.1, 0.03), Vector3(0, 0, 0))
		"wanderliver":
			var hat = Node3D.new()
			var sm = m.call(Color(0.93, 0.8, 0.4), 0.8)
			Geo.cyl(hat, 0.2, 0.2, 0.012, sm, Vector3.ZERO, 20)
			Geo.cyl(hat, 0.1, 0.105, 0.09, sm, Vector3(0, 0.05, 0), 18)
			Geo.cyl(hat, 0.106, 0.106, 0.02, m.call(Color(0.85, 0.2, 0.2), 0.6), Vector3(0, 0.035, 0), 18)
			p.attach_prop("c_hat", hat, "Head", Vector3(0, 0.15, 0))
			var bag = Node3D.new()
			var bm = m.call(Color(0.52, 0.32, 0.18), 0.7)
			Geo.box(bag, Vector3(0.32, 0.24, 0.1), bm, Vector3.ZERO, 0.02)
			Geo.box(bag, Vector3(0.1, 0.035, 0.03), m.call(Color(0.15, 0.1, 0.07), 0.6), Vector3(0, 0.14, 0), 0.01)
			Geo.box(bag, Vector3(0.34, 0.03, 0.105), m.call(Color(0.8, 0.7, 0.3), 0.5), Vector3(0, 0.0, 0), 0.005)
			p.attach_prop("c_bag", bag, "hand_l", Vector3(0, -0.2, 0.05), Vector3(0, PI / 2, 0))
		"gourmetstomach":
			var n = Node3D.new()
			var wm = m.call(Color(0.98, 0.98, 0.96), 0.7)
			Geo.box(n, Vector3(0.24, 0.26, 0.012), wm, Vector3.ZERO, 0.01)
			Geo.box(n, Vector3(0.24, 0.026, 0.014), m.call(Color(0.85, 0.15, 0.15), 0.6), Vector3(0, 0.1, 0), 0.004)
			Geo.box(n, Vector3(0.24, 0.026, 0.014), m.call(Color(0.85, 0.15, 0.15), 0.6), Vector3(0, 0.0, 0), 0.004)
			p.attach_prop("c_bib", n, "spine_03", Vector3(0, 0.02, 0.15), Vector3(0, 0, 0))
		"bagpipelungs":
			var n = Node3D.new()
			var bm = m.call(Color(0.5, 0.12, 0.12), 0.8)
			var dm = m.call(Color(0.12, 0.1, 0.09), 0.5)
			Geo.sphere(n, 0.13, bm, Vector3.ZERO, 0.85)
			Geo.box(n, Vector3(0.27, 0.03, 0.27), m.call(Color(0.1, 0.45, 0.2), 0.8), Vector3(0, 0.0, 0), 0.01)
			for sx in [-0.05, 0.0, 0.05]: Geo.cyl(n, 0.01, 0.016, 0.34, dm, Vector3(sx, 0.2, -0.04), 8)
			Geo.cyl(n, 0.011, 0.011, 0.22, dm, Vector3(0.12, 0.08, 0.03), 8).rotation.z = 1.0
			p.attach_prop("c_pipes", n, "spine_03", Vector3(0.0, 0.0, 0.2))
		"lowbattery":
			var n = Node3D.new()
			var gm = m.call(Color(0.15, 0.15, 0.17), 0.4)
			Geo.box(n, Vector3(0.2, 0.11, 0.035), gm, Vector3.ZERO, 0.01)
			Geo.box(n, Vector3(0.025, 0.05, 0.03), gm, Vector3(0.108, 0, 0), 0.005)
			var rm = m.call(Color(1.0, 0.15, 0.1), 0.3); rm.emission_enabled = true; rm.emission = Color(1, 0.1, 0.05)
			Geo.box(n, Vector3(0.035, 0.075, 0.04), rm, Vector3(-0.07, 0, 0.004), 0.003)
			p.attach_prop("c_batt", n, "spine_03", Vector3(0, 0.03, 0.15))
			p.cue.batt_mat = rm
		"hiccupclock":
			var n = Node3D.new()
			var cm = m.call(Color(0.95, 0.85, 0.3), 0.3, 0.4)
			var fc = m.call(Color(1, 1, 1), 0.4)
			var d = Geo.cyl(n, 0.075, 0.075, 0.035, cm, Vector3.ZERO, 20); d.rotation.x = PI / 2
			var f = Geo.cyl(n, 0.062, 0.062, 0.01, fc, Vector3(0, 0, 0.02), 20); f.rotation.x = PI / 2
			Geo.box(n, Vector3(0.008, 0.05, 0.006), m.call(Color(0.1, 0.1, 0.1), 0.5), Vector3(0, 0.022, 0.028), 0.001)
			Geo.box(n, Vector3(0.036, 0.008, 0.006), m.call(Color(0.1, 0.1, 0.1), 0.5), Vector3(0.016, 0, 0.028), 0.001)
			Geo.sphere(n, 0.028, m.call(Color(0.85, 0.2, 0.2), 0.4), Vector3(-0.045, 0.085, 0))
			Geo.sphere(n, 0.028, m.call(Color(0.85, 0.2, 0.2), 0.4), Vector3(0.045, 0.085, 0))
			p.attach_prop("c_clock", n, "spine_03", Vector3(0, 0.04, 0.16))
		"bluescreen":
			var img = Image.create(32, 28, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.05, 0.25, 0.85))
			var w = Color.WHITE
			for r in [Rect2i(8, 8, 3, 3), Rect2i(21, 8, 3, 3), Rect2i(9, 19, 14, 2), Rect2i(7, 21, 3, 2), Rect2i(22, 21, 3, 2)]:
				img.fill_rect(r, w)
			var tex = ImageTexture.create_from_image(img)
			var sm = StandardMaterial3D.new(); sm.albedo_texture = tex; sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			var q = QuadMesh.new(); q.size = Vector2(0.18, 0.16)
			var n = Node3D.new()
			Geo.mi(n, q, sm, Vector3.ZERO, 0.0, false)
			p.attach_prop("c_screen", n, "Head", Vector3(0, 0.04, 0.113))
		"lostshadow":
			var sh = MeshInstance3D.new(); var cm = CylinderMesh.new(); cm.top_radius = 0.34; cm.bottom_radius = 0.34; cm.height = 0.004; cm.radial_segments = 20
			sh.mesh = cm; sh.material_override = m.call(Color(0.05, 0.05, 0.07, 0.75), 1.0)
			sh.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			sh.top_level = true; sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			p.add_child(sh); p.cue.shadow = sh; p.cue.sh_pos = p.global_position
		"puffytoes":
			pass
		"deflated":
			if p.model: p.model.scale = Vector3(p.model.scale.x * 1.2, p.model.scale.y * 0.9, p.model.scale.z * 1.2)
			p.shape = p.shape * Vector3(1.2, 1.0, 1.2)
	if dis in ["balloonhead"]: pass

# ---------------------------------------------------------------- per-frame (every frame)
static func c_set(p: CharPuppet, k: String, v) -> void:
	p.cue[k] = v

# the cane is held low in the left hand; while walking the tip sweeps left-right and taps the floor at each side
static func _cane(p: CharPuppet, live: bool, T: float) -> void:
	var cane: Node3D = p.cue.cane
	if not is_instance_valid(cane): return
	var sk: Skeleton3D = p.skel
	var gfwd: Vector3 = p.global_basis * Vector3(0, 0, 1)
	var gright: Vector3 = -p.global_basis.x
	var pos: Vector3 = p.global_position
	cane.visible = p.visible and p.lie_k < 0.3
	if not cane.visible: return
	var walking: bool = p.vel.length() > 0.25
	var standing: bool = live and not p.seated and p.reach_w < 0.01
	if standing:
		_reach_s(p, "upperarm_l", "hand_l", pos + Vector3(0, 0.8, 0) + gfwd * 0.3 - gright * 0.1, 0.9)
	var hi = sk.find_bone("hand_l")
	if hi < 0: return
	var hand: Vector3 = sk.global_transform * sk.get_bone_global_pose(hi).origin
	var tip: Vector3
	if standing:
		var ph: float = T * (5.2 if walking else 1.2) + float(p.cue.ph)
		var sw: float = sin(ph)
		var amp: float = 0.3 if walking else 0.08
		tip = pos + gfwd * 0.9 + gright * (sw * amp - 0.05)
		tip.y = 0.02 + (0.06 * (1.0 - absf(sw)) if walking else 0.0)
	else:
		tip = Vector3(hand.x, 0.02, hand.z) + gfwd * 0.15 - gright * 0.12
	var v: Vector3 = hand - tip
	var L: float = clampf(v.length(), 0.6, 1.25)
	var y: Vector3 = v.normalized()
	var x: Vector3 = y.cross(gfwd)
	if x.length() < 0.01: x = y.cross(gright)
	x = x.normalized()
	var z: Vector3 = x.cross(y).normalized()
	cane.global_transform = Transform3D(Basis(x, y * L, z), hand)

static func speed(p: CharPuppet, spd: float, moving: bool) -> float:
	if p.cue.is_empty() or not moving: return spd
	return spd * float(p.cue.b.get("slow", 1.0))

static func tick(p: CharPuppet, gdt: float, moving: bool) -> void:
	var c: Dictionary = p.cue
	if c.is_empty(): return
	var b: Dictionary = c.b
	var T = Time.get_ticks_msec() / 1000.0
	var live: bool = p.lie_k < 0.3 and p.cue_vs == null
	c.env = 0.0
	# periodic behaviour
	if live:
		if float(c.u) < 0.0:
			c.t -= gdt
			if c.t <= 0.0:
				if bool(b.get("cont", false)) and b.mv == "none" or float(b.dur) < 0.2:
					_emit(p); c.t = randf_range(b.per[0], b.per[1])
				elif b.per[0] < 90:
					c.u = 0.0; c.fired = false; c.echo_n = 0
				else: c.t = 5.0
		else:
			c.u += gdt / float(b.dur)
			c.env = clampf(minf(c.u / 0.2, (1.0 - c.u) / 0.2), 0.0, 1.0)
			c.env = c.env * c.env * (3.0 - 2.0 * c.env)
			if not c.fired and c.u > 0.4:
				c.fired = true; _emit(p)
			if b.get("echo", false) and c.echo_n < 2 and c.u > 0.55 + 0.15 * c.echo_n:
				c.echo_n += 1; _emit(p)
			if c.u >= 1.0:
				c.u = -1.0; c.t = randf_range(b.per[0], b.per[1])
		if bool(b.get("cont", false)) and b.mv != "none" and float(c.u) >= 0.0 and b.get("mv") in ["talk", "chest"] and int(T * 3) % 1 == 0:
			pass
	# continuous: hop, props
	var d: String = c.d
	if live and p.model:
		if b.mv == "hop" and float(c.u) >= 0.0: p.model.position.y += sin(clampf(c.u, 0, 1) * PI) * 0.22
		if b.get("hop", false) and float(c.u) >= 0.55: p.model.position.y += sin(clampf((c.u - 0.55) / 0.45, 0, 1) * PI) * 0.12
		if b.mv == "hic" and float(c.u) >= 0.0: p.model.position.y += sin(clampf(c.u, 0, 1) * PI) * 0.07
		if d == "jellyspine": p.model.rotation.z += 0.0
	if c.has("nose_mat"):
		var k = 0.5 + 0.5 * sin(T * 6.0 + c.ph)
		c.nose_mat.emission_energy_multiplier = 0.2 + 2.6 * k
		c.nose_mat.albedo_color = Color(1.0, 0.1 + 0.15 * k, 0.08)
	if c.has("batt_mat"):
		c.batt_mat.emission_energy_multiplier = 0.2 + 1.8 * (0.5 + 0.5 * sin(T * 5.0))
	if props_has(p, "c_cloud"):
		var cl = p.props["c_cloud"]; cl.position.y = 0.0 + 0.01 * sin(T * 2.0)
		if live:
			c.ct -= gdt
			if c.ct <= 0.0:
				c.ct = 0.1; _drop(p, p.head_world() + Vector3(randf_range(-0.14, 0.14), 0.3, randf_range(-0.1, 0.1)))
	if c.has("shadow"):
		var tgt = p.global_position
		c.sh_pos = c.sh_pos.lerp(tgt, minf(1.0, gdt * 1.6))
		var off = (c.sh_pos - tgt)
		c.shadow.global_position = Vector3(c.sh_pos.x + 0.25, 0.02, c.sh_pos.z + 0.1)
	if d == "tail" and p.tail_node and live:
		p.tail_node.rotation.y = sin(T * 7.0 + c.ph) * 0.5 * (1.0 if not moving else 0.4)
	if d == "statichair" and props_has(p, "c_hair"):
		var h = p.props["c_hair"]; h.rotation.y = sin(T * 20.0) * 0.06; h.scale = Vector3.ONE * (1.0 + 0.08 * sin(T * 13.0))
	_update_puffs(p, gdt)

static func props_has(p: CharPuppet, n: String) -> bool:
	return p.props.has(n) and is_instance_valid(p.props[n])

# ---------------------------------------------------------------- bone layer (after the animation advance)
# the mixer does not always rewrite a bone that has not changed, so every rotation we add is undone first
# (restore the pose we saved if the bone still holds exactly what we wrote last time)
static func _undo(p: CharPuppet) -> void:
	var sv: Dictionary = p.rot_saved
	for gi in sv:
		var cur: Quaternion = p.skel.get_bone_pose_rotation(gi)
		if cur.dot(sv[gi][1]) > 0.99999: p.skel.set_bone_pose_rotation(gi, sv[gi][0])
	p.rot_saved = {}

static func _rot(p: CharPuppet, bone: String, axis: Vector3, ang: float) -> void:
	var sk: Skeleton3D = p.skel
	var gi = sk.find_bone(bone)
	if gi < 0 or absf(ang) < 0.0005: return
	var sv: Dictionary = p.rot_saved
	var base: Quaternion = sv[gi][0] if sv.has(gi) else sk.get_bone_pose_rotation(gi)
	CharPuppet.rot_global(sk, gi, Quaternion(axis.normalized(), ang))
	sv[gi] = [base, sk.get_bone_pose_rotation(gi)]

static func bones(p: CharPuppet) -> void:
	var c: Dictionary = p.cue
	if c.is_empty() or p.skel == null: return
	var b: Dictionary = c.b
	var sk: Skeleton3D = p.skel
	var live: bool = p.lie_k < 0.3 and p.cue_vs == null
	var env: float = c.env if live else 0.0
	var T = Time.get_ticks_msec() / 1000.0
	var fwd: Vector3 = (sk.global_basis.inverse() * p.global_basis * Vector3(0, 0, 1)).normalized()
	var up := Vector3.UP
	var side: Vector3 = up.cross(fwd).normalized()   # rotating `up` about this axis by +a leans the body forward
	var lean := 0.0
	var head_lean := 0.0
	var roll := 0.0
	var u: float = c.u
	var mv: String = b.mv
	lean += float(b.get("slump", 0.0)) if live else 0.0
	match mv:
		"bend": lean += 1.0 * env; head_lean += 0.2 * env
		"grope":
			if live and not p.seated: lean += 0.1; head_lean += 0.12 + 0.06 * sin(T * 1.3 + c.ph); roll += 0.03 * sin(T * 0.9 + c.ph)
		"yawn": head_lean -= 0.55 * env; lean -= 0.1 * env
		"sneeze":
			var s = 0.0
			if u >= 0.0: s = -smoothstep(0.0, 0.55, u) if u < 0.6 else lerpf(-1.0, 1.1, smoothstep(0.6, 0.72, u)) * (1.0 - smoothstep(0.72, 1.0, u))
			head_lean += 0.6 * s; lean += 0.35 * s
		"shake": roll += sin(T * 30.0) * 0.06 * env; head_lean += sin(T * 24.0) * 0.07 * env; lean += 0.12 * env
		"belly": lean += 0.55 * env; head_lean += 0.15 * env
		"hic":
			if u >= 0.0: lean += 0.3 * sin(clampf(u, 0, 1) * PI); head_lean -= 0.3 * sin(clampf(u, 0, 1) * PI)
		"talk": head_lean += sin(T * 9.0 + c.ph) * 0.1 * env; roll += sin(T * 5.0) * 0.04 * env
		"scratch": roll += 0.12 * env
		"chest":
			var beat = pow(maxf(0.0, sin(T * float(b.get("beat", 3.0)))), 6.0)
			if live: _rot(p, "spine_03", side, 0.0); _scale_chest(p, 1.0 + 0.05 * beat)
			lean += 0.1 * env
	# 1.0.0 diarrhea: knock-kneed waddle (hip sway) and a hunch while hurrying to the toilet
	if b.get("waddle", false) and live and not p.seated:
		roll += sin(T * 6.5 + c.ph) * (0.09 if p.rush_vis else 0.05)
		if p.rush_vis: lean += 0.22
	if lean != 0.0:
		_rot(p, "spine_01", side, lean * 0.3); _rot(p, "spine_02", side, lean * 0.4); _rot(p, "spine_03", side, lean * 0.3)
	if head_lean != 0.0:
		_rot(p, "neck_01", side, head_lean * 0.4); _rot(p, "Head", side, head_lean * 0.6)
	if roll != 0.0: _rot(p, "spine_03", fwd, roll)
	if c.has("cane"): _cane(p, live, T)
	# arms
	if not live or p.seated or p.reach_w > 0.01: return
	var hw: Vector3 = p.head_world()
	var gfwd: Vector3 = p.global_basis * Vector3(0, 0, 1)
	var gright: Vector3 = -p.global_basis.x
	match mv:
		"yawn", "echo", "ear": pass
	if mv == "yawn" and env > 0.01: _reach_s(p, "upperarm_r", "hand_r", hw + gfwd * 0.1 + Vector3(0, -0.02, 0), env)
	elif mv == "scratch" and env > 0.01: _reach_s(p, "upperarm_r", "hand_r", hw + gright * 0.11 + Vector3(0, 0.0 + 0.03 * sin(T * 16.0), 0.03), env)
	elif mv == "ear" and env > 0.01: _reach_s(p, "upperarm_r", "hand_r", hw + gright * 0.15 + Vector3(0, -0.02, 0.0), env)
	elif mv == "belly" and (env > 0.01 or p.rush_vis):
		var eb = maxf(env, 0.85 if p.rush_vis else 0.0)
		var bp = p.global_position + Vector3(0, 0.98, 0) + gfwd * 0.2
		_reach_s(p, "upperarm_r", "hand_r", bp - gright * 0.0 + gright * 0.08, eb); _reach_s(p, "upperarm_l", "hand_l", bp - gright * 0.08, eb)
	elif mv == "chest" and env > 0.01:
		var cp = p.global_position + Vector3(0, 1.28, 0) + gfwd * 0.18
		_reach_s(p, "upperarm_r", "hand_r", cp + gright * 0.03, env)
	elif mv == "wave" and env > 0.01:
		_reach_s(p, "upperarm_r", "hand_r", hw + Vector3(0, 0.3, 0) + gright * (0.12 + 0.12 * sin(T * 9.0)) + gfwd * 0.05, env)
	elif mv == "selfie":
		_reach_s(p, "upperarm_r", "hand_r", hw + gfwd * 0.42 + gright * 0.12 + Vector3(0, 0.08, 0), 1.0)
	elif mv == "grope":
		var k = 0.5 + 0.5 * sin(T * 2.4 + c.ph)
		_reach_s(p, "upperarm_r", "hand_r", p.global_position + Vector3(0, 1.0, 0) + gfwd * 0.4 + gright * (0.22 - 0.12 * k), 0.45)

static func _reach_s(p: CharPuppet, upper: String, hand: String, target: Vector3, w: float) -> void:
	var sk: Skeleton3D = p.skel
	var names = [upper, upper.replace("upperarm", "lowerarm")]
	var sv: Dictionary = p.rot_saved
	for nm in names:
		var gi = sk.find_bone(nm)
		if gi >= 0 and not sv.has(gi): sv[gi] = [sk.get_bone_pose_rotation(gi), Quaternion.IDENTITY]
	p._reach(upper, hand, target, w)
	for nm in names:
		var gi = sk.find_bone(nm)
		if gi >= 0 and sv.has(gi): sv[gi][1] = sk.get_bone_pose_rotation(gi)

static func _scale_chest(p: CharPuppet, k: float) -> void:
	var gi = p.skel.find_bone("spine_03")
	if gi >= 0: p.skel.set_bone_pose_scale(gi, Vector3.ONE * k)

# per-person build (heavy / thin / stoop / child head) + static disease body changes; re-applied after every animation advance
static func pose(p: CharPuppet) -> void:
	if p.skel == null: return
	_undo(p)
	var sk: Skeleton3D = p.skel
	var sh: Vector3 = p.shape   # build is a non-uniform MODEL scale (set in LookPool.apply); only the head is counter-scaled here
	var c: Dictionary = p.cue
	var d: String = c.d if not c.is_empty() else ""
	var hk: float = p.head_k
	if p.head_idx >= 0 and (sh != Vector3.ONE or hk != 1.0):
		sk.set_bone_pose_scale(p.head_idx, Vector3(hk / sh.x, hk, hk / sh.z))
	if p.stoop != 0.0:
		var fwd: Vector3 = (sk.global_basis.inverse() * p.global_basis * Vector3(0, 0, 1)).normalized()
		var side: Vector3 = Vector3.UP.cross(fwd).normalized()
		_rot(p, "spine_01", side, p.stoop * 0.3); _rot(p, "spine_02", side, p.stoop * 0.4); _rot(p, "spine_03", side, p.stoop * 0.3)
		_rot(p, "Head", side, -p.stoop * 0.7)
	if p.retch_t > 0.0 and p.lie_k < 0.3:
		# 0.9.9: being sick: double over, head down (a vomit puddle appears on the floor in front)
		var u2 = clampf(p.retch_t / 1.4, 0.0, 1.0)
		var e2 = sin(u2 * PI)
		var fw: Vector3 = (sk.global_basis.inverse() * p.global_basis * Vector3(0, 0, 1)).normalized()
		var sd2: Vector3 = Vector3.UP.cross(fw).normalized()
		var jerk = 1.0 + 0.15 * sin(p.retch_t * 22.0)
		_rot(p, "spine_01", sd2, 0.3 * e2 * jerk); _rot(p, "spine_02", sd2, 0.45 * e2 * jerk); _rot(p, "spine_03", sd2, 0.35 * e2)
		_rot(p, "neck_01", sd2, 0.25 * e2); _rot(p, "Head", sd2, 0.2 * e2)
	if c.is_empty(): return
	match d:
		"flathead":
			if p.head_idx >= 0 and absf(p.head_scale - 1.0) < 0.005: sk.set_bone_pose_scale(p.head_idx, Vector3(1.4 / sh.x, 0.52, 1.4 / sh.z))
		"puffytoes":
			for nm in ["foot_l", "foot_r"]:
				var i = sk.find_bone(nm)
				if i >= 0: sk.set_bone_pose_scale(i, Vector3(1.9, 1.5, 1.9))
	bones(p)

# ---------------------------------------------------------------- puffs
static func _anchor(p: CharPuppet, at: String) -> Vector3:
	var hw = p.head_world()
	var f: Vector3 = p.global_basis * Vector3(0, 0, 1)
	match at:
		"mouth": return hw + f * 0.13 + Vector3(0, -0.01, 0)
		"nose": return hw + f * 0.15 + Vector3(0, 0.04, 0)
		"head": return hw + Vector3(0, 0.3, 0)
		"belly": return p.global_position + Vector3(0, 1.0, 0) + f * 0.25
		"chest": return p.global_position + Vector3(0, 1.3, 0) + f * 0.22
		"phone": return hw + f * 0.42 + Vector3(0, 0.08, 0)
	return hw

static var _burp_last = 0
static func _emit(p: CharPuppet) -> void:
	var c: Dictionary = p.cue
	var b: Dictionary = c.b
	var key: String = b.ic
	if key == "": return
	# 0.9.9: stomach / fizzy patients audibly burp (only when on screen, at most one burp every 2.5 s overall)
	if c.d in ["gourmetstomach", "fizzyblood"] and p.is_inside_tree():
		var now = Time.get_ticks_msec()
		var cam = p.get_viewport().get_camera_3d()
		if now - _burp_last > 2500 and cam and cam.is_position_in_frustum(p.global_position + Vector3(0, 1, 0)):
			_burp_last = now
			var gm = p.get_tree().current_scene
			if gm and gm.has_method("snd"): gm.snd("burp")
	var n = int(b.get("burst", 1))
	for i in n:
		var s = Sprite3D.new()
		s.texture = icon(key)
		if s.texture == null: return
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED; s.shaded = false; s.double_sided = true; s.no_depth_test = true
		s.top_level = true
		s.pixel_size = 0.0026 if n == 1 else 0.002
		p.add_child(s)
		var a = _anchor(p, b.at)
		s.global_position = a + Vector3(randf_range(-0.05, 0.05) * (n - 1), 0, randf_range(-0.05, 0.05) * (n - 1))
		# 0.9.7: puffs stay attached to their patient (offset follows the body), rise only a little and fade quickly
		var vv = Vector3(randf_range(-0.06, 0.06), 0.22 + 0.05 * i, randf_range(-0.05, 0.05))
		if key in ["x_gas", "x_anger"]: vv = Vector3(0, 0.12, 0) + (p.global_basis * Vector3(0, 0, 0.25))
		c.puffs.append({"n": s, "t": 0.0, "v": vv, "life": 1.1, "off": s.global_position - p.global_position})

static func _drop(p: CharPuppet, at: Vector3) -> void:
	if _drop_mesh == null:
		var s = SphereMesh.new(); s.radius = 0.016; s.height = 0.07; s.radial_segments = 6; s.rings = 3
		_drop_mesh = s
	var mi = MeshInstance3D.new(); mi.mesh = _drop_mesh
	var mt = Geo.mat(Color(0.55, 0.78, 1.0), 0.2); mt.emission_enabled = true; mt.emission = Color(0.4, 0.65, 1.0); mt.emission_energy_multiplier = 0.6
	mi.material_override = mt; mi.top_level = true; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(mi); mi.global_position = at
	p.cue.puffs.append({"n": mi, "t": 0.0, "v": Vector3(0, -1.5, 0), "life": 0.5, "drop": true})

static func _update_puffs(p: CharPuppet, gdt: float) -> void:
	var L: Array = p.cue.puffs
	for i in range(L.size() - 1, -1, -1):
		var q = L[i]
		if not is_instance_valid(q.n): L.remove_at(i); continue
		q.t += gdt
		if q.has("off"):
			q.off += q.v * gdt
			q.n.global_position = p.global_position + q.off
		else: q.n.global_position += q.v * gdt
		if not q.get("drop", false):
			q.n.modulate.a = clampf((q.life - q.t) / 0.5, 0.0, 1.0)
			q.n.pixel_size *= 1.0 + gdt * 0.1
		if q.t >= q.life:
			q.n.queue_free(); L.remove_at(i)
