# v18.js: patience factors, leaving unserved, rank influence, queue rebalance, crowd factor
class_name Sim18
extends Sim17

const PAT_RANK := [0.8, 0.9, 1, 1.12, 1.25]

func v18Init() -> void:
	if S.get("v18") == null: S.v18 = {"left": 0, "lost": 0, "moved": 0}

func patFactors(p, c: float) -> Dictionary:
	var r = room_by_id(p.room)
	var pos: int = maxi(0, r.queue.find(p.id)) if r else 0
	var q = 1 + minf(0.6, maxf(0, pos - 3) * 0.06)
	var t = 1 + minf(0.5, gnum(p, "wt", 0.0) / 300.0)
	var soda = 0.85 if S.items.any(func(i): return i.type == "soda" and absf(i.x - p.x) + absf(i.y - p.y) <= 5) else 1.0
	if S.v18.get("rd") != S.day:
		S.v18.rd = S.day
		S.v18.rk = myRank()
	var rk: float = PAT_RANK[S.v18.rk - 1] if S.v18.rk - 1 < PAT_RANK.size() else 1.0
	return {"c": maxf(0.33, 1 - c / 12.0), "q": q, "t": t, "soda": soda, "rk": rk}

func patRate(p, c, dt) -> float:
	v18Init()
	p.wt = gnum(p, "wt", 0.0) + (dt if dt else 0.05)
	var f = patFactors(p, c)
	p._pf = f
	if f.soda < 1 and not p.get("drank") and p.pat < 60 and rand() < 0.004:
		p.drank = true
		p.pat = minf(100, p.pat + 15)
		p.thought = "🥤"
		S.money += 15; S.earn += 15
	return 0.35 * f.c * f.q * f.t * f.soda * f.rk

func patLeave(p) -> void:
	v18Init()
	var fee = D.dis.get(p.dis, {}).get("fee", 0)
	S.v18.left += 1
	S.v18.lost += fee
	p.angry = true
	msg("😠 " + p.name + " ушёл(ла), не дождавшись — упущено $" + str(fee) + ", репутация −3")
	leave(p, "😠", 3)
	snd("bad")

func v18Rebalance() -> void:
	for r in S.rooms:
		if r.queue.size() < 4: continue
		var s = staff_by_id(r.staff)
		if s and s.state == "work": continue
		var alt = S.rooms.filter(func(o): return o != r and o.type == r.type and o.queue.size() + 3 < r.queue.size() and S.staff.any(func(x): return x.id == o.staff and x.state == "work"))
		if alt.is_empty(): continue
		var p = pat_by_id(r.queue.back())
		if p == null or p.state != "queue" or p.vs: continue
		unqueue(p)
		p.state = "seek"
		S.v18.moved += 1

func update(dt: float) -> void:
	super.update(dt)
	if S.is_empty(): return
	v18Init()
	S.v18.rt = gnum(S.v18, "rt", 0.0) + dt
	if S.v18.rt > 1:
		S.v18.rt = 0.0
		v18Rebalance()

func chips() -> Array:
	var h = super.chips()
	v18Init()
	if S.v18.left: h.append(["😠 " + str(S.v18.left), "#8a3a2a"])
	return h

func crowdK() -> float:
	var q = -1
	for r in S.rooms:
		if r.type == "gp" or r.type == "reception": q = maxi(q, r.queue.size())
	if q < 0: return 1.0
	if q < 8: return 1.0
	v18Init()
	if not S.v18.get("crowdMsg"):
		S.v18.crowdMsg = 1
		msg("🗣 Длинные очереди отпугивают новых пациентов — постройте ещё кабинет")
	return maxf(0.7, 1 - (q - 7) * 0.06)
