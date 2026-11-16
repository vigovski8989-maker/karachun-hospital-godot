# v17.js: cover staff, skills (library, courses, specializations), chief doctor, rival ranking, paid GP
class_name Sim17
extends Sim12

const COMP := {"doctor": ["nurse", "receptionist"], "nurse": ["receptionist"], "receptionist": [], "orderly": [], "handyman": []}
const SPEC := {"surgeon": {"n": "Хирург", "rooms": ["surgery", "transplant", "cardio"]}, "psych": {"n": "Психиатр", "rooms": ["psych", "electro", "reboot"]}, "diagn": {"n": "Диагност", "rooms": ["gp", "paygp", "diag", "xray"]}}
const COURSE := {"doctor": [2500, 6, 12], "nurse": [1500, 5, 12], "receptionist": [800, 4, 15], "orderly": [800, 4, 15], "handyman": [800, 4, 15]}
const RIVALS := ["Клиника «Добрый Пульс»", "Госпиталь им. Пилюлькина", "«Зелёная Таблетка»", "Медцентр «Сто Лет»", "Лечебница «Бодрячок»", "Клиника «Тише Едешь»", "«Белый Халат и Ко»", "Санаторий «Сопелька»"]
const RANK_MUL := [1.15, 1.07, 1, 0.95, 0.9]
const PAY_FEE := 300

func isNoCover(t) -> bool: return t == "chief" or t == "research" or t == "morgue" or t == "library"
func chiefRoom(): return first_room("chief")
func chiefOf() -> Variant:
	var r = chiefRoom()
	return staff_by_id(r.staff) if r and r.staff != null else null
func chiefK() -> float:
	var c = chiefOf()
	return 0.5 + c.skill / 200.0 if c else 0.0

func v17Init() -> void:
	if S.get("away") == null: S.away = []
	if S.get("v17") == null: S.v17 = {"covers": 0, "courses": 0, "read": 0.0}
	if S.get("rivals") == null:
		var lv: int = S.lv
		var rs = []
		var F = [0.62, 0.82, 1.0, 1.18]
		for i in 4: rs.append({"name": RIVALS[(lv * 3 + i) % RIVALS.size()], "f": F[i] * (0.95 + ((lv * 7 + i * 3) % 5) * 0.025)})
		S.rivals = rs

func canCover(s, t) -> bool:
	var need = drm(t).get("staff")
	return need != null and need != "" and (need == s.type or COMP.get(s.type, []).has(need)) and not isNoCover(t)

func handOver(s, r) -> void:
	if r == null or r.type == "chief": return
	for o in S.staff:
		if o != s and o.room == null and o.state == "idle" and not o.get("vs") and canCover(o, r.type):
			r.staff = null; s.room = null
			return

func releaseCover(s, r) -> void:
	clearSeat(s)
	s.room = null; s.cover = false; s.state = "idle"; s.path = []
	if r and r.staff == s.id: r.staff = null

func updStaff(s, dt: float) -> void:
	v17Init()
	if s.state == "read":
		v17Read(s, dt); return
	if s.state == "idle" and s.room == null and not s.get("vs") and s.type != "handyman":
		var own = S.rooms.any(func(r): return drm(r.type).get("staff") == s.type and r.staff == null and not (r.type == "research" and resDone()))
		if not own:
			var cov = null
			for r in S.rooms:
				if drm(r.type).get("staff") == s.type and r.staff != null and r.busy == null:
					var o = staff_by_id(r.staff)
					if o and o.get("cover") and o.state == "work" and o.type != s.type:
						cov = r; break
			if cov:
				var o = staff_by_id(cov.staff)
				releaseCover(o, cov)
				msg("🔄 " + s.name + " сменяет " + o.name + " в «" + drm(cov.type).name + "»")
			else:
				var c = S.rooms.filter(func(r): return r.staff == null and canCover(s, r.type) and drm(r.type).get("staff") != s.type and (r.queue.size() > 0 or drm(r.type).get("staff") == "receptionist"))
				if c.size():
					c.sort_custom(func(a, b): return a.queue.size() > b.queue.size())
					var r = c[0]
					r.staff = s.id; s.room = r.id; s.cover = true
					S.v17.covers += 1
					var p = spotStaff(r)
					goTo(s, p.x, p.y)
					s.state = "goto"
					msg("🔄 " + D.staff[s.type].name + " " + s.name + " подменяет в «" + drm(r.type).name + "»")
					return
				var lib = first_room("library")
				if lib and rand() < .02:
					var p = libSpot(lib, s)
					if p and goTo(s, p.x, p.y):
						s.state = "read"
						s.rd = {"ph": "go", "sp": p, "t": 0.0}
						return
	if s.get("cover") and s.room != null:
		var r = room_by_id(s.room)
		if r == null: s.cover = false
		elif drm(r.type).get("staff") == s.type: s.cover = false
	if s.room == null: s.cover = false
	super.updStaff(s, dt)
	if s.state == "work" and chiefOf() and s.fat > 0: s.fat = maxf(0, s.fat - dt * 0.1 * chiefK())
	if s.state == "rest" and first_room("library") != null:
		var mc = 1.0
		for r in rooms_of("library"): mc = maxf(mc, rCap(r))
		gainXp(s, dt * 0.04 * v24Spd(mc))

func gainXp(s, v: float) -> void:
	if s.skill >= 100: return
	v *= 1 + chiefK() * 0.5
	s.xp = gnum(s, "xp", 0.0) + v
	while s.xp >= 1 and s.skill < 100:
		s.xp -= 1
		s.skill += 1
		if int(s.skill) % 10 == 0: msg("📈 " + s.name + ": навык " + str(s.skill))

func libSpot(lib, me) -> Variant:
	roomLay(lib)
	for k in ["read1", "read2"]:
		var p = lib.sp.get(k)
		var key = str(lib.id) + k
		if p and not S.staff.any(func(o): return o != me and o.get("rd") and o.rd.get("k") == key):
			if me.get("rd"): me.rd.k = key
			else: me._rk = key
			var o: Dictionary = p.duplicate()
			o.k = k
			return o
	return null

func v17Read(s, dt: float) -> void:
	var lib = first_room("library")
	if lib == null or s.get("rd") == null:
		clearSeat(s); s.rd = null; s.state = "idle"; return
	if not s.rd.get("k"): s.rd.k = s.get("_rk")
	if s.rd.ph == "go":
		if move(s, dt):
			s.rd.ph = "in"
			s.dir = s.rd.sp.dir if s.rd.sp.get("dir") != null else 1
			takeSeat(s, s.rd.sp)
		return
	if s.vs and s.vs.ph != "sat" and s.vs.ph != "down": return
	s.rd.t += dt
	gainXp(s, dt * 0.12)
	S.v17.read += dt
	s.fat = maxf(0, s.fat - dt * 2)
	var need = S.rooms.any(func(r): return r.staff == null and canCover(s, r.type) and (drm(r.type).get("staff") == s.type or r.queue.size() > 0))
	if need or s.rd.t > DAY * 2:
		if s.vs and s.vs.ph == "sat":
			leaveSeat(s); return
		clearSeat(s)
		s.rd = null
		s.state = "idle"

func sendCourse(id, spec = null) -> bool:
	v17Init()
	var s = staff_by_id(id)
	if s == null: return false
	var c = COURSE[s.type]
	if S.money < c[0]:
		msg("Недостаточно денег на курсы"); return false
	S.money -= c[0]
	var r = room_by_id(s.room)
	if r and r.staff == s.id: r.staff = null
	clearSeat(s)
	s.room = null; s.cover = false; s.rd = null; s.state = "idle"; s.path = []
	S.staff.erase(s)
	S.away.append({"s": s, "back": S.day + c[1], "gain": c[2], "spec": spec})
	S.v17.courses += 1
	msg("🎓 " + s.name + " уехал(а) на курсы" + ((" «" + SPEC[spec].n + "»") if spec else "") + " на " + str(c[1]) + " дн. (−$" + str(c[0]) + ")")
	snd("cash")
	return true

func specCourse(id, k) -> void:
	var c = COURSE.doctor
	if S.money < c[0] * 2:
		msg("Недостаточно денег"); return
	S.money -= c[0]
	sendCourse(id, k)
	var a = S.away.back() if S.away.size() else null
	if a and a.s.id == id: a.back += 3

func courseBack() -> void:
	for a in S.away.duplicate():
		if S.day >= a.back:
			var s = a.s
			s.skill = mini(100, int(s.skill) + int(a.gain))
			if a.spec: s.spec = a.spec
			s.x = float(S.ent.x); s.y = float(S.ent.y)
			s.path = []; s.state = "idle"; s.room = null; s.fat = 0.0; s.vs = null
			S.staff.append(s)
			S.away.erase(a)
			msg("🎓 " + s.name + " вернулся(лась) с курсов: навык " + str(s.skill) + ((", специализация «" + SPEC[a.spec].n + "»") if a.spec else ""))

func cureChance(p, s = null) -> float:
	var c = super.cureChance(p, s)
	var dz = D.dis[p.dis]
	if s and s.get("spec") and SPEC[s.spec].rooms.has(dz.cure): c += 0.08
	if p.get("prem"): c += 0.06
	return maxf(.05, minf(.98, c))

func appointChief(id) -> void:
	var r = chiefRoom()
	if r == null: return
	var s = staff_by_id(id)
	if s == null: return
	var old = chiefOf()
	if old:
		clearSeat(old); old.room = null; old.state = "idle"; old.path = []
	var pr = room_by_id(s.room)
	if pr and pr.staff == s.id: pr.staff = null
	clearSeat(s)
	s.rd = null; s.cover = false
	r.staff = s.id; s.room = r.id
	var p = spotStaff(r)
	goTo(s, p.x, p.y)
	s.state = "goto"
	msg("👔 " + s.name + " назначен(а) главврачом")
	snd("win")

func dismissChief() -> void:
	var r = chiefRoom()
	var c = chiefOf()
	if c:
		clearSeat(c); c.room = null; c.state = "idle"; c.path = []
	if r: r.staff = null

func canStartRoom(t) -> bool:
	if (t == "chief" or t == "library") and first_room(t) != null:
		msg("Такой кабинет может быть только один"); snd("bad"); return false
	return true

func goalIdx() -> float:
	var g = L().goals
	return g.rep * 0.6 + g.cured * 1.5 + (gnum(g, "value", 0) if gnum(g, "value", 0) else g.money * 1.5) / 5000.0
func myIdx() -> int: return int(round(S.rep * 0.6 + S.cured * 1.5 + hospValue() / 5000.0))
func rivalIdx(r) -> int: return int(round(goalIdx() * r.f * minf(1.1, 0.5 + S.day / 650.0)))
func ranking() -> Array:
	v17Init()
	var a = []
	for r in S.rivals: a.append({"name": r.name, "v": rivalIdx(r)})
	a.append({"name": "⭐ Больница Карачун (вы)", "v": myIdx(), "me": 1})
	a.sort_custom(func(x, y): return x.v > y.v)
	return a
func myRank() -> int:
	var a = ranking()
	for i in a.size():
		if a[i].get("me"): return i + 1
	return 3

func crowdK() -> float: return 1.0

func spawnPatient() -> Variant:
	var p = super.spawnPatient()
	v17Init()
	var rk = myRank()
	var k: float = RANK_MUL[rk - 1] if rk - 1 < RANK_MUL.size() else 1.0
	k *= crowdK()
	S.spawnT /= k
	var pg = S.rooms.any(func(r): return r.type == "paygp" and r.staff != null)
	if p and pg and not p.get("vip") and rand() < 0.12 + 0.04 * (5 - rk): p.rich = true
	return p

func finish(p, r, s) -> void:
	if r.type == "paygp":
		p.need = "gp"
		p.prem = true
		super.finish(p, r, s)
		p.cert = minf(1, p.cert + 0.2)
		if not p.known and p.cert >= 0.8:
			p.known = true; p.need = D.dis[p.dis].cure; lowChanceCheck(p)
		if p.need == "gp": p.need = "paygp"
		S.money += PAY_FEE; S.earn += PAY_FEE
		S.v17.pay = gnum(S.v17, "pay", 0) + PAY_FEE
		S.rep = minf(1000, S.rep + 0.5)
		return
	var wasRec: bool = p.need == "reception"
	super.finish(p, r, s)
	if p.get("rich") and (wasRec or p.need == "gp") and S.rooms.any(func(q): return q.type == "paygp" and q.staff != null):
		p.need = "paygp"; p.thought = "💎"

func payRotate() -> void:
	for pr in S.rooms.filter(func(r): return r.type == "paygp" and r.staff != null and r.busy == null):
		var cur = staff_by_id(pr.staff)
		if cur == null or cur.state != "work": continue
		var best = null
		var bestr = null
		for b in S.staff:
			if b.type == "doctor" and b.state == "work" and b.room != null and not b.get("cover") and b.skill > cur.skill + 5:
				var br = room_by_id(b.room)
				if br and br.busy == null and not ["chief", "research", "paygp"].has(br.type) and (best == null or b.skill > best.skill):
					best = b; bestr = br
		if best:
			clearSeat(best); clearSeat(cur)
			pr.staff = best.id; best.room = pr.id
			bestr.staff = cur.id; cur.room = bestr.id
			var q = spotStaff(pr)
			goTo(best, q.x, q.y); best.state = "goto"
			q = spotStaff(bestr)
			goTo(cur, q.x, q.y); cur.state = "goto"
			msg("💎 " + best.name + " (навык " + str(best.skill) + ") переведён(а) в платный кабинет")

func onDay() -> void:
	super.onDay()
	v17Init()
	courseBack()
	payRotate()
	var c = chiefOf()
	if c:
		var k = chiefK()
		for s in S.staff:
			if s != c: gainXp(s, 0.15 * k)
		if S.day % MONTH_DAYS == 0:
			var tot = 0.0
			for s in S.staff: tot += s.salary
			var sv = int(round(tot * 0.08 * k))
			S.money += sv
			msg("👔 Главврач сэкономил на управлении: +$" + str(sv))
		if L().get("locked"): S.rp += 0.6 * k * DAY / 8.0
	if S.day % 10 == 5:
		var rk = myRank()
		if rk != S.v17.get("lastRank"):
			if S.v17.get("lastRank"): msg("🏆 Рейтинг больниц: " + ("поднялись" if rk < S.v17.lastRank else "опустились") + " на " + str(rk) + " место")
			S.v17.lastRank = rk

func chips() -> Array:
	var h = super.chips()
	v17Init()
	var rk = myRank()
	h.append(["🏆 " + str(rk) + "/5", "#2a7a3a" if rk <= 2 else ("#8a4a2a" if rk >= 4 else "#555")])
	var cv = S.staff.filter(func(s): return s.get("cover") and s.room != null).size()
	if cv: h.append(["🔄 подмена " + str(cv), "#356"])
	if S.away.size(): h.append(["🎓 " + str(S.away.size()), "#536"])
	if chiefOf(): h.append(["👔", "#654"])
	return h

func v17Bot() -> void:
	v17Init()
	var r = chiefRoom()
	if r and not chiefOf():
		var c = S.cands.get("doctor")
		if c and c.size():
			var bi = 0
			for i in c.size():
				if c[i].skill > c[bi].skill: bi = i
			hire("doctor", bi)
			appointChief(S.staff.back().id)
	if S.day % 25 == 0 and S.money > 60000:
		var cand = S.staff.filter(func(s): return s.type == "doctor" and s.skill < 70 and s.room != null)
		cand.sort_custom(func(a, b): return a.skill < b.skill)
		if cand.size():
			var s = cand[0]
			var sr = room_by_id(s.room)
			if sr and sr.busy == null and S.staff.any(func(o): return o != s and o.room == null and canCover(o, sr.type)): sendCourse(s.id)

func v12Bot() -> void:
	super.v12Bot()
	v17Bot()

func after_load() -> void:
	super.after_load()
	# 45.x saves keep the away staff objects inside S.away[].s; ints fixed by fix_ints
	v17Init()
