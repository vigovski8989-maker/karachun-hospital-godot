# mech.js: lots, research, emergencies, epidemics, VIP, quakes, loans, hospital value
class_name SimMech
extends SimMotion

func mechInit() -> void:
	var l = L()
	S.lots = []
	for a in l.get("lots", []): S.lots.append({"x": int(a[0]), "y": int(a[1]), "w": int(a[2]), "h": int(a[3]), "price": a[4], "own": false})
	S.rp = 0.0
	S.unl = {}
	S.loan = 0
	S.em = null; S.epi = null; S.vip = null; S.quake = null
	S.mt = {"em": ri(6, 10) if l.get("emerg") else -1, "epi": ri(10, 16) if l.get("epid") else -1, "vip": ri(8, 14) if l.get("vip") else -1, "quake": ri(12, 20) if l.get("quake") else -1}

func lotAt(x, y) -> Variant:
	if S.is_empty() or S.get("lots") == null: return null
	for l in S.lots:
		if not l.own and x >= l.x and y >= l.y and x < l.x + l.w and y < l.y + l.h: return l
	return null
func inLot(x, y) -> bool: return lotAt(x, y) != null

func buyLot(i: int) -> bool:
	if i < 0 or i >= S.lots.size(): return false
	var l = S.lots[i]
	if l.own: return false
	if S.money < l.price:
		msg("Недостаточно денег на участок"); snd("bad"); return false
	S.money -= l.price
	l.own = true
	invBlk(); _rgrid_sig = ""
	snd("build")
	msg("🏞 Участок куплен: +" + str(l.w * l.h) + " клеток")
	return true

func hospValue() -> float:
	var v = 0.0
	for r in S.rooms:
		if not r.get("par"): v += gnum(r, "cost", drm(r.type).cost)
	for i in S.items: v += D.items[i.type].cost
	for l in S.get("lots", []):
		if l.own: v += round(l.price * 1.5)
	return v + maxf(0, S.money) - gnum(S, "loan", 0)

func roomLocked(k) -> bool: return lockCost(k) > 0
func lockCost(k) -> float:
	var lk = L().get("locked")
	if lk and lk.get(k) and not (S.get("unl") and S.unl.get(k)): return lk[k]
	return 0

func mechTick(dt: float) -> void:
	var lk = L().get("locked")
	if lk:
		for r in S.rooms:
			if r.type == "research" and staffReady(r):
				var s = staff_by_id(r.staff)
				S.rp += dt * 0.9 * eff(s) * v24Spd(rCap(r))
		for k in lk:
			if not S.unl.get(k) and S.rp >= lk[k]:
				S.unl[k] = 1
				msg("🔬 Исследование завершено: можно строить «" + drm(k).name + "»")
				snd("win")
	if S.get("quake") and S.quake.t > 0:
		S.quake.t -= dt
		if S.quake.t <= 0: S.quake = null

func mechDay() -> void:
	var l = L()
	var d: int = S.day
	if S.loan > 0 and d % MONTH_DAYS == 0:
		var i = int(round(S.loan * gnum(l, "loanRate", .03)))
		S.money -= i
		msg("🏦 Проценты по кредиту −$" + str(i))
	if S.em and d >= S.em.until:
		var left = []
		for id in S.em.ids:
			var p = pat_by_id(id)
			if p and p.state != "leave" and p.state != "dead": left.append(id)
		var ok: int = S.em.cured
		if ok >= S.em.n * 0.6:
			S.money += S.em.bonus; S.earn += S.em.bonus
			S.rep = minf(1000, S.rep + 20)
			msg("🚑 ЧП: спасено " + str(ok) + "/" + str(S.em.n) + " — премия $" + str(S.em.bonus))
		else:
			S.rep = maxf(0, S.rep - 25)
			msg("🚑 ЧП провалено: спасено " + str(ok) + "/" + str(S.em.n) + " — репутация −25")
		for id in left:
			var p = pat_by_id(id)
			if p: p.emg = false
		S.em = null
		S.mt.em = d + ri(10, 16)
	elif not S.em and S.mt.em >= 0 and d >= S.mt.em:
		startEmergency()
	if S.epi and d >= S.epi.until:
		var inf = 0
		for p in S.pats:
			if p.get("inf") and p.state != "leave" and p.state != "dead": inf += 1
		if inf == 0:
			S.money += 3000
			S.rep = minf(1000, S.rep + 15)
			msg("🦠 Инспектор доволен: эпидемия остановлена, +$3000")
		else:
			var f = inf * 1500
			S.money -= f
			S.rep = maxf(0, S.rep - inf * 8)
			msg("🦠 Инспектор нашёл " + str(inf) + " заражённых: штраф −$" + str(f))
		for p in S.pats: p.inf = false
		S.epi = null
		S.mt.epi = d + ri(14, 22)
	elif not S.epi and S.mt.epi >= 0 and d >= S.mt.epi and S.pats.size() > 3:
		var c = S.pats.filter(func(p): return not p.get("immune") and p.state != "dead" and p.state != "leave")
		if c.size():
			var p = pick(c)
			p.inf = true
			S.epi = {"until": d + 6, "dis": p.dis}
			msg("🦠 Эпидемия! Заразный пациент " + p.name + ". Вакцинируйте больных (нажмите на пациента) до прихода инспектора через 6 дней")
			snd("pa")
	if not S.vip and S.mt.vip >= 0 and d >= S.mt.vip: spawnVip()
	if S.mt.quake >= 0 and d == S.mt.quake - 1: msg("🌋 Сейсмологи предупреждают: завтра возможно землетрясение! Отремонтируйте аппараты")
	if S.mt.quake >= 0 and d >= S.mt.quake:
		quakeHit()
		S.mt.quake = d + ri(18, 26)

func startEmergency() -> void:
	var ok = []
	for z in L().diseases:
		if D.dis[z].cure != "transplant" and first_room(D.dis[z].cure) != null: ok.append(z)
	if ok.is_empty():
		S.mt.em = S.day + 4; return
	var dz = pick(ok)
	var n = ri(3, 5) + (2 if S.lv > 8 else 0)
	S.em = {"dis": dz, "ids": [], "n": n, "cured": 0, "until": S.day + 20, "bonus": n * D.dis[dz].fee}
	for i in n:
		var p = spawnPatient()
		p.dis = dz; p.known = false; p.cert = .45; p.need = "reception"; p.emg = true
		p.health = maxf(p.health, 100); p.wcDone = true
		S.em.ids.append(p.id)
		p.x = float(S.ent.x + ri(-1, 1))
	msg("🚑 ЧП! " + str(n) + " пациентов с «" + D.dis[dz].name + "». Пройдут регистрацию и диагностику без очереди. Вылечите ≥60% за 20 дней — премия $" + str(S.em.bonus))
	snd("pa")

func spawnVip() -> void:
	var p = spawnPatient()
	p.vip = true
	p.state = "vip"
	p.vt = []
	var rs: Array = S.rooms.duplicate()
	rs.shuffle()
	for r in rs.slice(0, 5):
		var o = doorOut(r)
		p.vt.append([o.x, o.y])
	p.pat = 100.0; p.health = 100.0; p.wcDone = true
	S.vip = {"id": p.id, "deaths0": S.deaths, "cured0": S.cured, "litter": 0, "n": 0}
	msg("🎩 В больницу прибыл VIP-гость. Он оценит чистоту, очереди и уют")
	S.mt.vip = -1

func updVip(p, dt: float) -> void:
	if not S.vip:
		p.vip = false; leave(p, "🎩", 0); return
	if p.path.is_empty():
		if p.vt.size():
			var t = p.vt.pop_front()
			goTo(p, t[0], t[1])
			S.vip.litter += S.litter.size()
			S.vip.n += 1
			var q = 0
			for r in S.rooms: q += r.queue.size()
			S.vip.q = gnum(S.vip, "q", 0) + q
		else:
			vipVerdict()
			leave(p, "🎩", 0)
			return
	move(p, dt)

func vipVerdict() -> void:
	var v = S.vip
	if not v: return
	var n = maxf(1, v.n)
	var lit: float = v.litter / n
	var q: float = gnum(v, "q", 0) / n / maxf(1, S.rooms.size())
	var dd: int = S.deaths - v.deaths0
	var comf = 0
	for i in S.items:
		if gnum(D.items[i.type], "comfort"): comf += 1
	var sc: float = 100 - lit * 4 - q * 25 - dd * 20 + mini(20, comf * 2) + (S.rep - 500) / 20.0
	sc = clampf(round(sc), 0, 100)
	var bonus: int = int(round(sc * 100)) if sc >= 60 else 0
	S.money += bonus
	S.rep = clampf(S.rep + (sc - 50) / 2.0, 0, 1000)
	var t = "🎩 Отзыв VIP-гостя: оценка " + str(int(sc)) + "/100. " + (("«Великолепно! Жертвую $" + str(bonus) + "»") if sc >= 60 else "«Грязно и долго. Расскажу всем друзьям…»")
	msg(t)
	events.append(["modal", t])
	S.vip = null
	S.mt.vip = S.day + ri(16, 24)

func quakeHit() -> void:
	S.quake = {"t": 4.0}
	snd("boom")
	var n = 0
	for r in S.rooms.duplicate():
		if drm(r.type).get("machine"):
			r.cond = maxf(5, r.cond - ri(15, 40)); n += 1
	msg("🌋 Землетрясение! Повреждено аппаратов: " + str(n) + ". Аппараты с износом ≤20% закрыты до ремонта — нужен разнорабочий")
	events.append(["quake", null])

func loanMax() -> int: return int(gnum(L(), "loanMax", 40000))
func takeLoan() -> bool:
	if S.loan + 10000 > loanMax(): return false
	S.loan += 10000; S.money += 10000; return true
func repayLoan() -> bool:
	if S.loan < 10000 or S.money < 10000: return false
	S.loan -= 10000; S.money -= 10000; return true
