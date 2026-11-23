# Port of game.js (core of «Больница Карачун» 45.1.0). Later patch files (motion, mech, v11..v42)
# extend this class and override methods; super.f() == the captured previous function in the JS patch chains.
class_name SimCore
extends RefCounted

const T := 32
const DAY := 8.0
const MONTH_DAYS := 30
const SAVE_KEY := "hohotun_trial45_save_v1"
const DIRS := [[0, 1], [1, 0], [0, -1], [-1, 0]]
const FIRST := ["Анна", "Борис", "Вера", "Глеб", "Дина", "Егор", "Жанна", "Илья", "Кира", "Лев", "Мила", "Олег", "Пётр", "Рита", "Семён", "Таня", "Фёдор", "Юля", "Ян", "Зоя"]
const LAST := ["Пилюлькин", "Градусов", "Бинтов", "Шприцев", "Таблеткин", "Сиропов", "Компрессов", "Йодов", "Ваткин", "Пульсов", "Микстуров", "Клизмин"]
const FEM := ["Анна", "Вера", "Дина", "Жанна", "Кира", "Мила", "Рита", "Таня", "Юля", "Зоя"]

var D: Dictionary = {}
var S: Dictionary = {}
var speed: float = 1.0
var dstat = {}   # harness-only death stats (not saved)
var rng = RandomNumberGenerator.new()
var msgs: Array = []          # [{t, text}]
var events: Array = []        # sound/view events: [name, arg]
var errors: Array = []
var ui: Dictionary = {"mode": null, "ghost": null, "sel": null}
var _blk_cache = null

func _init() -> void:
	rng.randomize()

# ---------- helpers (JS semantics) ----------
func rnd(a: float, b: float) -> float: return a + rng.randf() * (b - a)
func ri(a: int, b: int) -> int: return int(floor(rnd(a, b + 1)))
func pick(a: Array): return a[int(floor(rng.randf() * a.size()))]
func rand() -> float: return rng.randf()
func pname() -> String:
	var f: String = pick(FIRST)
	return f + " " + pick(LAST) + ("а" if FEM.has(f) else "")
func L() -> Dictionary: return D.levels[S.lv]
func gnum(o, k: String, def = 0) -> Variant:
	if o is Dictionary and o.has(k) and o[k] != null: return o[k]
	return def
func room_by_id(id) -> Variant:
	if id == null: return null
	for r in S.rooms:
		if r.id == id: return r
	return null
func staff_by_id(id) -> Variant:
	if id == null: return null
	for s in S.staff:
		if s.id == id: return s
	return null
func pat_by_id(id) -> Variant:
	if id == null: return null
	for p in S.pats:
		if p.id == id: return p
	return null
func rooms_of(t: String) -> Array:
	var o = []
	for r in S.rooms:
		if r.type == t: o.append(r)
	return o
func first_room(t: String) -> Variant:
	for r in S.rooms:
		if r.type == t: return r
	return null
var _re_f0: RegEx
func msg(t: String) -> void:
	if _re_f0 == null:
		_re_f0 = RegEx.new(); _re_f0.compile("(\\d)\\.0(?!\\d)")
	t = _re_f0.sub(t, "$1", true)
	msgs.append({"t": S.get("t", 0.0), "text": t})
	if msgs.size() > 200: msgs.pop_front()
func snd(n: String) -> void: events.append(["snd", n])
func drm(t: String) -> Dictionary: return D.rooms[t]
func hyp(a: float, b: float) -> float: return sqrt(a * a + b * b)

func load_data(path := "res://data/effective_data.json") -> void:
	var f = FileAccess.open(path, FileAccess.READ)
	var j = JSON.parse_string(f.get_as_text())
	D = j.D
	D.dis = {}
	for d in D.diseases: D.dis[d.id] = d
	consts_loaded(j.consts)

func consts_loaded(_c: Dictionary) -> void: pass

func newGame(li := 0, _quiet := true) -> void:
	var Lv: Dictionary = D.levels[li]
	S = {"lv": li, "w": int(Lv.w), "h": int(Lv.h), "money": Lv.money, "rep": Lv.rep, "t": 0.0, "day": 0, "rooms": [], "items": [], "staff": [], "pats": [], "litter": [], "nid": 1, "spawnT": 5.0, "cured": 0, "deaths": 0, "sent": 0, "won": false, "lost": false, "cands": null, "lastMonth": 0, "earn": 0}
	S.ent = {"x": int(Lv.entX) if Lv.get("entX") != null else int(floor(Lv.w / 2.0)), "y": int(Lv.h) - 1}
	mechInit()
	genCands()
	invBlk()
	msg(Lv.name)

# ---------- grid ----------
func roomAt(x, y) -> Variant:
	for r in S.rooms:
		if x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h: return r
	return null
func isWall(r, x, y) -> bool:
	if r == null: return false
	var edge: bool = x == r.x or y == r.y or x == r.x + r.w - 1 or y == r.y + r.h - 1
	return edge and not (x == r.door.x and y == r.door.y)
func isHole(x, y) -> bool:
	if inLot(x, y): return true
	var hs = L().get("holes")
	if hs == null: return false
	for h in hs:
		if x >= h[0] and y >= h[1] and x < h[0] + h[2] and y < h[1] + h[3]: return true
	return false
func inLot(_x, _y) -> bool: return false
func invBlk() -> void:
	_blk_cache = null
	_rgrid_sig = ""
func blk() -> Dictionary:
	if _blk_cache != null and _blk_cache.n == S.nid and _blk_cache.r == S.rooms.size() and _blk_cache.i == S.items.size() and _blk_cache.S == S:
		return _blk_cache.s
	var s = {}
	for r in S.rooms:
		roomLay(r)
		for t in r.it:
			if not t.get("soft", false):
				for tt in tilesOf(t.x, t.y, t.fp): s[int(tt[1]) * S.w + int(tt[0])] = true
	for i in S.items:
		if i.get("fp") == null: i.fp = fpOf(i.type)
		for tt in tilesOf(i.x, i.y, i.fp): s[int(tt[1]) * S.w + int(tt[0])] = true
	_blk_cache = {"s": s, "S": S, "n": S.nid, "r": S.rooms.size(), "i": S.items.size()}
	return s
func walk0(x, y) -> bool:
	if x < 0 or y < 0 or x >= S.w or y >= S.h or isHole(x, y): return false
	return not isWall(roomAt(x, y), x, y)
func walk(x, y) -> bool:
	return walk0(x, y) and not blk().has(int(y) * S.w + int(x))

# room id grid cache for BFS speed
var _rgrid: PackedInt32Array
var _rgrid_sig = ""
func _room_grid() -> PackedInt32Array:
	var sig = str(S.w, "x", S.h, ":", S.rooms.size(), ":", S.nid)
	if sig == _rgrid_sig and _rgrid.size() == S.w * S.h: return _rgrid
	_rgrid = PackedInt32Array(); _rgrid.resize(S.w * S.h); _rgrid.fill(-1)
	for k in S.rooms.size():
		var r = S.rooms[k]
		for y in range(r.y, r.y + r.h):
			for x in range(r.x, r.x + r.w):
				if x >= 0 and y >= 0 and x < S.w and y < S.h and _rgrid[y * S.w + x] < 0: _rgrid[y * S.w + x] = k
	_rgrid_sig = sig
	return _rgrid

func path(sx, sy, tx, ty) -> Variant:
	sx = int(round(sx)); sy = int(round(sy)); tx = int(tx); ty = int(ty)
	if sx == tx and sy == ty: return []
	var W: int = S.w
	var H: int = S.h
	if sx < 0 or sy < 0 or sx >= W or sy >= H: return null
	var rg = _room_grid()
	var prev = PackedInt32Array(); prev.resize(W * H); prev.fill(-1)
	var q = PackedInt32Array([sy * W + sx])
	prev[q[0]] = q[0]
	var B = blk()
	var i = 0
	while i < q.size():
		var c: int = q[i]; i += 1
		var x: int = c % W
		var y: int = c / W
		if x == tx and y == ty:
			var p = []
			var k = c
			while k != q[0]:
				p.append({"x": k % W, "y": k / W})
				k = prev[k]
			p.reverse()
			return p
		for d in DIRS:
			var nx: int = x + d[0]
			var ny: int = y + d[1]
			if nx < 0 or ny < 0 or nx >= W or ny >= H: continue
			var n: int = ny * W + nx
			if prev[n] >= 0: continue
			var ok: bool
			if nx == tx and ny == ty: ok = walk0(nx, ny)
			else: ok = walk0(nx, ny) and not B.has(n)
			if not ok: continue
			var ia: int = rg[c]
			var ib: int = rg[n]
			if ia != ib:
				var ra = S.rooms[ia] if ia >= 0 else null
				var rb = S.rooms[ib] if ib >= 0 else null
				if not ((ra != null and ra.door.x == x and ra.door.y == y) or (rb != null and rb.door.x == nx and rb.door.y == ny)): continue
			prev[n] = c
			q.append(n)
	return null

func doorOut(r) -> Dictionary:
	var d = DIRS[int(r.side)]
	return {"x": r.door.x + d[0], "y": r.door.y + d[1]}

func makeRoom(type: String, x: int, y: int, w: int, h: int, side: int) -> Dictionary:
	var r = {"id": S.nid, "type": type, "x": x, "y": y, "w": w, "h": h, "side": side, "staff": null, "queue": [], "busy": null, "cond": 100, "uses": 0}
	S.nid += 1
	placeDoor(r)
	var l = layout(r)
	r.bad = l == null
	r.it = l.items if l != null else []
	r.sp = l.sp if l != null else {}
	return r

func placeDoor(r) -> void:
	var mx: int = r.x + int(floor(r.w / 2.0))
	var my: int = r.y + int(floor(r.h / 2.0))
	r.door = [{"x": mx, "y": r.y + r.h - 1}, {"x": r.x + r.w - 1, "y": my}, {"x": mx, "y": r.y}, {"x": r.x, "y": my}][int(r.side)]

func inner(r) -> Dictionary: return {"x": r.x + 1, "y": r.y + 1, "w": r.w - 2, "h": r.h - 2}

func items_cover(x, y) -> bool:
	for i in S.items:
		for t in tilesOf(i.x, i.y, i.fp if i.get("fp") != null else fpOf(i.type)):
			if t[0] == x and t[1] == y: return true
	return false

func validRoom(g: Dictionary) -> Variant:
	if g.x < 0 or g.y < 0 or g.x + g.w > S.w or g.y + g.h > S.h - 1: return "За пределами"
	for y in range(g.y, g.y + g.h):
		for x in range(g.x, g.x + g.w):
			if isHole(x, y): return "Нельзя строить здесь"
			if roomAt(x, y): return "Пересечение"
			if items_cover(x, y): return "Мешают предметы"
	var t = makeRoom(g.type, g.x, g.y, g.w, g.h, g.side)
	S.nid -= 1
	if t.bad: return "Мебель не помещается"
	var o = doorOut(t)
	if not walk(o.x, o.y) or roomAt(o.x, o.y): return "Дверь упирается"
	S.rooms.append(t); invBlk()
	var ok = true
	for r in S.rooms:
		var d = doorOut(r)
		if path(S.ent.x, S.ent.y, d.x, d.y) == null and not (d.x == S.ent.x and d.y == S.ent.y): ok = false
	S.rooms.pop_back(); invBlk()
	return null if ok else "Перекрывает проход"

# ---------- staff ----------
func cand_new(k: String) -> Dictionary:
	var sk = ri(15, 90)
	return {"name": pname(), "skill": sk, "salary": int(round(D.staff[k].base * (0.6 + sk / 100.0) / 10.0)) * 10}
func genCands() -> void:
	S.cands = {}
	for k in D.staff:
		S.cands[k] = []
		for i in 3: S.cands[k].append(cand_new(k))

func hire(type: String, i: int) -> Variant:
	var c = S.cands[type][i]
	var s = {"id": S.nid, "type": type, "name": c.name, "skill": c.skill, "salary": c.salary, "x": float(S.ent.x), "y": float(S.ent.y), "path": [], "state": "idle", "room": null, "fat": 0.0, "task": null, "t": 0.0, "dir": 1, "vs": null, "oa": null}
	S.nid += 1
	S.staff.append(s)
	S.cands[type].remove_at(i)
	S.cands[type].append(cand_new(type))
	msg(D.staff[type].name + " " + s.name + " принят(а) на работу")
	snd("click")
	return s

func fire(id) -> void:
	var s = staff_by_id(id)
	if s == null: return
	var r = room_by_id(s.room)
	if r: r.staff = null
	clearSeat(s)
	S.staff.erase(s)
	msg(s.name + " уволен(а)")

func staffReady(r) -> bool:
	if not drm(r.type).get("staff"): return true
	var s = staff_by_id(r.staff)
	if drm(r.type).get("machine") and r.cond <= 20: return false
	return s != null and s.state == "work" and not (s.vs and s.vs.ph != "sat") and s.path.is_empty()

func eff(s) -> float:
	return (0.5 + s.skill / 100.0) * (1.0 - s.fat / 250.0)

# ---------- movement ----------
func goTo(e, x, y) -> bool:
	var p = path(e.x, e.y, x, y)
	if p == null:
		e.path = []
		return false
	e.path = p
	return true

func move(e, dt: float, sp := 2.2) -> bool:
	if e.path.is_empty(): return true
	var n = e.path[0]
	var dx: float = n.x - e.x
	var dy: float = n.y - e.y
	var d = hyp(dx, dy)
	var st = sp * dt
	if absf(dx) + absf(dy) > .001: e.dir = (0 if dx > 0 else 2) if absf(dx) >= absf(dy) else (1 if dy > 0 else 3)
	if d <= st:
		e.x = float(n.x); e.y = float(n.y)
		e.path.pop_front()
		return e.path.is_empty()
	e.x += dx / d * st
	e.y += dy / d * st
	return false

# ---------- patients ----------
func spawnPatient() -> Variant:
	var ds0: Array = L().diseases
	var ds1 = []
	for z in ds0:
		if not roomLocked(D.dis[z].cure): ds1.append(z)
	var ds: Array = ds1 if ds1.size() else ds0
	var dz = pick(ds)
	var p = {"id": S.nid, "name": pname(), "dis": dz, "x": float(S.ent.x), "y": float(S.ent.y), "path": [], "state": "seek", "need": "reception", "health": 100.0, "pat": 100.0, "cert": 0.0, "known": false, "wait": 0.0, "room": null, "t": 0.0, "thought": null, "hue": ri(0, 360), "wcDone": rand() < .55, "wcAt": rnd(45, 120), "dir": 1, "vs": null, "oa": null, "wantSeat": null}
	S.nid += 1
	S.pats.append(p)
	snd("arrive")
	return p

func comfortAt(x, y) -> float:
	var c = 0.0
	for i in S.items:
		if absf(i.x - x) + absf(i.y - y) <= 3:
			var d = D.items[i.type]
			c += gnum(d, "comfort") * (0 if i.type == "plant" and gnum(i, "water", 100) < 30 else 1) + gnum(d, "warm")
	if first_room("toilet") != null: c += 2
	return minf(c, 8)

func leave(p, why, rep := 0.0) -> void:
	unqueue(p)
	p.wash = false
	p.state = "leave"
	p.thought = why
	if S.get("lvw") == null: S.lvw = {}
	var kk := str(why) + ":" + str(p.get("need"))
	S.lvw[kk] = gnum(S.lvw, kk, 0) + 1
	S.rep = maxf(0, S.rep - rep)
	goTo(p, S.ent.x, S.ent.y)

func unqueue(p) -> void:
	for q in S.rooms:
		if q.type == "toilet" and q.busy == p.id: q.busy = null
	p.wantSeat = null
	releaseBench(p)
	var r = room_by_id(p.room)
	if r:
		r.queue.erase(p.id)
		if r.busy == p.id: r.busy = null
	p.room = null

func waitSpot(r, p) -> Dictionary:
	var o = doorOut(r)
	var bs = []
	for i in S.items:
		if i.type == "bench" and absf(i.x - o.x) + absf(i.y - o.y) <= 7: bs.append(i)
	bs.sort_custom(func(a, b): return absf(a.x - o.x) + absf(a.y - o.y) < absf(b.x - o.x) + absf(b.y - o.y))
	for b in bs:
		if b.get("occ") == null: b.occ = [0, 0]
		for k in b.occ.size():
			if not b.occ[k] or pat_by_id(b.occ[k]) == null:
				b.occ[k] = p.id
				return {"x": b.x + k, "y": b.y, "pose": "sit", "dir": 1, "seat": "bench", "bench": true, "slot": k}
	for k in 20:
		var x: int = o.x + ri(-2, 2)
		var y: int = o.y + ri(-2, 2)
		if walk(x, y) and not roomAt(x, y): return {"x": x, "y": y, "pose": "stand", "dir": ri(0, 3)}
	return {"x": o.x, "y": o.y, "pose": "stand", "dir": 1}

func rCap(_r) -> float: return 1.0
func dirty_ok(p) -> bool:
	for i in S.items:
		if i.type == "bin" and absf(i.x - p.x) + absf(i.y - p.y) < 4: return false
	return true

func updPatient(p, dt: float) -> void:
	var dz = D.dis[p.dis]
	if p.state == "dead":
		p.t += dt
		return
	if p.state == "vip":
		updVip(p, dt)
		return
	if p.get("inf") and S.get("epi") and rand() < dt * .05:
		for q in S.pats:
			if not q.get("inf") and not q.get("immune") and not q.get("vip") and q.state != "dead" and absf(q.x - p.x) + absf(q.y - p.y) < 1.6:
				q.inf = true
				break
	if p.state != "leave":
		p.health -= dt * 0.12 * (0.5 + dz.diff) * gnum(L(), "decay", 1) * (0.65 if icuOn() else 1.0)
		if p.health <= 0:
			die(p, "decay")
			return
	if rand() < dt * 0.004 and not roomAt(int(round(p.x)), int(round(p.y))) and dirty_ok(p):
		S.litter.append({"x": p.x + rnd(-.3, .3), "y": p.y + rnd(-.3, .3)})
	if p.state == "seek" or p.state == "queue":
		var c = comfortAt(round(p.x), round(p.y))
		p.pat -= dt * patRate(p, c, dt)
		if p.pat <= 0:
			patLeave(p)
			return
		if rand() < dt * 0.003 and S.items.any(func(i): return i.type == "soda"):
			S.money += 15; S.earn += 15
	if p.vs:
		if p.vs.ph == "up": return
		if not ["queue", "treat", "wc2"].has(p.state):
			if p.vs.ph == "sat": leaveSeat(p)
			return
	match p.state:
		"seek": _pat_seek(p, dt)
		"queue": _pat_queue(p, dt)
		"enter":
			var r = room_by_id(p.room)
			if r == null:
				p.state = "seek"; return
			if move(p, dt):
				p.state = "treat"
				p.t = r_dur(p)
				p.tT = p.t
				var sp = spotPatient(r)
				p.dir = sp.dir if sp.get("dir") != null else p.dir
				takeSeat(p, sp)
		"treat":
			var r = room_by_id(p.room)
			if r == null:
				clearSeat(p); p.state = "seek"; return
			var s = staff_by_id(r.staff)
			if s and s.state != "work" and not (s.vs and s.vs.ph != "sat"): return
			if p.t > 0: p.t -= dt * (eff(s) if s else 1.0)
			if p.vs and p.vs.ph == "sat" and p.t <= seatT(p.vs.pose, .9): leaveSeat(p)
			if p.t <= 0:
				if p.vs: return
				finish(p, r, s)
		"wc1":
			var tr = room_by_id(p.get("wcRoom"))
			if tr == null:
				p.state = "seek"; p.thought = null; return
			var sp = tr.sp.patient
			if not p.get("wcGo"):
				if not goTo(p, sp.x, sp.y + 1) and not goTo(p, sp.x, sp.y):
					tr.busy = null; p.wcDone = true; p.state = "seek"; return
				p.wcGo = true
			if move(p, dt):
				p.dir = 3
				p.oa = {"act": "lid", "d": 3, "t": 0.0, "T": 1.0}
				p.state = "wcL"
		"wcL", "wcF", "wcD":
			var tr = room_by_id(p.get("wcRoom"))
			var wc = roomItem(tr.sp.patient, "wc") if tr else null
			if tr == null or p.oa == null:
				p.oa = null; p.state = "seek"; return
			var o = p.oa
			o.t += dt
			var q = minf(1.0, o.t / o.T)
			if wc:
				if p.state == "wcL": wc.lid = 0.0 if q < .4 else minf(3, (q - .4) / .6 * 3)
				elif p.state == "wcD": wc.lid = 0.0 if q > .6 else maxf(0, 3 - q / .6 * 3)
			if q < 1: return
			p.oa = null
			if p.state == "wcL":
				p.state = "wc2"
				p.t = 5 + rnd(0, 2)
				takeSeat(p, tr.sp.patient)
			elif p.state == "wcF":
				p.oa = {"act": "lid", "d": 3, "t": 0.0, "T": 1.0, "rev": true}
				p.state = "wcD"
			else:
				var w = tr.sp.get("wash") if tr.sp.get("wash") else tr.sp.patient
				goTo(p, w.x, w.y)
				p.state = "wc3"
		"wc2":
			var tr = room_by_id(p.get("wcRoom"))
			if tr == null:
				clearSeat(p); p.state = "seek"; return
			if p.vs and p.vs.ph == "down": return
			p.t -= dt
			if p.t <= 0:
				if p.vs:
					if p.vs.ph == "sat": leaveSeat(p)
					return
				var sp = tr.sp.patient
				p.x = float(sp.x); p.y = float(sp.y + 1)
				p.dir = 3
				p.oa = {"act": "flush", "d": 3, "t": 0.0, "T": .9}
				p.state = "wcF"
		"wc3":
			var tr = room_by_id(p.get("wcRoom"))
			if tr == null:
				p.state = "seek"; return
			if move(p, dt):
				var w = tr.sp.get("wash") if tr.sp.get("wash") else tr.sp.patient
				p.dir = w.dir if w.get("dir") != null else 3
				p.wash = true
				p.state = "wc4"
				p.t = 3.2
		"wc4":
			p.t -= dt
			if p.t <= 0:
				var tr = room_by_id(p.get("wcRoom"))
				if tr: tr.busy = null
				p.wash = false
				p.wcDone = true
				p.pat = minf(100, p.pat + 25)
				p.thought = null
				p.state = "seek"
		"leave":
			if move(p, dt):
				S.pats.erase(p)

func _pat_seek(p, dt: float) -> void:
	var rs = rooms_of(p.need)
	if rs.is_empty():
		p.thought = "❓"
		p.wait += dt
		move(p, dt)
		if p.path.is_empty() and rand() < .02:
			var x = ri(1, S.w - 2)
			var y = ri(S.h - 6, S.h - 2)
			if walk(x, y) and not roomAt(x, y): goTo(p, x, y)
		if p.wait > (60 if p.known else 40):
			msg(p.name + ": нет кабинета «" + drm(p.need).name + "» — отправлен(а) домой")
			S.sent += 1
			leave(p, "🏠", 3)
		return
	rs.sort_custom(func(a, b): return a.queue.size() / rCap(a) < b.queue.size() / rCap(b))
	var r = rs[0]
	if p.get("emg"):
		var k: int = r.queue.size()
		while k > 1:
			var q = pat_by_id(r.queue[k - 1])
			if q and q.get("emg"): break
			k -= 1
		r.queue.insert(maxi(mini(1, r.queue.size()), k), p.id)
	else: r.queue.append(p.id)
	p.room = r.id
	p.thought = null
	p.wait = 0.0
	var w = waitSpot(r, p)
	goTo(p, w.x, w.y)
	p.wantSeat = w if w.pose != "stand" else null
	if p.get("dir") == null: p.dir = 1
	p.state = "queue"

func _pat_queue(p, dt: float) -> void:
	var r = room_by_id(p.room)
	if r == null:
		clearSeat(p); p.state = "seek"; return
	if not p.vs:
		if p.path.size(): move(p, dt)
		elif p.wantSeat: takeSeat(p, p.wantSeat)
	p.wc = gnum(p, "wc", 0.0) + dt
	var tr = null
	if not p.wcDone:
		for q in S.rooms:
			if q.type == "toilet" and q.busy == null and not q.get("dirty") and roomLay(q).sp.get("patient") and absf(q.x - p.x) + absf(q.y - p.y) <= 16:
				tr = q; break
	if not p.wcDone and p.wc > p.wcAt and tr and r.queue[0] != p.id and r.queue.size() > 1 and (not p.vs or p.vs.ph == "sat"):
		tr.busy = p.id
		p.wcRoom = tr.id
		r.queue.erase(p.id)
		p.room = null
		releaseBench(p)
		p.wantSeat = null
		p.thought = "🚽"
		p.state = "wc1"
		p.wcGo = false
		return
	if r.queue.size() and r.queue[0] == p.id and r.busy == null and staffReady(r):
		p.wantSeat = null
		if p.vs:
			if p.vs.ph == "sat": leaveSeat(p)
			return
		if p.path.size(): return
		r.busy = p.id
		releaseBench(p)
		var sp = spotPatient(r)
		goTo(p, sp.x, sp.y)
		p.state = "enter"

const R_DUR := {"reception": 3, "gp": 8, "diag": 10, "lab": 7, "pharmacy": 6, "ward": 16, "psych": 12, "pump": 12, "cardio": 13, "surgery": 18, "xray": 9, "genetics": 14, "electro": 11, "reboot": 10, "inflate": 12, "derma": 13}
func r_dur(p) -> float: return float(R_DUR.get(p.need, 8))

func icuOn() -> bool:
	for r in S.rooms:
		if r.type == "icu" and staffReady(r): return true
	return false

func queue_len_of(t: String) -> int:
	var n = 0
	for r in S.rooms:
		if r.type == t: n += r.queue.size()
	return n

func finish(p, r, s) -> void:
	r.busy = null
	r.queue.erase(p.id)
	p.room = null
	var dz = D.dis[p.dis]
	var sk: float = s.skill if s else 50.0
	if p.need == "reception":
		p.need = "gp"; p.state = "seek"; return
	if p.need == "gp" or drm(p.need).get("diag"):
		if p.need == "gp": p.cert += 0.25 + sk / 250.0 - dz.diff * 0.15
		else:
			p.cert += drm(p.need).diag + sk / 400.0
			S.money += 100; S.earn += 100
		p.cert = minf(1.0, p.cert)
		if p.cert >= 0.8:
			p.known = true
			p.need = dz.cure
			msg(p.name + ": диагноз — " + dz.name)
			lowChanceCheck(p)
		elif p.need != "gp":
			p.need = "gp"
		else:
			var dr = []
			for t in ["diag", "lab"]:
				if first_room(t) != null: dr.append(t)
			if dr.size():
				dr.sort_custom(func(a, b): return queue_len_of(a) < queue_len_of(b))
				p.need = dr[0]
			elif p.cert >= 0.5:
				p.known = true; p.need = dz.cure; lowChanceCheck(p)
			else: p.cert += 0.15
		p.state = "seek"
		return
	if drm(r.type).get("machine"):
		var c0: float = r.cond
		r.cond -= ri(8, 15)
		if c0 <= 20 and r.cond <= 0: r.cond = 1
		r.uses += 1
		if r.cond <= 0:
			explode(r); return
	var ch = cureChance(p, s)
	if rand() < ch:
		p.healed = true
		S.money += dz.fee; S.earn += dz.fee
		S.cured += 1
		if p.get("emg") and S.get("em"): S.em.cured += 1
		p.inf = false
		S.rep = minf(1000, S.rep + 4)
		p.thought = "😊"
		snd("cash")
		msg(p.name + " вылечен(а) от «" + dz.name + "» +$" + str(dz.fee))
		events.append(["healed", p.id])
		leave(p, "😊", 0)
	elif rand() < gnum(L(), "failDeath", .5) and not (icuOn() and rand() < .5):
		msg("💀 Лечение «" + dz.name + "» не удалось: " + p.name + " не выжил(а)")
		die(p, "fail")
	else:
		msg("Лечение не помогло: " + p.name + " уходит недовольным")
		leave(p, "😞", 6)

func die(p, why := "x") -> void:
	clearSeat(p)
	p.path = []
	if S.get("dl") == null: S.dl = {}
	S.dl[why] = gnum(S.dl, why, 0) + 1
	dstat[str(why) + ":" + str(p.get("need")) + ":" + str(p.get("state"))] = dstat.get(str(why) + ":" + str(p.get("need")) + ":" + str(p.get("state")), 0) + 1
	unqueue(p)
	p.state = "dead"
	p.t = 0.0
	S.deaths += 1
	S.rep = maxf(0, S.rep - 15)
	snd("bad")
	events.append(["died", p.id])
	msg("☠ " + p.name + " скончался(ась)… Репутация падает")

func explode(r) -> void:
	snd("boom")
	events.append(["explode", r.id])
	msg("💥 Аппарат в «" + drm(r.type).name + "» взорвался!")
	S.rep = maxf(0, S.rep - 25)
	var rf = int(round(gnum(r, "cost", drm(r.type).cost) * .3))
	S.money += rf
	msg("Страховка: +$" + str(rf) + ". Пациенты эвакуированы")
	for p in S.pats:
		if p.room == r.id:
			clearSeat(p); unqueue(p); p.vs = null; p.state = "seek"
	var s = staff_by_id(r.staff)
	if s:
		clearSeat(s); s.room = null; s.state = "idle"
	S.rooms.erase(r)
	invBlk()

# ---------- staff AI ----------
func updStaff(s, dt: float) -> void:
	if s.type == "handyman":
		updHandy(s, dt); return
	if s.vs and s.vs.ph == "up": return
	var r = room_by_id(s.room)
	if r == null and s.room != null:
		clearSeat(s); s.room = null; s.state = "idle"
	if s.vs and s.state == "idle":
		if s.vs.ph == "sat": leaveSeat(s)
		return
	match s.state:
		"idle":
			var cand = []
			for q in S.rooms:
				if drm(q.type).get("staff") == s.type and q.staff == null and not (q.type == "research" and resDone()): cand.append(q)
			if cand.size():
				cand.sort_custom(func(a, b): return hyp(a.x - s.x, a.y - s.y) < hyp(b.x - s.x, b.y - s.y))
				r = cand[0]
				r.staff = s.id
				s.room = r.id
				var p = spotStaff(r)
				goTo(s, p.x, p.y)
				s.state = "goto"
			else:
				move(s, dt)
				if s.path.is_empty() and rand() < .01:
					var x = ri(1, S.w - 2)
					var y = ri(1, S.h - 2)
					if walk(x, y) and not roomAt(x, y): goTo(s, x, y)
		"goto":
			if move(s, dt):
				s.state = "work"
				var rr = r if r else room_by_id(s.room)
				var p = spotStaff(rr) if rr else {"x": s.x, "y": s.y, "dir": 1, "pose": "stand"}
				s.dir = p.dir if p.get("dir") != null else 1
				takeSeat(s, p)
		"work":
			s.fat = minf(100, s.fat + dt * (0.5 if r and r.busy != null else 0.15))
			var sr = first_room("staffroom")
			if s.fat >= 90 and sr and r and r.busy == null:
				if s.vs:
					if s.vs.ph == "sat": leaveSeat(s)
					return
				var cm = null
				for t in sr.get("it", []):
					if t.k == "coffee": cm = t; break
				handOver(s, r)
				if cm and not S.staff.any(func(o): return o != s and (o.state == "tocoffee" or o.state == "coffee")):
					goTo(s, cm.x, cm.y + 1)
					s.state = "tocoffee"
				else:
					var p = restSpot(sr, s)
					goTo(s, p.x, p.y)
					s.state = "torest"
		"tocoffee":
			var sr = first_room("staffroom")
			if sr == null:
				s.state = "idle"; return
			if move(s, dt):
				s.dir = 3
				s.oa = {"act": "coffee", "d": 3, "t": 0.0, "T": 3.2}
				s.state = "coffee"
		"coffee":
			var sr = first_room("staffroom")
			if s.oa == null: s.oa = {"act": "coffee", "d": 3, "t": 0.0, "T": 3.2}
			s.oa.t += dt
			s.fat = maxf(0, s.fat - dt * 4)
			if sr == null:
				s.oa = null; s.state = "idle"; return
			if s.oa.t >= s.oa.T:
				s.oa = null
				var p = restSpot(sr, s)
				goTo(s, p.x, p.y)
				s.state = "torest"
		"torest":
			var sr = first_room("staffroom")
			if sr == null:
				s.state = "idle"; return
			if move(s, dt):
				s.state = "rest"
				s.t = 0.0
				takeSeat(s, restSpot(sr, s))
		"rest":
			if s.vs and s.vs.ph == "down": return
			s.fat = maxf(0, s.fat - dt * 8 * v24Spd(rCap(first_room("staffroom"))))
			if s.fat <= 0:
				if s.vs:
					if s.vs.ph == "sat": leaveSeat(s)
					return
				s.restKey = null
				if r:
					var p = spotStaff(r)
					goTo(s, p.x, p.y)
					s.state = "goto"
				else: s.state = "idle"

# 1.0.0: where a janitor stands to clean a toilet (the tile in front of the bowl, like a visitor)
func wcCleanSpot(r) -> Variant:
	var sp = r.get("sp").get("patient") if r.get("sp") else null
	if sp == null: return null
	if walk(sp.x, sp.y + 1): return {"x": int(sp.x), "y": int(sp.y) + 1}
	return {"x": int(sp.x), "y": int(sp.y)}

func task_taken(o) -> bool:
	for h in S.staff:
		if h.get("task") and is_same(h.task.o, o): return true
	return false

func updHandy(s, dt: float) -> void:
	match s.state:
		"idle":
			# lambdas capture locals by value in GDScript -> keep the running best in a shared dict
			var acc = {"best": null, "bd": 1e9}
			var cons = func(x, y, k, o):
				var d: float = hyp(x - s.x, y - s.y) + (-80.0 if k == "fix" else (-40.0 if k == "wc" else 0.0))
				if d < acc.bd:
					acc.bd = d; acc.best = {"k": k, "o": o, "x": x, "y": y}
			for r in S.rooms:
				if drm(r.type).get("machine") and r.cond < 70 and not S.staff.any(func(h): return h.get("task") and h.task.k == "fix" and h.task.o == r.id):
					var q = spotStaff(r)
					cons.call(q.x, q.y, "fix", r.id)
			for l in S.litter:
				if not task_taken(l): cons.call(int(round(l.x)), int(round(l.y)), "clean", l)
			# 1.0.0: a dirty toilet (after a diarrhea patient) is cleaned before ordinary litter
			for r in S.rooms:
				if r.type == "toilet" and r.get("dirty") and not task_taken(r):
					var wq = wcCleanSpot(r)
					if wq: cons.call(wq.x, wq.y, "wc", r)
			for it in S.items:
				if it.type == "plant" and gnum(it, "water", 100) < 50 and not task_taken(it): cons.call(it.x, it.y, "water", it)
			var best = acc.best
			if best and goTo(s, best.x, best.y):
				s.task = best
				s.state = "goto"
			else:
				move(s, dt)
				if s.path.is_empty() and rand() < .01:
					var x = ri(1, S.w - 2)
					var y = ri(1, S.h - 2)
					if walk(x, y) and not roomAt(x, y): goTo(s, x, y)
		"goto":
			if move(s, dt):
				s.state = "do"
				s.t = 4.0 if s.task.k == "fix" else (3.0 if s.task.k == "wc" else 1.5)
		"do":
			s.t -= dt * eff(s)
			if s.t <= 0:
				var k = s.task
				if k.k == "fix":
					var r = room_by_id(k.o)
					if r: r.cond = 100
				elif k.k == "clean": S.litter.erase(k.o)
				elif k.k == "wc": k.o.dirty = false
				else: k.o.water = 100.0
				s.task = null
				s.state = "idle"
				s.fat = minf(100, s.fat + 3)

# ---------- world loop ----------
func update(dt: float) -> void:
	S.t += dt
	var nd = int(floor(S.t / DAY))
	if nd != S.day:
		S.day = nd
		onDay()
	S.spawnT -= dt
	if S.spawnT <= 0:
		S.spawnT = L().spawnEvery / (0.5 + S.rep / 1000.0) * rnd(.6, 1.4)
		spawnPatient()
	for it in S.items:
		if it.type == "plant": it.water = maxf(0, gnum(it, "water", 100) - dt * 0.15)
	for p in S.pats.duplicate(): updPatient(p, dt)
	S.pats = S.pats.filter(func(p): return not (p.state == "dead" and p.t > 3))
	for s in S.staff.duplicate(): updStaff(s, dt)
	for e in S.pats: tickVs(e, dt)
	for e in S.staff: tickVs(e, dt)
	tickDoors(dt)
	mechTick(dt)
	checkEnd()

func onDay() -> void:
	mechDay()
	v11Day()
	v11Day2()
	v12Day()
	if S.litter.size() > 15: S.rep = maxf(0, S.rep - 2)
	if S.day % MONTH_DAYS == 0:
		var sal: int = S.rooms.size() * 50
		for s in S.staff: sal += int(s.salary)
		S.money -= sal
		msg("📆 Новый месяц: зарплаты и содержание −$" + str(sal))
		snd("pa")
		genCands()
		events.append(["autosave", null])

func checkEnd() -> void:
	if S.won or S.lost: return
	var g = L().goals
	var l = L().lose
	if S.cured >= g.cured and netCash() >= g.money and S.rep >= g.rep and (not g.get("value") or hospValue() >= g.value):
		S.won = true
		speed = 0
		snd("win")
		events.append(["won", S.lv])
	elif gnum(S, "bk", 0) >= MONTH_DAYS * 2 or S.deaths >= l.deaths or S.rep < l.rep:
		S.lost = true
		speed = 0
		snd("bad")
		var why = "Больница обанкротилась: 2 месяца с долгом больше $10 000." if gnum(S, "bk", 0) >= MONTH_DAYS * 2 else ("Слишком много смертей." if S.deaths >= l.deaths else "Репутация упала ниже плинтуса.")
		events.append(["lost", why])

# ---------- hooks implemented by patch layers ----------
func mechInit() -> void: pass
func mechTick(_dt: float) -> void: pass
func mechDay() -> void: pass
func v11Day() -> void: pass
func v11Day2() -> void: pass
func v12Day() -> void: pass
func roomLocked(_t) -> bool: return false
func resDone() -> bool: return false
func hospValue() -> float: return 0.0
func netCash() -> float: return S.money
func updVip(_p, _dt: float) -> void: pass
func patRate(_p, c, _dt) -> float: return 0.35 * (1 - c / 12.0)
func patLeave(p) -> void:
	msg(p.name + " ушёл(ла), не дождавшись"); leave(p, "😠", 5); snd("bad")
func lowChanceCheck(_p) -> void: pass
func cureChance(_p, _s = null) -> float: return 0.8
func handOver(_s, _r) -> void: pass
func v24Spd(_c) -> float: return 1.0
func seatT(pose, def: float) -> float: return def
func roomLay(r) -> Variant: return r
func layout(_r) -> Variant: return {"items": [], "sp": {}}
func tilesOf(x, y, fp) -> Array:
	var o = []
	var w: int = fp[0] if fp else 1
	var h: int = fp[1] if fp else 1
	for dy in h:
		for dx in w: o.append([int(x) + dx, int(y) + dy])
	return o
func fpOf(_t) -> Array: return [1, 1]
func spotPatient(r) -> Dictionary: return {"x": r.door.x, "y": r.door.y, "pose": "stand", "dir": 1}
func spotStaff(r) -> Dictionary: return {"x": r.door.x, "y": r.door.y, "pose": "stand", "dir": 1}
func restSpot(sr, _me) -> Dictionary: return spotStaff(sr)
func takeSeat(_e, _sp) -> void: pass
func leaveSeat(_e) -> void: pass
func clearSeat(_e) -> void: pass
func releaseBench(_p) -> void: pass
func roomItem(_sp, _k) -> Variant: return null
func tickVs(_e, _dt: float) -> void: pass
func tickDoors(_dt: float) -> void: pass

# ---------- player actions (UI layer calls these) ----------
func roomBuildCost(g: Dictionary) -> int:
	var d = drm(g.type)
	return int(d.cost + (g.w * g.h - (d.min[0] + 2) * (d.min[1] + 2)) * 30)

func gsz_clamp(g: Dictionary, dw: int, dh: int) -> void:
	var m = drm(g.type).min
	g.w = maxi(m[0] + 2, mini(12, g.w + dw))
	g.h = maxi(m[1] + 2, mini(12, g.h + dh))

# gok(): returns null on success or error string
func buildRoom(g: Dictionary) -> Variant:
	var bad = "не исследовано" if roomLocked(g.type) else validRoom(g)
	if bad:
		msg("Нельзя: " + bad); snd("bad"); return bad
	var cost = roomBuildCost(g)
	if S.money < cost:
		msg("Недостаточно денег"); return "Недостаточно денег"
	S.money -= cost
	var nr = makeRoom(g.type, g.x, g.y, g.w, g.h, g.side)
	nr.cost = cost
	S.rooms.append(nr)
	invBlk()
	snd("build")
	var d = drm(g.type)
	msg("Построено: " + d.name + ((" — наймите: " + D.staff[d.staff].name) if d.get("staff") else ""))
	for p in S.pats:
		if p.state == "queue" or p.state == "seek": p.path = []
	after_build(nr)
	return null

func after_build(_r) -> void: pass

func paths_ok() -> bool:
	for r in S.rooms:
		var o = doorOut(r)
		if path(S.ent.x, S.ent.y, o.x, o.y) == null and not (o.x == S.ent.x and o.y == S.ent.y): return false
	return true

func placeItem(type: String, x: int, y: int, _dir = null) -> Variant:
	var d = D.items[type]
	var fp = fpOf(type)
	for t in tilesOf(x, y, fp):
		var tx: int = t[0]; var ty: int = t[1]
		if tx < 0 or ty < 0 or tx >= S.w or ty >= S.h - 1 or isHole(tx, ty) or roomAt(tx, ty) or blk().has(ty * S.w + tx):
			msg("Сюда нельзя"); snd("bad"); return null
	if S.money < d.cost:
		msg("Недостаточно денег"); return null
	var it = {"type": type, "x": x, "y": y, "fp": fp, "water": 100.0}
	if type == "bench": it.occ = [0, 0]
	S.items.append(it)
	invBlk()
	if not paths_ok():
		S.items.pop_back(); invBlk()
		msg("Это перекроет проход"); snd("bad"); return null
	S.money -= d.cost
	snd("build")
	return it

func sellRoom(id) -> void:
	var r = room_by_id(id)
	if r == null: return
	var o = doorOut(r)
	for p in S.pats:
		if p.room == r.id or p.get("wcRoom") == r.id:
			clearSeat(p); unqueue(p); p.state = "seek"
			p.x = float(o.x); p.y = float(o.y); p.path = []
	var s = staff_by_id(r.staff)
	if s:
		clearSeat(s); s.room = null; s.state = "idle"
		s.x = float(o.x); s.y = float(o.y); s.path = []
	for s2 in S.staff:
		if roomAt(int(round(s2.x)), int(round(s2.y))) == r:
			clearSeat(s2)
			s2.x = float(o.x); s2.y = float(o.y); s2.path = []
			if ["rest", "torest", "coffee", "tocoffee"].has(s2.state):
				s2.oa = null; s2.state = "idle"
	S.money += int(round(gnum(r, "cost", drm(r.type).cost) / 2.0))
	S.rooms.erase(r)
	invBlk()
	msg("Кабинет продан")

func leavePat(id) -> void:
	var p = pat_by_id(id)
	if p:
		if p.get("inf") and S.get("epi"):
			S.money -= 1500
			S.rep = maxf(0, S.rep - 8)
			msg("🦠 Заразного отправили домой: штраф −$1500"); snd("bad")
		S.sent += 1
		leave(p, "🏠", 2)

func vacc(id) -> void:
	var p = pat_by_id(id)
	if p == null: return
	if S.money < 200:
		msg("Недостаточно денег"); return
	S.money -= 200
	p.inf = false; p.immune = true
	msg("💉 " + p.name + " вакцинирован(а)")

# ---------- save/load (JSON compatible with 45.x {S, v:1}) ----------
func save_json() -> String:
	return JSON.stringify({"S": S, "v": 1})

func load_state(st: Dictionary) -> void:
	S = st
	fix_ints()
	if S.get("mt") == null: mechInit()
	invBlk()
	for r in S.rooms:
		if r.get("sp") == null or r.get("it") == null:
			var l = layout(r)
			r.it = l.items if l != null else []
			r.sp = l.sp if l != null else {}
	for e in S.pats + S.staff:
		e.vs = null; e.path = []; e.wash = false
		if ["queue", "enter", "treat", "wc1", "wc2", "wc3", "wc4", "wcL", "wcF", "wcD"].has(e.state):
			e.oa = null; e.state = "seek"; e.room = null; e.wantSeat = null
	for b in S.items:
		if b.get("occ") != null: b.occ = [0, 0]
	for r in S.rooms:
		r.queue = []; r.busy = null
	for s in S.staff:
		if s.state == "coffee" or s.state == "tocoffee": s.oa = null
		if ["work", "goto", "torest", "rest", "coffee", "tocoffee"].has(s.state):
			s.state = "goto"; s.restKey = null
		var r = room_by_id(s.room)
		if r and s.type != "handyman":
			var p = spotStaff(r)
			goTo(s, p.x, p.y)
	for s in S.staff:
		if s.type == "handyman":
			s.task = null; s.state = "idle"
	after_load()
	msg("📂 Игра загружена")

func after_load() -> void: pass

const INT_KEYS := ["id", "lv", "w", "h", "x", "y", "nid", "day", "side", "room", "staff", "busy", "cured", "deaths", "sent", "dir", "wcRoom", "slot"]
# JSON numbers come back as float; ids/coords must be int for == and dictionary keys
func fix_ints(o = null) -> void:
	if o == null: o = S
	if o is Dictionary:
		for k in o.keys():
			var v = o[k]
			if v is float and INT_KEYS.has(k) and v == floor(v): o[k] = int(v)
			elif v is Dictionary or v is Array: fix_ints(v)
			if k == "queue" and v is Array:
				for i in v.size():
					if v[i] is float: v[i] = int(v[i])
			if k == "occ" and v is Array:
				for i in v.size():
					if v[i] is float: v[i] = int(v[i])
	elif o is Array:
		for v in o:
			if v is Dictionary or v is Array: fix_ints(v)
