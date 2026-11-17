# Real-gameplay pose audit (debug only, --audit=FRAMES): measures every puppet's bones against the furniture it uses
# and logs anomalies (legs up in bed, crooked lying, standing patients in sit rooms, upright on the scanner,
# overlapping bodies, lab nurse far from the arm). Optional --ashot=<dir>: first anomaly of each type -> screenshot.
class_name PoseAudit
extends Node

var game
var frames_left = 0
var n = {}
var ex = {}
var ov_pairs = {}
var frame = 0
var shot_dir = ""
var shot_q = []
var shot_done = {}
var shot_wait = -1
var cur_shot = ""
var stats = {}
var loiter = {}
var trace_room = ""

func _bw(p: CharPuppet, b: String) -> Vector3:
	var i = p.skel.find_bone(b)
	if i < 0: return p.global_position
	return p.skel.global_transform * p.skel.get_bone_global_pose(i).origin

func _hit(kind: String, info: String, at: Vector3) -> void:
	n[kind] = n.get(kind, 0) + 1
	if not ex.has(kind): ex[kind] = []
	if ex[kind].size() < 6: ex[kind].append("f%d %s" % [frame, info])
	if shot_dir != "" and not shot_done.has(kind) and shot_wait < 0:
		shot_done[kind] = true
		cur_shot = kind
		game.cam.focus = Vector3(at.x, 0, at.z); game.cam.zoom = 4.5; game.cam.apply()
		shot_wait = 3

func _stat(k: String, v: float) -> void:
	if not stats.has(k): stats[k] = [0, 0.0, 1e9, -1e9]
	var s = stats[k]
	s[0] += 1; s[1] += v; s[2] = minf(s[2], v); s[3] = maxf(s[3], v)

func _ent(id):
	for e in game.sim.S.pats:
		if e.id == id: return e
	for e in game.sim.S.staff:
		if e.id == id: return e
	return null

func _item_at(rid, x: int, y: int):
	var wb = game.view.wb
	if wb == null or not wb.items_nodes.has(rid): return null
	for it in wb.items_nodes[rid]:
		var t = it.t
		var fp = t.get("fp") if t.get("fp") else game.sim.fpOf(t.k)
		if x >= int(t.x) and y >= int(t.y) and x < int(t.x) + int(fp[0]) and y < int(t.y) + int(fp[1]): return it
	return null

func _process(_d: float) -> void:
	if game.sim.S.is_empty() or game.view == null: return
	frame += 1
	if shot_wait >= 0:
		shot_wait -= 1
		if shot_wait == 0:
			var img = get_viewport().get_texture().get_image()
			if img: img.save_png(shot_dir + "/a_" + cur_shot + ".png")
	if frame % 6 == 0: _scan()
	frames_left -= 1
	if frames_left <= 0:
		_report(); get_tree().quit()

var _dumped = {}
func _dump_rooms() -> void:
	for r in game.sim.S.rooms:
		if _dumped.has(r.id): continue
		_dumped[r.id] = true
		var its = []
		for it in r.get("it", []): its.append("%s@%s,%s fp=%s rot=%s" % [it.get("k"), it.x, it.y, it.get("fp"), it.get("rot", it.get("r"))])
		print("ROOMDUMP ", r.type, " par=", r.get("par"), " id=", r.id, " rect=", [r.x, r.y, r.w, r.h], " sp=", r.get("sp"), "\n   items=", its)

func _scan() -> void:
	if frame < 400: _dump_rooms()
	var sim = game.sim
	var view = game.view
	var arr = []
	var E = {}
	for e in sim.S.pats: E[e.id] = e
	for e in sim.S.staff: E[e.id] = e
	var seats = {}
	for e in E.values():
		if e.get("vs") and e.vs.get("sp"):
			var key = str(int(e.vs.sp.x), ",", int(e.vs.sp.y))
			if seats.has(key) and not e.vs.sp.get("bench"): _hit("seat_shared", "%d & %d at %s pose=%s" % [seats[key], e.id, key, e.vs.pose], Vector3(e.x, 0, e.y))
			seats[key] = e.id
	for id in view.puppets:
		var p: CharPuppet = view.puppets[id]
		var e = E.get(id)
		if e == null or p.skel == null: continue
		arr.append([p, e])
		var vs = e.get("vs")
		var r = sim.room_by_id(e.get("room"))
		var rt = str(r.type) if r else ""
		var rin = sim.roomAt(int(floor(p.position.x)), int(floor(p.position.z)))
		var rint = str(rin.type) if rin else ""
		var pel = _bw(p, "pelvis")
		var head = _bw(p, "Head")
		var fm = (_bw(p, "foot_l") + _bw(p, "foot_r")) * 0.5
		# ---- standing inside solid furniture (sofa/bed/desk/counter...)
		if p.lie_k < 0.05 and p._seat_w < 0.05:
			var it0 = view.item_at_tile(int(floor(p.position.x)), int(floor(p.position.z)))
			if it0 and not it0.get("soft") and str(it0.k) != "plant":
				_hit("inside_furn_" + str(it0.k), "id%d %s %s room=%s vs=%s anim=%s" % [e.id, e.get("type", "pat"), e.state, rint, (vs.pose + ":" + vs.ph) if vs else "-", p.cur], p.position)
		# ---- loitering: standing still inside a treatment room without a seat for > 2 s (game time)
		var still = (not vs) and not p.is_staff and p.vw_pos == null and p.lie_k < 0.05 and (e.get("path") == null or e.path.is_empty()) and rint in ["gp", "psych", "diag", "ward", "staffroom"] and e.state != "leave" and e.state != "dead" and not (e.state == "treat" and rint in ["diag", "ward"] and float(e.t) < 2.7)
		if still:
			loiter[e.id] = loiter.get(e.id, 0.0) + 6.0 / 30.0 * game.sim.speed
			if loiter[e.id] > 2.0: _hit("loiter_" + rint, "id%d %s %s pos=(%.1f,%.1f) anim=%s room=%s need=%s ws=%s path=%d" % [e.id, e.get("type", "pat"), e.state, e.x, e.y, p.cur, e.get("room"), e.get("need"), e.get("wantSeat"), e.path.size()], p.position)
		else: loiter.erase(e.id)
		if trace_room != "" and not p.is_staff and rint == trace_room and (e.state == "treat" or e.state == "enter") and frame % 12 == 0:
			print("TRACE f%d id%d %s t=%.1f/%.1f vs=%s lie=%.2f sw=%.2f pos=(%.2f,%.2f) mp=(%.2f,%.2f) yaw=%.2f anim=%s" % [frame, e.id, e.state, float(e.t), float(e.get("tT", 0)), (vs.ph + ":" + str(snappedf(vs.t, .1))) if vs else "-", p.lie_k, p._seat_w, e.x, e.y, p.position.x, p.position.z, p.rotation.y, p.cur])
		# ---- lying
		if p.lie_k > 0.5:
			var lift = fm.y - pel.y
			_stat("lie_feet_above_pelvis", lift)
			if lift > 0.22: _hit("lie_legs_up", "id%d %s room=%s ph=%s lie=%.2f lift=%.2f anim=%s" % [e.id, e.state, rt, vs.ph if vs else "-", p.lie_k, lift, p.cur], pel)
			if vs and vs.ph == "sat" and vs.get("sp"):
				var b = p._bed_of(view, vs.sp)
				if b:
					var ax: Vector3 = b.piv.global_transform.basis.z.normalized()
					var bd = Vector3(head.x - fm.x, 0, head.z - fm.z)
					var ang = rad_to_deg(acos(clampf(absf(bd.normalized().dot(ax)), 0, 1))) if bd.length() > .2 else 90.0
					_stat("lie_axis_deg_" + str(b.t.k), ang)
					var lp = b.piv.global_transform.affine_inverse() * pel
					_stat("lie_pel_off_" + str(b.t.k), Vector2(lp.x, lp.z).length())
					if ang > 15.0: _hit("lie_crooked", "id%d %s %s ang=%.0f yaw=%.2f bedyaw=%.2f" % [e.id, rt, b.t.k, ang, p.rotation.y, b.piv.rotation.y], pel)
					if absf(lp.x) > .3 or absf(lp.z) > .8: _hit("lie_off_bed", "id%d %s lp=%s" % [e.id, b.t.k, lp], pel)
					if absf(head.y - fm.y) > .25: _hit("lie_not_flat", "id%d dy=%.2f" % [e.id, head.y - fm.y], pel)
		# ---- scanner / bed: treat while not lying
		if not p.is_staff and e.state == "treat" and rt in ["diag", "ward"] and vs and vs.ph == "sat" and p.lie_k < 0.8:
			_hit("lie_room_upright", "id%d %s lie=%.2f anim=%s" % [e.id, rt, p.lie_k, p.cur], pel)
		if not p.is_staff and e.state == "treat" and rt in ["diag", "ward"] and vs == null and float(e.t) > 2.7:
			_hit("lie_room_novs", "id%d %s t=%.1f/%.1f pos=(%.1f,%.1f) anim=%s staff=%s" % [e.id, rt, float(e.t), float(e.get("tT", 0)), e.x, e.y, p.cur, sim.staff_by_id(r.staff).state if sim.staff_by_id(r.staff) else null], pel)
		# ---- seated
		if vs and vs.ph == "sat" and vs.pose == "sit" and p.lie_k < 0.05:
			var sp = vs.sp
			_stat("sit_pelvis_y_" + str(p._seat_kind(sim, e, sp, vs.pose)), pel.y)
			if fm.y > 0.16: _hit("sit_feet_up", "id%d %s %s feet=%.2f" % [e.id, e.type if p.is_staff else "pat", rt, fm.y], pel)
			var it = _item_at(e.get("room") if e.get("room") != null else -1, int(sp.x), int(sp.y))
			if it == null and r == null:
				for rr in sim.S.rooms:
					it = _item_at(rr.id, int(sp.x), int(sp.y))
					if it: break
			if it:
				var fwd_i: Vector3 = it.piv.global_transform.basis.z
				var fwd_p = Vector3(sin(p.rotation.y), 0, cos(p.rotation.y))
				if fwd_i.dot(fwd_p) < 0.7: _hit("sit_facing", "id%d %s %s k=%s dot=%.2f" % [e.id, e.type if p.is_staff else "pat", rt, it.t.k, fwd_i.dot(fwd_p)], pel)
				var lp = it.piv.global_transform.affine_inverse() * pel
				_stat("sit_pel_localz_" + str(it.t.k), lp.z)
				if pel.y > float(p._seat_h) + .25 or pel.y < float(p._seat_h) - .05: _hit("sit_height", "id%d %s %s pel.y=%.2f seat=%.2f" % [e.id, rt, it.t.k, pel.y, p._seat_h], pel)
		# ---- sit rooms: patient treated but not sitting
		if not p.is_staff and e.state == "treat" and rt in ["gp", "psych"]:
			var el = float(e.get("tT", 0)) - float(e.t)
			if el > 1.5 and float(e.t) > 1.5 and not (vs and vs.ph == "sat"):
				_hit("treat_not_sitting", "id%d %s vs=%s pos=(%.1f,%.1f) sp=%s" % [e.id, rt, vs.ph if vs else "null", e.x, e.y, sim.spotPatient(r)], pel)
		# ---- lab
		if p.is_staff and e.state == "work" and rt == "lab":
			for q in sim.S.pats:
				if q.get("room") == r.id and q.state == "treat":
					var pq = view.puppets.get(q.id)
					var qq = CharPuppet.procQ(q)
					if pq and qq > .5 and qq < .7 and p.vw_arrived:
						var dh = p.hand_world("hand_r").distance_to(pq.hand_world("hand_r"))
						_stat("lab_hand_dist", dh)
						var dd = Vector2(p.position.x - pq.position.x, p.position.z - pq.position.z).length()
						_stat("lab_body_dist", dd)
						if dh > .3: _hit("lab_far", "nurse%d pat%d hand=%.2f body=%.2f n=(%.1f,%.1f) vw=%s goal=%s pts=%d p=(%.1f,%.1f) pst=%s qq=%.2f room=%s/%s rect=%s sp=%s" % [e.id, q.id, dh, dd, e.x, e.y, p.vw_pos, p.vw_goal, p.vw_pts.size(), q.x, q.y, str(pq.position), qq, e.get("room"), q.get("room"), [r.x, r.y, r.w, r.h], r.sp], p.position)
	# ---- overlaps
	for i in arr.size():
		var a: CharPuppet = arr[i][0]
		if a.lie_k > .05 or not a.visible: continue
		for j in range(i + 1, arr.size()):
			var b: CharPuppet = arr[j][0]
			if b.lie_k > .05 or not b.visible: continue
			if a.seated and b.seated and arr[i][1].vs and arr[j][1].vs and arr[i][1].vs.ph == "sat" and arr[j][1].vs.ph == "sat": continue
			var d = Vector2(a.position.x - b.position.x, a.position.z - b.position.z).length()
			if d < 0.38:
				var key = str(mini(a.eid, b.eid)) + "-" + str(maxi(a.eid, b.eid))
				var ea = arr[i][1]; var eb = arr[j][1]
				var cat = ("S" if a.seated else ("W" if ea.get("path") and ea.path.size() else "I")) + ("S" if b.seated else ("W" if eb.get("path") and eb.path.size() else "I"))
				ov_pairs[key] = ov_pairs.get(key, 0) + 1
				_hit("overlap_" + cat, "%d(%s %s) %d(%s %s) d=%.2f" % [a.eid, ea.get("type", "pat"), ea.state, b.eid, eb.get("type", "pat"), eb.state, d], a.position)

func _report() -> void:
	print("AUDIT frames=", frame, " day=", game.sim.S.day, " pats=", game.sim.S.pats.size(), " staff=", game.sim.S.staff.size(), " overlap_pairs=", ov_pairs.size())
	var ks = n.keys(); ks.sort()
	for k in ks:
		print("AUDIT ", k, " ", n[k])
		for s in ex[k]: print("   ", s)
	var sk = stats.keys(); sk.sort()
	for k in sk:
		var s = stats[k]
		print("ASTAT %s n=%d mean=%.3f min=%.3f max=%.3f" % [k, s[0], s[1] / maxf(1, s[0]), s[2], s[3]])

