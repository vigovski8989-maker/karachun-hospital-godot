# v12.js: morgue, organ transplants, orderly body fetch/carry
class_name Sim12
extends Sim11

const ORG := {"heart": ["🫀", "сердце"], "liver": ["🟤", "печень"], "kidney": ["🫘", "почка"], "lungs": ["🫁", "лёгкие"], "stomach": ["🥟", "желудок"]}
const MORGUE_CAP := 6
const ORGAN_LIFE := 8
const ORGAN_PRICE := 2500

func v12Init() -> void:
	if S.get("morgue") == null: S.morgue = []
	if S.get("organs") == null: S.organs = []
	if S.get("cands") and not S.cands.has("orderly"):
		S.cands.orderly = []
		for i in 3: S.cands.orderly.append(cand_new("orderly"))

func morgueRoom() -> Variant:
	for r in S.rooms:
		if r.type == "morgue" and r.staff != null and staff_by_id(r.staff) != null: return r
	return null

func morgueFree() -> int:
	v12Init()
	return MORGUE_CAP - S.morgue.size()

func needOrgan(p) -> Variant:
	var dz = D.dis.get(p.dis)
	return dz.get("organ") if dz and dz.cure == "transplant" else null

func freeOrgan(t) -> Variant:
	v12Init()
	var best = null
	for o in S.organs:
		if o.type == t and (best == null or o.until < best.until): best = o
	return best

func retOrgan(p) -> void:
	if p.get("organ") and not p.get("organUsed"): S.organs.append(p.organ)
	p.organ = null

func buyOrgan(id) -> void:
	var p = pat_by_id(id)
	if p == null: return
	var t = needOrgan(p)
	if not t or p.get("organ"): return
	if S.money < ORGAN_PRICE:
		msg("Не хватает денег на орган"); return
	S.money -= ORGAN_PRICE
	v12Init()
	S.organs.append({"type": t, "q": .72, "until": S.day + ORGAN_LIFE, "from": "банк"})
	msg("📦 Куплен орган «" + ORG[t][1] + "» в банке органов −$" + str(ORGAN_PRICE))

func die(p, why := "x") -> void:
	super.die(p, why)
	retOrgan(p)
	if first_room("morgue") != null:
		p.body = "wait"; p.bw = 0.0

func updPatient(p, dt: float) -> void:
	if p.state == "dead" and p.get("body"):
		p.bw += dt
		if p.body == "wait" and (p.bw > 40 or morgueRoom() == null or morgueFree() <= 0) and p.bw > 8:
			p.body = null; p.t = 0.0
		return
	if p.state == "leave" and p.get("organ"): retOrgan(p)
	var ot = needOrgan(p)
	if ot and p.state == "queue" and not p.get("organ"):
		var r = room_by_id(p.room)
		if r and r.type == "transplant":
			unqueue(p); clearSeat(p); p.vs = null; p.room = null; p.state = "seek"; p.need = "transplant"
	if ot and p.state == "seek" and p.need == "transplant" and not p.get("organ") and first_room("transplant") != null:
		var o = freeOrgan(ot)
		if o:
			S.organs.erase(o)
			p.organ = o
			p.ow = 0.0
			msg("🧊 Для " + p.name + " нашёлся орган «" + ORG[ot][1] + "» (совместимость " + str(int(round(o.q * 100))) + "%)")
		else:
			var dz = D.dis[p.dis]
			p.thought = ORG[ot][0] + "⏳"
			p.ow = gnum(p, "ow", 0.0) + dt
			move(p, dt)
			if p.path.is_empty() and rand() < .01:
				var x = ri(1, S.w - 2)
				var y = ri(S.h - 6, S.h - 2)
				if walk(x, y) and not roomAt(x, y): goTo(p, x, y)
			p.health -= dt * 0.07 * (0.5 + dz.diff) * gnum(L(), "decay", 1)
			if p.health <= 0:
				die(p, "organ"); return
			if p.ow > 200:
				msg(p.name + " не дождался донорского органа и ушёл")
				S.sent += 1
				leave(p, "🏠", 3)
			return
	super.updPatient(p, dt)

func cureChance(p, s = null) -> float:
	var c = super.cureChance(p, s)
	if needOrgan(p):
		var q: float = p.organ.q if p.get("organ") else .4
		c = maxf(.05, minf(.95, c * (.35 + q * .7) - (.15 if s and s.skill < 60 else 0.0)))
		if s and p.state == "treat": p.organUsed = true
	return c

func updStaff(s, dt: float) -> void:
	match s.state:
		"fetch":
			var p = pat_by_id(s.get("body"))
			if p == null:
				s.state = "idle"; s.body = null; return
			if move(s, dt, 3):
				s.state = "pick"; s.pt = 0.0
			return
		"pick":
			var p = pat_by_id(s.get("body"))
			if p == null:
				s.state = "idle"; s.body = null; return
			s.pt += dt
			if s.pt > 1.2:
				p.body = "carry"
				var r = room_by_id(s.room)
				if r == null:
					p.body = null; p.t = 0.0; s.state = "idle"; return
				var q = spotStaff(r)
				goTo(s, q.x, q.y)
				s.state = "carry"
			return
		"carry":
			var p = pat_by_id(s.get("body"))
			if p == null:
				s.state = "idle"; return
			var done = move(s, dt, 2.6)
			p.x = s.x; p.y = s.y; p.dir = s.dir
			if done:
				v12Init()
				S.pats.erase(p)
				S.morgue.append({"name": p.name, "day": S.day})
				S.rep = minf(1000, S.rep + 8)
				s.body = null
				var txt = "⚰ " + p.name + " доставлен(а) в морг (репутация −7 вместо −15)"
				if rand() < .6:
					var ks = ORG.keys()
					var n = ri(1, 2)
					var got = ""
					for i in n:
						var t = pick(ks)
						S.organs.append({"type": t, "q": round(rnd(.6, .97) * 100) / 100.0, "until": S.day + ORGAN_LIFE, "from": p.name})
						got += ORG[t][0]
					txt += ". Донор согласен: " + got
				msg(txt)
				s.state = "goto"
			return
	if s.state == "work" and (s.type == "orderly" or s.type == "doctor"):
		var r = room_by_id(s.room)
		if r and r.type == "morgue" and morgueFree() > 0:
			var p = null
			for x in S.pats:
				if x.state == "dead" and x.get("body") == "wait": p = x; break
			if p:
				if s.vs:
					if s.vs.ph == "sat":
						leaveSeat(s); return
					clearSeat(s)
				if goTo(s, round(p.x), round(p.y)):
					p.body = "fetch"; s.body = p.id; s.state = "fetch"; return
	super.updStaff(s, dt)

func v12Day() -> void:
	v12Init()
	var bad = S.organs.filter(func(o): return o.until <= S.day)
	if bad.size():
		S.organs = S.organs.filter(func(o): return o.until > S.day)
		msg("🗑 Испортилось органов: " + str(bad.size()))
	S.morgue = S.morgue.filter(func(b): return S.day - b.day < 6)

func v12Bot() -> void:
	v12Init()
	if S.get("_obT") != null and S.day - S._obT < .5: return
	for p in S.pats:
		if needOrgan(p) and not p.get("organ") and p.state == "seek" and gnum(p, "ow", 0) > 15 and not freeOrgan(needOrgan(p)) and S.money > 30000:
			buyOrgan(p.id); S._obT = S.day; return

func spawnPatient() -> Variant:
	var p = super.spawnPatient()
	if p and needOrgan(p) and rand() < .6:
		var ok = []
		for z in L().diseases:
			if D.dis[z].cure != "transplant" and not roomLocked(D.dis[z].cure): ok.append(z)
		if ok.size(): p.dis = pick(ok)
	return p

func chips() -> Array:
	var h = super.chips()
	if first_room("morgue") != null or (S.get("organs") and S.organs.size()):
		v12Init()
		h.append(["⚰" + str(S.morgue.size()) + "/" + str(MORGUE_CAP), ""])
		if S.organs.size(): h.append(["🧊" + str(S.organs.size()), ""])
	return h
