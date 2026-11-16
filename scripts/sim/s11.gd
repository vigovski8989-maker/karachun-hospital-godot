# v11.js: net cash, cure chance, low-chance policy, hand-over, bankruptcy, queue rebalance, warnings, tutorial
class_name Sim11
extends SimMech

const TUT_TEXT := [
	"1/7 Нажмите 🏗 Кабинеты → «Регистратура», поставьте её у входа и нажмите ✔",
	"2/7 Нажмите 👩‍⚕️ Нанять → регистратор. Он сам займёт стойку",
	"3/7 Постройте «Кабинет терапевта» — там ставят диагноз",
	"4/7 Наймите врача для кабинета терапевта",
	"5/7 Постройте «Аптеку» — там лечат большинство болезней",
	"6/7 Наймите медсестру для аптеки",
	"7/7 Постройте «Сканер-кабинет» и наймите второго врача — диагноз точнее, меньше смертей"]

func netCash() -> float: return S.money - gnum(S, "loan", 0)

func cureChance(p, s = null) -> float:
	var dz = D.dis[p.dis]
	var sk: float
	if s: sk = s.skill
	else:
		var b = bestSkill(drm(dz.cure).get("staff") if D.rooms.has(dz.cure) else null)
		sk = b if b else 50.0
	return maxf(.05, minf(.97, 0.55 + p.cert * 0.35 + sk / 400.0) - gnum(L(), "risk", 0) * (0.5 + dz.diff))

func bestSkill(t) -> float:
	var b = 0.0
	for s in S.staff:
		if s.type == t: b = maxf(b, s.skill)
	return b

func diagRooms() -> Array:
	var o = []
	for t in ["diag", "lab", "xray"]:
		if first_room(t) != null: o.append(t)
	return o

func lowChanceCheck(p) -> void:
	if p.get("force") or p.cert >= 0.99: return
	var mc: float = .6 if S.get("minCh") == null else S.minCh
	if cureChance(p) < mc:
		var dr = diagRooms()
		if dr.size():
			p.need = dr[int(floor(rand() * dr.size()))]
			p.thought = "🔍"

func treatNow(id) -> void:
	var p = pat_by_id(id)
	if p == null: return
	var dz = D.dis[p.dis]
	unqueue(p)
	p.known = true; p.force = true; p.need = dz.cure; p.state = "seek"
	msg(p.name + " → лечение сейчас (" + str(int(round(cureChance(p) * 100))) + "%)")

func moreDiag(id) -> void:
	var p = pat_by_id(id)
	if p == null: return
	var dr = diagRooms()
	if dr.is_empty():
		msg("Нет кабинетов диагностики"); return
	unqueue(p)
	p.force = false; p.need = dr[0]; p.state = "seek"
	msg(p.name + " → дообследование")

func handOver(s, r) -> void:
	if r == null: return
	for o in S.staff:
		if o != s and o.type == s.type and o.room == null and o.state == "idle":
			r.staff = null; s.room = null
			return

func v11Day() -> void:
	var d: int = S.day
	if S.money < -10000:
		S.bk = gnum(S, "bk", 0) + 1
		if S.bk == 1 or S.bk == MONTH_DAYS or S.bk == MONTH_DAYS * 2 - 5:
			msg("⚠ Долг больше $10 000! Банкротство через " + str(MONTH_DAYS * 2 - S.bk) + " дн."); snd("bad")
	else: S.bk = 0
	var by = {}
	for r in S.rooms:
		if not by.has(r.type): by[r.type] = []
		by[r.type].append(r)
	for t in by:
		var rs: Array = by[t]
		if rs.size() < 2: continue
		rs.sort_custom(func(a, b): return a.queue.size() / rCap(a) < b.queue.size() / rCap(b))
		var lo = rs[0]
		var hi = rs[rs.size() - 1]
		if hi.queue.size() / rCap(hi) - lo.queue.size() / rCap(lo) >= 3:
			var p = pat_by_id(hi.queue[hi.queue.size() - 1])
			if p and p.state == "queue" and not p.vs:
				unqueue(p); p.state = "seek"; p.room = null
	S.over = []
	for r in S.rooms:
		if r.queue.size() >= 6 * rCap(r): S.over.append(r.id)
	if S.over.size() and d % 3 == 0:
		var r = room_by_id(S.over[0])
		msg("⚠ Перегрузка: «" + drm(r.type).name + "», очередь " + str(r.queue.size()) + ". Постройте ещё один или наймите сменщика")

func resDone() -> bool:
	var lk = L().get("locked")
	if not lk: return false
	for k in lk:
		if not S.get("unl") or not S.unl.get(k): return false
	return true

func has_staff(t: String) -> bool: return S.staff.any(func(s): return s.type == t)

func v11Day2() -> void:
	var d: int = S.day
	if d % 4 == 1:
		if first_room("reception") == null: msg("⚠ Нет стойки регистрации — пациенты уходят! Постройте «Регистратура»")
		elif not has_staff("receptionist"): msg("⚠ Нет регистратора — наймите его")
		elif first_room("gp") == null: msg("⚠ Нет кабинета терапевта — пациентов некому осматривать")
	var lk = L().get("locked")
	if lk:
		if resDone():
			if not S.get("resMsg"):
				S.resMsg = 1
				msg("🔬 Всё исследовано! Лаборанты освобождены и пойдут в другие кабинеты")
				for r in S.rooms:
					if r.type == "research" and r.staff != null:
						var s = staff_by_id(r.staff)
						r.staff = null
						if s:
							clearSeat(s); s.room = null; s.state = "idle"
		elif d % 5 == 2 and not S.rooms.any(func(r): return r.type == "research" and r.staff != null):
			msg("🔬 Исследования стоят: " + ("в лаборатории нет сотрудника" if first_room("research") else "постройте исследовательский отдел"))
	if d % 5 == 3:
		var idle = idleStaff()
		if idle.size(): msg("👤 Без кабинета: " + str(idle.size()) + " сотр. — постройте кабинет или уволите лишних")
	for r in S.rooms:
		if drm(r.type).get("machine") and r.cond <= 20 and d % 3 == 0: msg("🔧 «" + drm(r.type).name + "» закрыт: износ " + str(int(r.cond)) + "%. Нужен разнорабочий")

func idleStaff() -> Array:
	return S.staff.filter(func(s): return s.type != "handyman" and s.room == null)

func tutStep() -> int:
	if S.lv != 0 or S.get("tutOff") or S.won or S.lost: return -1
	var c = [first_room("reception") != null, has_staff("receptionist"), first_room("gp") != null, has_staff("doctor"), first_room("pharmacy") != null, has_staff("nurse"), first_room("diag") != null and S.staff.filter(func(s): return s.type == "doctor").size() >= 2]
	for i in c.size():
		if not c[i]: return i
	S.tutOff = 1
	msg("🎓 Обучение пройдено! Дальше следите за целями (🎯) и очередями")
	return -1

# HUD chips (v11Hud) as array of [text, colorHex]
func chips() -> Array:
	var h = []
	var d: int = S.day
	if gnum(S, "loan", 0): h.append(["🏦 −$" + str(int(round(S.loan / 1000.0))) + "k", ""])
	if gnum(S, "bk", 0): h.append(["⚠ банкротство " + str(MONTH_DAYS * 2 - S.bk) + "д", "#a22"])
	var lk = L().get("locked")
	if lk and not resDone():
		var nx = null
		for k in lk:
			if not S.unl.get(k) and (nx == null or lk[k] < lk[nx]): nx = k
		h.append(["🔬 " + str(int(floor(S.rp))) + "/" + str(int(lk[nx])), ""])
	if S.get("em"): h.append(["🚑 " + str(S.em.cured) + "/" + str(S.em.n) + " · " + str(maxi(0, S.em.until - d)) + "д", "#a33"])
	if S.get("epi"):
		var n = S.pats.filter(func(p): return p.get("inf") and p.state != "dead").size()
		h.append(["🦠 " + str(n) + " · инсп. " + str(maxi(0, S.epi.until - d)) + "д", "#585"])
	if S.get("vip"):
		var v = S.vip
		var vp = null
		for p in S.pats:
			if p.get("vip") and p.state == "vip": vp = p
		if vp:
			var n = maxf(1, v.n)
			var q: float = gnum(v, "q", 0) / n / maxf(1, S.rooms.size())
			var lit: float = v.litter / n
			var m = "😠" if (q > 3 or lit > 8) else ("😐" if (q > 1.5 or lit > 3) else "😊")
			h.append(["🎩 VIP " + str(v.n) + "/" + str(v.n + vp.vt.size()) + " " + m, "#764"])
	if S.get("quake"): h.append(["🌋", "#a52"])
	var idle = idleStaff().size()
	if idle: h.append(["👤 " + str(idle) + " без каб.", "#555"])
	if S.get("over") and S.over.size(): h.append(["⚠ очередь", "#a60"])
	return h
