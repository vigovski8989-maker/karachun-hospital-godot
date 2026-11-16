# v41.js: relief of tired staff, stuck-seat watchdog, corridor item auto-rotation, rotated bench seats
class_name Sim41
extends Sim25

const V41F := [[1, 0], [0, 1], [-1, 0], [0, -1]]
const V41RN := ["→ вправо", "↓ вниз", "← влево", "↑ вверх"]

func v41Sub(s) -> Variant:
	for o in S.staff:
		if not is_same(o, s) and o.type == s.type and o.room == null and o.state == "idle" and not o.get("vs") and not o.get("goRest"):
			return o
	return null

func v41Relieve(s, r) -> bool:
	var sub = v41Sub(s)
	if sub == null: return false
	r.staff = sub.id
	sub.room = r.id
	var p = spotStaff(r)
	goTo(sub, p.x, p.y)
	sub.state = "goto"
	s.room = null; s.cover = false; s.goRest = true; s.state = "work"
	if S.get("v41") == null: S.v41 = {}
	S.v41.reliefs = gnum(S.v41, "reliefs", 0) + 1
	msg("🔄 " + sub.name + " сменяет уставшего " + s.name + " в «" + drm(r.type).name + "»")
	return true

func finish(p, r, s) -> void:
	super.finish(p, r, s)
	var w = staff_by_id(r.staff)
	if w and w.fat >= 75 and w.state == "work": v41Relieve(w, r)

func updStaff(s, dt: float) -> void:
	if s.get("goRest"):
		if s.vs:
			if s.vs.ph == "sat": leaveSeat(s)
			return
		s.goRest = false
		var sr = first_room("staffroom")
		if sr:
			var q = restSpot(sr, s)
			goTo(s, q.x, q.y)
			s.state = "torest"
		else: s.state = "idle"
		return
	if s.state == "idle" and s.vs and s.vs.ph != "sat":
		s.vst = gnum(s, "vst", 0.0) + dt
		if s.vst > 6:
			clearSeat(s); s.vst = 0.0
	else: s.vst = 0.0
	super.updStaff(s, dt)
	if s.state == "work" and s.room != null and s.fat >= 92:
		var r = room_by_id(s.room)
		if r and r.busy == null: v41Relieve(s, r)

func v41Blocked(tx, ty) -> int:
	if tx < 0 or ty < 0 or tx >= S.w or ty >= S.h - 1: return 3
	if isHole(tx, ty) or roomAt(tx, ty): return 3
	if items_cover(tx, ty): return 1
	return 0

func v41Fits(type, x, y, d) -> bool:
	for t in tilesOf(x, y, fpDir(type, d)):
		if v41Blocked(t[0], t[1]): return false
	return true

func v41AutoDir(type, x, y) -> Variant:
	var best = null
	var bs = -1
	for d in [1, 3, 0, 2]:
		if not v41Fits(type, x, y, d): continue
		var fp = fpDir(type, d)
		var f = V41F[d]
		var back = 0
		var front = 0
		var tl = tilesOf(x, y, fp)
		for t in tl:
			var bx: int = t[0] - f[0]; var by: int = t[1] - f[1]
			var nx: int = t[0] + f[0]; var ny: int = t[1] + f[1]
			var inB = tl.any(func(a): return a[0] == bx and a[1] == by)
			var inF = tl.any(func(a): return a[0] == nx and a[1] == ny)
			if not inB: back += v41Blocked(bx, by)
			if not inF and not v41Blocked(nx, ny): front += 1
		var sc = back * 2 + front
		if sc > bs:
			bs = sc; best = d
	return best

func placeItem(type: String, x: int, y: int, rot = null) -> Variant:
	var d0 = D.items[type]
	var dir = rot if rot != null else (ui.get("v41rot") if ui.get("v41rot") != null else v41AutoDir(type, x, y))
	if dir == null:
		msg("Сюда нельзя"); snd("bad"); return null
	var fp = fpDir(type, dir)
	for t in tilesOf(x, y, fp):
		var tx: int = t[0]; var ty: int = t[1]
		if tx < 0 or ty < 0 or tx >= S.w or ty >= S.h - 1 or isHole(tx, ty) or roomAt(tx, ty) or blk().has(ty * S.w + tx):
			msg("Сюда нельзя"); snd("bad"); return null
	if S.money < d0.cost:
		msg("Недостаточно денег"); return null
	var it = {"type": type, "x": x, "y": y, "fp": fp, "dir": dir, "water": 100.0}
	if type == "bench": it.occ = [0, 0]
	S.items.append(it)
	invBlk()
	if not paths_ok():
		S.items.pop_back(); invBlk()
		msg("Это перекроет проход"); snd("bad"); return null
	S.money -= d0.cost
	snd("build")
	return it

func v41Rot() -> void:
	var r = ui.get("v41rot")
	ui.v41rot = 1 if r == null else (0 if r == 1 else (3 if r == 0 else (2 if r == 3 else null)))
func v41RotLbl() -> String:
	return "🔄 Поворот: " + ("авто" if ui.get("v41rot") == null else V41RN[ui.v41rot])

func waitSpot(r, p) -> Dictionary:
	var s = super.waitSpot(r, p)
	if s.get("bench"):
		var b = null
		for i in S.items:
			if i.type == "bench" and i.get("occ") != null and i.occ.has(p.id): b = i; break
		if b and b.get("dir") != null:
			var k: int = s.slot
			if b.dir == 0 or b.dir == 2:
				s.x = b.x; s.y = b.y + k
			else:
				s.x = b.x + k; s.y = b.y
			s.dir = b.dir
	return s
