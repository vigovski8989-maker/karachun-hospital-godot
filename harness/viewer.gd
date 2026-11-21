# Close-up test bench: characters standing / walking / sitting on every seat prefab, rendered from the game's iso camera.
# usage: tools/godot --path game -s res://harness/viewer.gd -- --out=/abs.png [--rot=deg] [--mode=shoes|seats] [--zoom=m]
extends SceneTree
var out = "/tmp/viewer.png"
var rot = 0.0
var mode = "seats"
var zoom = 4.0
var frames = 0
var snaps = [40]
var anim_dis = "Idle"
var dis_ids = []
var crowd_n = 0
var id0 = 100
var no_tweak = false
var pups = []
var cam: Camera3D
func _initialize():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--rot="): rot = float(a.substr(6))
		elif a.begins_with("--mode="): mode = a.substr(7)
		elif a.begins_with("--zoom="): zoom = float(a.substr(7))
		elif a == "--notweak": no_tweak = true
		elif a.begins_with("--snaps="): snaps = Array(a.substr(8).split(",")).map(func(x): return int(x))
		elif a.begins_with("--anim="): anim_dis = a.substr(7)
		elif a.begins_with("--n="): crowd_n = int(a.substr(4))
		elif a.begins_with("--id0="): id0 = int(a.substr(6))
		elif a.begins_with("--ids="): dis_ids = Array(a.substr(6).split(","))
	var w = Node3D.new(); root.add_child(w)
	var env = WorldEnvironment.new(); var e = Environment.new()
	e.background_mode = Environment.BG_COLOR; e.background_color = Color(0.8, 0.82, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.ambient_light_color = Color.WHITE; e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC; e.tonemap_exposure = 0.85; e.tonemap_white = 3.0
	env.environment = e; w.add_child(env)
	var sun = DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-55, 35, 0); sun.light_energy = 1.1; sun.shadow_enabled = true; w.add_child(sun)
	var fl = MeshInstance3D.new(); var pm = PlaneMesh.new(); pm.size = Vector2(20, 20); fl.mesh = pm
	fl.material_override = Geo.mat(Color(0.9, 0.9, 0.88), 0.8); w.add_child(fl)
	cam = Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.keep_aspect = Camera3D.KEEP_WIDTH; cam.size = zoom
	w.add_child(cam)
	var dir = Vector3(1.0, 0.92, 1.0).normalized().rotated(Vector3.UP, deg_to_rad(rot))
	var c = Vector3(1.5, 0.6, 0.5) if mode == "seats" else (Vector3(0, 0.9, 0) if mode == "all" else Vector3(1.0, 0.5, 0))
	cam.look_at_from_position(c + dir * 30.0, c, Vector3.UP)
	if mode == "seats":
		var seats = [["chair_plain", "chair"], ["chair_office", "chair_office"], ["sofa", "sofa"], ["bench", "bench"], ["elchair", "elchair"], ["stool", "stool"]]
		for i in seats.size():
			var x = (i % 3) * 1.5
			var z = (i / 3) * 1.6
			var k = seats[i][0]
			var piv = Node3D.new(); piv.position = Vector3(x, 0, z); w.add_child(piv)
			if k == "stool":
				var cy = CylinderMesh.new(); cy.top_radius = .19; cy.bottom_radius = .19; cy.height = .06
				Geo.mi(piv, cy, Geo.mat(Color(0.2, 0.45, 0.75)), Vector3(0, .47, -0.14), 0.0)
				var lg = CylinderMesh.new(); lg.top_radius = .03; lg.bottom_radius = .03; lg.height = .44
				Geo.mi(piv, lg, Geo.mat(Color(0.3, 0.3, 0.3)), Vector3(0, .23, -0.14), 0.0)
			else:
				var g = WorldBuild.prefab(k)
				var nf = [2, 1] if k in ["sofa", "bench"] else [1, 1]
				g.position = Vector3(-0.5, 0, -0.5)
				piv.add_child(g)
			var p = CharPuppet.new(); w.add_child(p)
			p.setup("res://assets/chars/%s.glb" % ["patient_a", "doctor", "nurse", "patient_a", "orderly", "patient_a"][i], Color(0.3, 0.6, 1.0) if i % 3 == 0 else null)
			p.set_look(CharPuppet.SKIN_TONES[i % 7], [Color(0.13, 0.11, 0.1), Color(0.1, 0.1, 0.1), Color(0.95, 0.95, 0.95), Color(0.36, 0.22, 0.13), Color(0.18, 0.3, 0.55), Color(0.55, 0.12, 0.12)][i], "")
			var sk = seats[i][1]
			var f = Vector3(0, 0, 1)
			p.position = Vector3(x, 0, z) + f * float(CharPuppet.SIT_F.get(sk, .2))
			p.set_meta("seat_h", float(CharPuppet.SEAT_H.get(sk, .5)))
			p.set_meta("anim", "Sitting_Idle")
			pups.append(p)
	elif mode == "dis":
		var D = JSON.parse_string(FileAccess.get_file_as_string("res://data/effective_data.json"))
		var ids = []
		for d in D.D.diseases: ids.append(d.id)
		if not dis_ids.is_empty(): ids = dis_ids
		if crowd_n > 0:
			ids = []
			for i in crowd_n: ids.append("none")
		var wv = WorldView.new(); wv.chars_root = w; w.add_child(wv)
		var cols = 7 if ids.size() > 12 else 6
		for i in ids.size():
			var p = wv._make_puppet({"id": id0 + i, "dis": ids[i], "hue": i * 47.0}, false)
			p.position = Vector3((i % cols) * 1.3 - (mini(ids.size(), cols) - 1) * 0.65, 0, -(i / cols) * 2.3)
			p.set_meta("anim", anim_dis); p.set_meta("seat_h", -1.0)
			if not p.cue.is_empty(): p.cue.t = 0.2 + (i % 5) * 0.12
			pups.append(p)
		var rows = (ids.size() + cols - 1) / cols
		var cc = Vector3(0, 0.8, -(rows - 1) * 1.15)
		cam.look_at_from_position(cc + dir * 30.0, cc, Vector3.UP)
	elif mode == "all":
		var names = ["patient_a", "doctor", "orderly", "rocker", "bighead", "mummy", "nurse", "receptionist", "invisible"]
		for i in names.size():
			var p = CharPuppet.new(); w.add_child(p)
			p.setup("res://assets/chars/%s.glb" % names[i], null)
			p.set_look(CharPuppet.SKIN_TONES[(i * 2) % 7], Color(0.2, 0.2, 0.2), "")
			p.position = Vector3(i * 0.8 - 3.2, 0, 0)
			p.set_meta("anim", "Idle"); p.set_meta("seat_h", -1.0)
			pups.append(p)
			var ms = []
			for ch in p.skel.get_children():
				if ch is MeshInstance3D: ms.append(ch.name)
			print("ALLM ", names[i], " ", ms)
	else:
		var ms = ["patient_a", "nurse", "doctor", "patient_a"]
		for i in 4:
			var p = CharPuppet.new(); w.add_child(p)
			p.setup("res://assets/chars/%s.glb" % ms[i], Color(0.9, 0.4, 0.3) if i == 0 else (Color(0.3, 0.8, 0.4) if i == 3 else null))
			p.set_look(CharPuppet.SKIN_TONES[(i * 2) % 7], [Color(0.36, 0.22, 0.13), Color(0.95, 0.95, 0.95), Color(0.1, 0.1, 0.1), Color(0.18, 0.3, 0.55)][i], "")
			p.position = Vector3(i * 0.7, 0, 0)
			p.rotation.y = 0.6 if i % 2 == 0 else -0.4
			p.set_meta("anim", "Walk" if i >= 2 else "Idle")
			p.set_meta("seat_h", -1.0)
			pups.append(p)
	process_frame.connect(_tick)

func _tick():
	frames += 1
	for p in pups:
		p.play(p.get_meta("anim"))
		p.ap.advance(0.05)
		if p.model and p.get_meta("seat_h") <= 0: p.model.position.y = 0.0
		if not p.cue.is_empty(): DisCue.tick(p, 0.05, p.get_meta("anim") == "Walk")
		if p.badge and not OS.get_environment("NOBADGE_TICK"):
			p.badge_tick(true)
			if p.badge: p.badge.visible = true; p.badge.modulate.a = 1.0
		if not p.cue.is_empty() or p.stoop != 0.0 or p.shape != Vector3.ONE or p.head_k != 1.0: DisCue.pose(p)
		p._seat_w = 1.0 if p.get_meta("seat_h") > 0 else 0.0
		if p._seat_w > 0.5 and p.cur == "Sitting_Idle" and not no_tweak: p._sit_tweak(1.0)
		var sh: float = p.get_meta("seat_h")
		if sh > 0 and p.thigh_l >= 0:
			var ty = (p.skel.get_bone_global_pose(p.thigh_l).origin.y + p.skel.get_bone_global_pose(p.thigh_r).origin.y) * 0.5
			p.model.position.y = clampf(sh + .08 - ty, -.3, .3)
	if frames == snaps[-1] and OS.get_environment("DBG_HEAD") != "":
		for p in pups: print("HEADDBG ", p.head_k, " idx ", p.head_idx, " sc ", p.skel.get_bone_pose_scale(p.head_idx) if p.head_idx >= 0 else null, " cue ", p.cue.get("d", ""))
	if frames in snaps:
		root.get_viewport().get_texture().get_image().save_png(out.replace(".png", "_%d.png" % frames) if snaps.size() > 1 else out)
		if frames == snaps[-1]: quit()
