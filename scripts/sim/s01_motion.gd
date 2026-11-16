# motion.js (+ fpDir/roomItem from anim.js): furniture layouts, spots, seats, doors
class_name SimMotion
extends SimCore

var SEAT_T = {"sit": 1.2, "wc": .8, "lie": 2.6}

func seatT(pose, def: float) -> float: return float(SEAT_T.get(pose, def))

func fpOf(k) -> Array:
	var f = D.furn.get(k) if D.has("furn") else null
	return f.fp if f and f.get("fp") else [1, 1]

func fpDir(k, d) -> Array:
	var f = fpOf(k)
	return [f[1], f[0]] if (d != null and (d == 0 or d == 2)) else f

func tilesOf(x, y, fp) -> Array:
	var a = []
	for i in int(fp[0]):
		for j in int(fp[1]): a.append([int(x) + i, int(y) + j])
	return a

func doorInner(r) -> Dictionary:
	return {"x": r.door.x + (-1 if r.side == 1 else (1 if r.side == 3 else 0)), "y": r.door.y + (1 if r.side == 2 else (-1 if r.side == 0 else 0))}

func room_template(r) -> Variant:
	return drm(r.type).get("layout")

func layout(r) -> Variant:
	var TT = room_template(r)
	if TT == null: return {"items": [], "sp": {}}
	var I = inner(r)
	var dI = doorInner(r)
	var maxc = 0
	for t in TT.items: maxc = maxi(maxc, int(t.c) + int(fpDir(t.k, t.get("dir"))[0]))
	for s in TT.spots.values(): maxc = maxi(maxc, int(s.c) + 1)
	var anchors = []
	var a0 = 0
	while a0 + maxc <= I.w:
		anchors.append(a0); a0 += 1
	var mid: float = (I.w - maxc) / 2.0
	anchors.sort_custom(func(p, q): return absf(p - mid) < absf(q - mid))
	for a in anchors:
		var items = []
		var sp = {}
		var ok = true
		for t in TT.items:
			var fp = fpDir(t.k, t.get("dir"))
			var x: int = I.x + a + int(t.c)
			var y: int = I.y + int(t.r)
			for tt in tilesOf(x, y, fp):
				if not (tt[0] >= I.x and tt[1] >= I.y and tt[0] < I.x + I.w and tt[1] < I.y + I.h): ok = false
			items.append({"k": t.k, "x": x, "y": y, "fp": fp, "soft": bool(t.get("soft", false)), "dir": t.get("dir")})
		if not ok: continue
		for n in TT.spots:
			var s = TT.spots[n]
			var x: int = I.x + a + int(s.c)
			var y: int = I.y + int(s.r)
			if not (x >= I.x and y >= I.y and x < I.x + I.w and y < I.y + I.h):
				ok = false; break
			var o = {"x": x, "y": y, "pose": s.get("pose"), "dir": s.get("dir"), "seat": s.get("seat"), "onItem": bool(s.get("onItem", false)), "face": s.get("face")}
			if s.get("at") != null: o.at = {"x": I.x + a + int(s.at.c), "y": I.y + int(s.at.r)}
			sp[n] = o
		if not ok: continue
		var bl = {}
		for it in items:
			if not it.soft:
				for tt in tilesOf(it.x, it.y, it.fp): bl[tt[1] * 1000 + tt[0]] = true
		if bl.has(dI.y * 1000 + dI.x): continue
		for s in sp.values():
			if bl.has(s.y * 1000 + s.x) and not s.onItem: ok = false
		if not ok: continue
		var seen = {dI.y * 1000 + dI.x: true}
		var q = [[dI.x, dI.y]]
		var i = 0
		while i < q.size():
			var c = q[i]; i += 1
			for d in DIRS:
				var nx: int = c[0] + d[0]
				var ny: int = c[1] + d[1]
				var k: int = ny * 1000 + nx
				if nx >= I.x and ny >= I.y and nx < I.x + I.w and ny < I.y + I.h and not bl.has(k) and not seen.has(k):
					seen[k] = true; q.append([nx, ny])
		for s in sp.values():
			if seen.has(s.y * 1000 + s.x): continue
			if s.onItem:
				var adj = false
				for d in DIRS:
					if seen.has((s.y + d[1]) * 1000 + s.x + d[0]): adj = true
				if adj: continue
			ok = false
		if not ok: continue
		var P = sp.get("patient", sp.get("rest1"))
		for s in sp.values():
			if s.face == "patient" and P:
				var dx: int = P.x - s.x
				var dy: int = P.y - s.y
				s.dir = ((0 if dx > 0 else 2) if absi(dx) > absi(dy) else (1 if dy > 0 else 3))
		return {"items": items, "sp": sp}
	return null

func roomLay(r) -> Variant:
	if r.get("sp") == null:
		var l = layout(r)
		if l == null: l = {"items": [], "sp": {}}
		r.it = l.items
		r.sp = l.sp
	return r

func spotPatient(r) -> Dictionary:
	roomLay(r)
	var s = r.sp.get("patient", r.sp.get("rest1", r.sp.get("wash")))
	if s: return s
	var i = inner(r)
	return {"x": i.x + int(floor(i.w / 2.0)), "y": i.y + int(floor(i.h / 2.0))}

func spotStaff(r) -> Dictionary:
	roomLay(r)
	var s = r.sp.get("staff")
	if s: return s
	var i = inner(r)
	return {"x": i.x + i.w - 1, "y": i.y + int(floor(i.h / 2.0))}

func restSpot(sr, me) -> Dictionary:
	roomLay(sr)
	for k in ["rest1", "rest2"]:
		var s = sr.sp.get(k)
		var key = str(sr.id) + k
		if s and not S.staff.any(func(o): return o != me and o.get("restKey") == key):
			me.restKey = key
			return s
	me.restKey = null
	return sr.sp.get("rest1") if sr.sp.get("rest1") else spotPatient(sr)

func takeSeat(e, sp) -> void:
	if sp == null or sp.get("pose") == null or sp.pose == "stand": return
	e.x = float(sp.x); e.y = float(sp.y)
	e.path = []
	e.dir = sp.dir if sp.get("dir") != null else 1
	e.vs = {"pose": sp.pose, "ph": "down", "t": 0.0, "sp": sp}

func leaveSeat(e) -> void:
	if e.get("vs") and e.vs.ph == "sat":
		e.vs.ph = "up"; e.vs.t = 0.0

func clearSeat(e) -> void:
	if e.get("vs") and e.vs.get("sp") and e.vs.sp.get("bench"): releaseBench(e)
	e.vs = null
	e.wash = false

func releaseBench(e) -> void:
	for b in S.items:
		if b.get("occ") != null:
			for k in b.occ.size():
				if b.occ[k] == e.id: b.occ[k] = 0

func tickVs(e, dt: float) -> void:
	var v = e.get("vs")
	if v == null: return
	v.t += dt
	var TT = seatT(v.pose, .9)
	if v.ph == "down" and v.t >= TT:
		v.ph = "sat"; v.t = 0.0
	elif v.ph == "up" and v.t >= TT:
		if v.get("sp") and v.sp.get("bench"): releaseBench(e)
		var sp = v.get("sp")
		e.vs = null
		if sp and sp.get("pose") == "lie":
			e.x = float(sp.x); e.y = float(sp.y)

func tickDoors(dt: float) -> void:
	var all: Array = S.pats + S.staff
	for r in S.rooms:
		var t = 0.0
		for e in all:
			if absf(e.x - r.door.x) + absf(e.y - r.door.y) < 1.7 and not e.get("vs"):
				t = 1.0; break
		var dop: float = gnum(r, "dop", 0.0)
		r.dop = dop + signf(t - dop) * minf(absf(t - dop), dt * 3.2)

func roomItem(sp, k) -> Variant:
	if sp == null: return null
	var r = roomAt(sp.x, sp.y)
	if r == null: return null
	for t in r.it:
		if t.k == k: return t
	return null
