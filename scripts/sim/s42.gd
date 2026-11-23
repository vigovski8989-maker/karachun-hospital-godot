# v42.js (+v43Steal): stuck-in-furniture escape, own-room claim, rest standing, orderly cleaning (Theme Hospital style), bins/vomit, item ghost check, rooms against bottom wall
class_name Sim42
extends Sim41

func v42OnFurn(x, y) -> Variant:
	x = int(round(x)); y = int(round(y))
	for r in S.rooms:
		if x < r.x or y < r.y or x >= r.x + r.w or y >= r.y + r.h: continue
		roomLay(r)
		for t in r.it:
			for tt in tilesOf(t.x, t.y, t.fp):
				if tt[0] == x and tt[1] == y: return r
	return null

func v42FreeNear(x, y, r) -> Variant:
	x = int(round(x)); y = int(round(y))
	var B = blk()
	var best = null
	var bd = 1e9
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var tx: int = x + dx
			var ty: int = y + dy
			if r and (tx < r.x or ty < r.y or tx >= r.x + r.w or ty >= r.y + r.h): continue
			if tx < 0 or ty < 0 or tx >= S.w or ty >= S.h - 1 or B.has(ty * S.w + tx) or v42OnFurn(tx, ty): continue
			var d = absi(dx) + absi(dy)
			if d < bd:
				bd = d; best = {"x": tx, "y": ty}
	return best

func v42OwnFree(s) -> Variant:
	for r in S.rooms:
		if D.rooms.has(r.type) and drm(r.type).get("staff") == s.type and r.staff == null and not (r.type == "research" and resDone()): return r
	return null

# wrap 1 (innermost of v42): staff left standing "in the sofa" walk to a free tile
func _v42w1(s, dt: float) -> void:
	super.updStaff(s, dt)
	if not s.get("vs") and not s.get("oa") and s.path.is_empty() and (s.state == "idle" or s.state == "rest"):
		var r = v42OnFurn(s.x, s.y)
		if r:
			if s.state == "rest": s.state = "idle"
			s.restKey = null
			var f = v42FreeNear(s.x, s.y, r)
			if f: goTo(s, f.x, f.y)

# wrap 2: extra staff immediately take a new own room
func _v42w2(s, dt: float) -> void:
	if s.type != "handyman":
		var own = v42OwnFree(s)
		if own:
			if s.get("cover") and s.room != null and (s.state == "work" or s.state == "goto"):
				var r = room_by_id(s.room)
				if r == null or r.busy == null or s.state == "goto":
					releaseCover(s, r)
					if S.get("v42") == null: S.v42 = {"claims": 0}
					S.v42.claims += 1
					msg("➡ " + s.name + " уходит в свой новый кабинет «" + drm(own.type).name + "»")
			elif s.state == "read":
				if s.vs:
					if s.vs.ph == "sat": leaveSeat(s)
				else:
					s.rd = null; s.state = "idle"; s.path = []
			elif s.state == "idle" and s.vs and s.vs.ph != "sat":
				s._st42 = gnum(s, "_st42", 0.0) + dt
				if s._st42 > 3:
					clearSeat(s); s._st42 = 0.0
	_v42w1(s, dt)

func restSpot(sr, me) -> Dictionary:
	var s = super.restSpot(sr, me)
	if me.get("restKey"): return s
	var used = {}
	for o in S.staff:
		if not is_same(o, me) and o.get("restKey") == null and (o.state == "rest" or o.state == "torest"): used[str(int(round(o.x)), ",", int(round(o.y)))] = true
	var B = blk()
	var d = doorInner(sr)
	for y in range(sr.y, sr.y + sr.h):
		for x in range(sr.x, sr.x + sr.w):
			if used.has(str(x, ",", y)) or B.has(y * S.w + x) or v42OnFurn(x, y) or not walk(x, y): continue
			if d.x == x and d.y == y: continue
			return {"x": x, "y": y, "pose": "stand", "dir": 1}
	return s

func v42Claimed(o, me) -> bool:
	for h in S.staff:
		if not is_same(h, me) and ((h.get("task") and is_same(h.task.o, o)) or (h.get("cl") and is_same(h.cl.o, o))): return true
	return false

func v42FindJob(s) -> Variant:
	var acc = {"best": null, "bd": 1e9}
	var c = func(x, y, k, o, w := 0.0):
		var hm = null
		if k == "clean":
			for h in S.staff:
				if not is_same(h, s) and h.type == "handyman" and h.get("task") and is_same(h.task.o, o) and h.state == "goto": hm = h; break
		if not (hm and hyp(x - hm.x, y - hm.y) > hyp(x - s.x, y - s.y) + 1) and v42Claimed(o, s): return
		var d: float = hyp(x - s.x, y - s.y) - w
		if d < acc.bd:
			acc.bd = d; acc.best = {"k": k, "o": o, "x": x, "y": y}
	for l in S.litter: c.call(int(round(l.x)), int(round(l.y)), "clean", l, 6.0 if l.get("v") else 0.0)
	for r in S.rooms:
		if r.type == "toilet" and r.get("dirty"):
			var wq = wcCleanSpot(r)
			if wq: c.call(wq.x, wq.y, "wc", r, 15.0)
	for it in S.items:
		if it.type == "bin" and gnum(it, "fill", 0) >= 60: c.call(it.x, it.y, "bin", it, 2.0)
		if it.type == "plant" and gnum(it, "water", 100) < 50: c.call(it.x, it.y, "water", it)
	return acc.best

func v42Goal(s, j) -> bool:
	if goTo(s, j.x, j.y): return true
	for d in [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1]]:
		if walk(j.x + d[0], j.y + d[1]) and goTo(s, j.x + d[0], j.y + d[1]): return true
	return false

func v43Steal(o, me) -> void:
	for h in S.staff:
		if not is_same(h, me) and h.type == "handyman" and h.get("task") and is_same(h.task.o, o):
			h.task = null; h.state = "idle"; h.path = []; h.mop = false

func litter_has(o) -> bool:
	for l in S.litter:
		if is_same(l, o): return true
	return false
func items_has(o) -> bool:
	for l in S.items:
		if is_same(l, o): return true
	return false
func litter_remove(o) -> void:
	for i in S.litter.size():
		if is_same(S.litter[i], o):
			S.litter.remove_at(i); return

func updHandy(s, dt: float) -> void:
	# core clean removal by reference
	if s.state == "do" and s.get("task") and s.task.k == "clean" and s.t - dt * eff(s) <= 0:
		litter_remove(s.task.o)
	super.updHandy(s, dt)

# wrap 3 (outermost)
func updStaff(s, dt: float) -> void:
	if s.type == "handyman":
		_v42w2(s, dt)
		s.mop = s.state == "do" and s.get("task") and (s.task.k == "clean" or s.task.k == "wc")
		if s.state == "goto" and s.get("task") and s.task.k == "clean" and not litter_has(s.task.o):
			s.task = null; s.state = "idle"; s.path = []
		if s.get("task") and s.task.k == "wc" and not s.task.o.get("dirty") and s.state != "idle":
			s.task = null; s.state = "idle"; s.path = []; s.mop = false
		return
	if s.type != "orderly":
		_v42w2(s, dt); return
	if s.get("cl"):
		var j = s.cl
		var gone: bool = (not litter_has(j.o)) if j.k == "clean" else ((not j.o.get("dirty")) if j.k == "wc" else (not items_has(j.o)))
		if gone:
			s.cl = null; s.task = null; s.mop = false; s.path = []; s.state = "idle"
			v42Back(s); return
		if j.ph == "go":
			if move(s, dt):
				j.ph = "do"
				j.t = (4.5 if j.o.get("v") else 3.5) if j.k == "clean" else (5.0 if j.k == "wc" else 2.5)
				s.dir = ((0 if j.x > s.x else 2) if absf(j.x - s.x) > absf(j.y - s.y) else (1 if j.y > s.y else 3))
				s.mop = j.k == "clean" or j.k == "wc"
			return
		j.t -= dt * eff(s)
		if j.t <= 0:
			if j.k == "clean": litter_remove(j.o)
			elif j.k == "wc": j.o.dirty = false
			elif j.k == "bin": j.o.fill = 0
			else: j.o.water = 100.0
			S.v42cl = gnum(S, "v42cl", 0) + 1
			s.cl = null; s.task = null; s.mop = false
			s.fat = minf(100, s.fat + 2)
			s.state = "idle"
			var n = v42FindJob(s)
			if n and v42Goal(s, n):
				s.cl = n.duplicate(); s.cl.ph = "go"
				v43Steal(n.o, s)
				s.task = {"k": n.k, "o": n.o}
				s.state = "clean"
				return
			v42Back(s)
		return
	var morgueIdle: bool = s.state == "work" and not S.pats.any(func(p): return p.state == "dead" and p.get("body") == "wait")
	if (s.state == "idle" or morgueIdle) and not s.get("body") and (not s.get("vs") or s.vs.ph == "sat") and s.fat < 85:
		var j = v42FindJob(s)
		if j:
			if s.get("vs"):
				leaveSeat(s); return
			if v42Goal(s, j):
				s.cl = j.duplicate(); s.cl.ph = "go"
				v43Steal(j.o, s)
				s.task = {"k": j.k, "o": j.o}
				s.state = "clean"
				return
	_v42w2(s, dt)

func v42Back(s) -> void:
	var r = room_by_id(s.room)
	if r:
		var p = spotStaff(r)
		goTo(s, p.x, p.y)
		s.state = "goto"

func updPatient(p, dt: float) -> void:
	super.updPatient(p, dt)
	if p.state == "dead" or p.get("healed"): return
	var x = int(round(p.x))
	var y = int(round(p.y))
	if roomAt(x, y): return
	if rand() < dt * 0.004:
		for i in S.items:
			if i.type == "bin" and absf(i.x - p.x) + absf(i.y - p.y) < 4:
				i.fill = minf(100, gnum(i, "fill", 0) + 12); break
	if (p.state == "queue" or p.state == "wait" or p.state == "sit") and rand() < dt * 0.0012 and p.health < 70:
		S.litter.append({"x": p.x + rnd(-.3, .3), "y": p.y + rnd(-.3, .3), "v": 1})

# item ghost check (green/red outline)
func v42ItemCheck(type: String, x: int, y: int, rot = null) -> Dictionary:
	var dir = rot if rot != null else v41AutoDir(type, x, y)
	var bad = null
	if dir == null:
		dir = 1; bad = "Сюда нельзя"
	var fp = fpDir(type, dir)
	if bad == null:
		for t in tilesOf(x, y, fp):
			var tx: int = t[0]; var ty: int = t[1]
			if tx < 0 or ty < 0 or tx >= S.w or ty >= S.h - 1 or isHole(tx, ty) or roomAt(tx, ty) or blk().has(ty * S.w + tx):
				bad = "Сюда нельзя"; break
	if bad == null:
		S.items.append({"type": type, "x": x, "y": y, "fp": fp, "dir": dir}); invBlk()
		if not paths_ok(): bad = "Перекроет проход"
		S.items.pop_back(); invBlk()
	if bad == null and S.money < D.items[type].cost: bad = "Мало денег"
	return {"dir": dir, "fp": fp, "bad": bad, "x": x, "y": y, "type": type}

func validRoom(g: Dictionary) -> Variant:
	if g.x < 0 or g.y < 0 or g.x + g.w > S.w or g.y + g.h > S.h: return "За пределами"
	var e = S.ent
	if g.y + g.h >= S.h - 1 and e.x >= g.x - 1 and e.x <= g.x + g.w and g.y + g.h > e.y - 1: return "Перекрывает вход"
	for y in range(g.y, g.y + g.h):
		for x in range(g.x, g.x + g.w):
			if isHole(x, y): return "Нельзя строить здесь"
			if roomAt(x, y): return "Пересечение"
			if items_cover(x, y): return "Мешают предметы"
	var t = makeRoom(g.type, g.x, g.y, g.w, g.h, g.side)
	S.nid -= 1
	if t.bad: return "Мебель не помещается"
	var o = doorOut(t)
	if o.y >= S.h or not walk(o.x, o.y) or roomAt(o.x, o.y): return "Дверь упирается"
	S.rooms.append(t); invBlk(); _rgrid_sig = ""
	var ok = paths_ok()
	S.rooms.pop_back(); invBlk(); _rgrid_sig = ""
	return null if ok else "Перекрывает проход"
