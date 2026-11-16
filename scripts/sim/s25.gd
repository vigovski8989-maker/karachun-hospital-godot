# v25.js: real parallel places in M/L rooms. Room = main + (N-1) slot rooms (r.par) sharing outline/door, own furniture/staff/patient/queue.
class_name Sim25
extends Sim24

const V25NO := ["staffroom", "library", "chief"]
var V25C = {}

func v25Slot(type) -> bool:
	return not V25NO.has(type) and D.rooms.has(type) and D.rooms[type].get("layout") != null

func v25Dim(TT) -> Array:
	var mc = 0
	var mr = 0
	for t in TT.items:
		var f = fpDir(t.k, t.get("dir"))
		mc = maxi(mc, int(t.c) + int(f[0])); mr = maxi(mr, int(t.r) + int(f[1]))
	for s in TT.spots.values():
		mc = maxi(mc, int(s.c) + 1); mr = maxi(mr, int(s.r) + 1)
	return [mc, mr]

func layoutN(r, n: int) -> Variant:
	var TT = room_template(r)
	if TT == null: return null
	var I = inner(r)
	var dI = doorInner(r)
	var dm = v25Dim(TT)
	var mc: int = dm[0]
	var mr: int = dm[1]
	var tries = []
	for g in [1, 0]:
		for ax in [0, 1]:
			var W: int = mc if ax else n * mc + (n - 1) * g
			var H: int = n * mr + (n - 1) * g if ax else mr
			if W > I.w or H > I.h: continue
			var as_ = []
			var a0 = 0
			while a0 + W <= I.w:
				as_.append(a0); a0 += 1
			var mid: float = (I.w - W) / 2.0
			as_.sort_custom(func(p, q): return absf(p - mid) < absf(q - mid))
			var bs = [0]
			if ax:
				var b0 = 1
				while b0 + H <= I.h:
					bs.append(b0); b0 += 1
			for b in bs:
				for a in as_: tries.append([a, b, g, ax])
	for tr in tries:
		var a: int = tr[0]; var b: int = tr[1]; var g: int = tr[2]; var ax: int = tr[3]
		var cps = []
		var ok = true
		var bl = {}
		for k in n:
			if not ok: break
			var ox: int = I.x + a + (0 if ax else k * (mc + g))
			var oy: int = I.y + b + (k * (mr + g) if ax else 0)
			var items = []
			var sp = {}
			for t in TT.items:
				var fp = fpDir(t.k, t.get("dir"))
				var x: int = ox + int(t.c)
				var y: int = oy + int(t.r)
				for tt in tilesOf(x, y, fp):
					if not (tt[0] >= I.x and tt[1] >= I.y and tt[0] < I.x + I.w and tt[1] < I.y + I.h): ok = false
				items.append({"k": t.k, "x": x, "y": y, "fp": fp, "soft": bool(t.get("soft", false)), "dir": t.get("dir")})
			for nm in TT.spots:
				var s = TT.spots[nm]
				var x: int = ox + int(s.c)
				var y: int = oy + int(s.r)
				if not (x >= I.x and y >= I.y and x < I.x + I.w and y < I.y + I.h): ok = false
				var o = {"x": x, "y": y, "pose": s.get("pose"), "dir": s.get("dir"), "seat": s.get("seat"), "onItem": bool(s.get("onItem", false)), "face": s.get("face")}
				if s.get("at") != null: o.at = {"x": ox + int(s.at.c), "y": oy + int(s.at.r)}
				sp[nm] = o
			for it in items:
				if not it.soft:
					for tt in tilesOf(it.x, it.y, it.fp): bl[tt[1] * 1000 + tt[0]] = true
			cps.append({"items": items, "sp": sp})
		if not ok or bl.has(dI.y * 1000 + dI.x): continue
		for c in cps:
			for s in c.sp.values():
				if bl.has(s.y * 1000 + s.x) and not s.onItem: ok = false
		if not ok: continue
		var seen = {dI.y * 1000 + dI.x: true}
		var q = [[dI.x, dI.y]]
		var i = 0
		while i < q.size():
			var c0 = q[i]; i += 1
			for d in DIRS:
				var nx: int = c0[0] + d[0]
				var ny: int = c0[1] + d[1]
				var kk: int = ny * 1000 + nx
				if nx >= I.x and ny >= I.y and nx < I.x + I.w and ny < I.y + I.h and not bl.has(kk) and not seen.has(kk):
					seen[kk] = true; q.append([nx, ny])
		for c in cps:
			for s in c.sp.values():
				if seen.has(s.y * 1000 + s.x): continue
				if s.onItem:
					var adj = false
					for d in DIRS:
						if seen.has((s.y + d[1]) * 1000 + s.x + d[0]): adj = true
					if adj: continue
				ok = false
		if not ok: continue
		for c in cps:
			var P = c.sp.get("patient", c.sp.get("rest1"))
			for s in c.sp.values():
				if s.face == "patient" and P:
					var dx: int = P.x - s.x
					var dy: int = P.y - s.y
					s.dir = ((0 if dx > 0 else 2) if absi(dx) > absi(dy) else (1 if dy > 0 else 3))
		return cps
	return null

func v25N(type, w, h, side = 0) -> int:
	if not v25Slot(type): return 1
	var m = drm(type).min
	if w <= m[0] + 2 and h <= m[1] + 2: return 1
	var key = str(type, w, "x", h, "s", side if side else 0)
	if V25C.has(key): return V25C[key]
	var f = {"type": type, "x": 0, "y": 0, "w": w, "h": h, "side": side if side else 0, "door": {"x": 0, "y": 0}}
	placeDoor(f)
	var n = 1
	for k in [3, 2]:
		if layoutN(f, k) != null:
			n = k; break
	V25C[key] = n
	return n

func layout(r) -> Variant:
	if r and gnum(r, "nS", 1) > 1:
		var c = layoutN(r, int(r.nS))
		if c != null: return c[int(gnum(r, "slot", 0))]
	return super.layout(r)

func cap_v24(type, w, h) -> int: return super.v24Cap(type, w, h)
func v24Cap(type, w, h) -> int:
	var side = ui.ghost.side if ui.ghost and ui.ghost.type == type else 0
	return v25N(type, w, h, side) if v25Slot(type) else cap_v24(type, w, h)
func rCap(r) -> float:
	if r == null: return 1.0
	if v25Slot(r.type): return 1.0
	return float(r.cap) if gnum(r, "cap", 0) else float(cap_v24(r.type, r.w, r.h))

func ghostLabel(g: Dictionary) -> String:
	var sl = v25Slot(g.type)
	var c: int = v25N(g.type, g.w, g.h, g.side) if sl else cap_v24(g.type, g.w, g.h)
	return str(g.w - 2) + "×" + str(g.h - 2) + " " + V24SZ[c - 1] + (((" 👥×" + str(c)) if sl else (" ⚡×%.1f" % v24Spd(c))) if c > 1 else "")

func v24Pre(g: Dictionary, n: int) -> void:
	var m = drm(g.type).min
	var w0: int = m[0] + 2
	var h0: int = m[1] + 2
	if n == 0 or not v25Slot(g.type):
		g.w = mini(12, w0 + n); g.h = mini(12, h0 + n)
		if not v25Slot(g.type) and n:
			var s = 0
			while cap_v24(g.type, g.w, g.h) < n + 1 and s < 6:
				s += 1
				if g.w <= g.h: g.w = mini(12, g.w + 1)
				else: g.h = mini(12, g.h + 1)
	else:
		var best = null
		for w in range(w0, 13):
			for h in range(h0, 13):
				if v25N(g.type, w, h, g.side) >= n + 1 and (best == null or w * h < best[0] or (w * h == best[0] and absi(w - h) < absi(best[1] - best[2]))): best = [w * h, w, h]
		if best:
			g.w = best[1]; g.h = best[2]
		else:
			g.w = mini(12, w0 + 2); g.h = mini(12, h0 + 2)
			msg("Больше мест здесь не помещается")

func v25Cost(type, w, h, side) -> int:
	var b = v24Cost(type, w, h)
	var n = v25N(type, w, h, side)
	return maxi(b, int(round(drm(type).cost * (1 + .6 * (n - 1)) / 50.0)) * 50)

func roomBuildCost(g: Dictionary) -> int: return v25Cost(g.type, g.w, g.h, g.side)

func buildRoom(g: Dictionary) -> Variant:
	var bad = "не исследовано" if roomLocked(g.type) else validRoom(g)
	if bad:
		msg("Нельзя: " + bad); snd("bad"); return bad
	var d = drm(g.type)
	var cost = roomBuildCost(g)
	if S.money < cost:
		msg("Недостаточно денег"); return "Недостаточно денег"
	S.money -= cost
	var nr = makeRoom(g.type, g.x, g.y, g.w, g.h, g.side)
	nr.cost = cost
	var n = v25N(g.type, g.w, g.h, g.side)
	if not v25Slot(g.type): nr.cap = cap_v24(g.type, g.w, g.h)
	S.rooms.append(nr)
	if n > 1: v25Split(nr, n)
	invBlk()
	snd("build")
	msg("Построено: " + d.name + ((" на " + str(n) + " места") if n > 1 else "") + ((" — наймите: " + D.staff[d.staff].name + ((" ×" + str(n)) if n > 1 else "")) if d.get("staff") else ""))
	for p in S.pats:
		if p.state == "queue" or p.state == "seek": p.path = []
	return null

func sellRoom(id) -> void:
	var r = room_by_id(id)
	if r == null: return
	var m = room_by_id(r.par) if r.get("par") else r
	if m == null:
		super.sellRoom(id); return
	for s in S.rooms.filter(func(x): return x.get("par") == m.id):
		var mo = S.money
		super.sellRoom(s.id)
		S.money = mo
	super.sellRoom(m.id)

func after_load() -> void:
	super.after_load()
	for r in S.rooms.duplicate():
		if not r.get("par") and r.get("nS") == null and v25Slot(r.type):
			var n = v25N(r.type, r.w, r.h, r.side)
			r.nS = 1
			if n > 1: v25Split(r, n)

func v25Split(m, n: int) -> void:
	m.nS = n
	m.slot = 0
	var l = layout(m)
	if l == null:
		m.nS = 1; return
	m.it = l.items; m.sp = l.sp
	var at: int = S.rooms.find(m)
	for k in range(n - 1, 0, -1):
		var s = {"id": S.nid, "type": m.type, "x": m.x, "y": m.y, "w": m.w, "h": m.h, "side": m.side, "door": {"x": m.door.x, "y": m.door.y}, "staff": null, "queue": [], "busy": null, "cond": 100, "uses": 0, "par": m.id, "slot": k, "nS": n, "cost": 0}
		S.nid += 1
		var c = layout(s)
		s.it = c.items; s.sp = c.sp
		S.rooms.insert(at + 1, s)
	invBlk(); _rgrid_sig = ""

func v25Group(r) -> Array:
	var m = room_by_id(r.par) if r.get("par") else r
	if m == null: return [r]
	var o = [m]
	for x in S.rooms:
		if x.get("par") == m.id: o.append(x)
	return o

func roomItem(sp, k) -> Variant:
	if sp == null: return null
	var b = null
	var bd = 1e9
	for r in S.rooms:
		if not (sp.x >= r.x and sp.y >= r.y and sp.x < r.x + r.w and sp.y < r.y + r.h): continue
		for t in r.get("it", []):
			if t.k == k:
				var d: float = absf(t.x - sp.x) + absf(t.y - sp.y)
				if d < bd:
					bd = d; b = t
	return b
