# Port of review/build46/ap.js (45.x autoplayer): only the game's own build/hire/item/vacc/buyOrgan paths, real costs, no stat injection.
class_name AutoPlayer
extends RefCounted

var sim: Sim
var st = {"log": [], "built": {}, "fails": {}}

func _init(s: Sim) -> void: sim = s

func RES() -> int: return 4000 + sim.S.staff.size() * 120
func count(t: String) -> int: return sim.rooms_of(t).filter(func(r): return not r.get("par")).size()

func tryBuild(t: String, big := false, reserve := -1) -> bool:
	var S = sim.S
	if sim.roomLocked(t): return false
	var d = sim.drm(t)
	if not sim.canStartRoom(t): return false
	var w: int = d.min[0] + 2
	var h: int = d.min[1] + 2
	if big:
		var g0 = {"type": t, "w": w, "h": h, "side": 0}
		sim.v24Pre(g0, 1)
		w = g0.w; h = g0.h
	var cost = sim.roomBuildCost({"type": t, "w": w, "h": h, "side": 0})
	if S.money < cost + (RES() if reserve < 0 else reserve): return false
	var cands = []
	for y in range(1, S.h - h):
		for x in range(1, S.w - w):
			var dist: float = absf(x + w / 2.0 - S.ent.x) + absf(y + h / 2.0 - S.ent.y) * 1.2
			cands.append([dist, x, y])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var n = 0
	for c in cands:
		var x: int = c[1]
		var y: int = c[2]
		if x <= S.ent.x and S.ent.x < x + w: continue
		for side in [0, 1, 2, 3]:
			var g = {"type": t, "x": x, "y": y, "w": w, "h": h, "side": side}
			if sim.validRoom(g) != null: continue
			var m0 = S.money
			if sim.buildRoom(g) == null and S.money < m0:
				st.built[t] = st.built.get(t, 0) + 1
				st.log.append([S.day, "build", t, x, y])
				return true
		n += 1
		if n > 4000: break
	st.fails[t] = st.fails.get(t, 0) + 1
	return false

func wanted() -> Array:
	var l = sim.L()
	var rooms: Array = l.rooms
	var cures = []
	var freq = {}
	for z in l.diseases:
		var c = sim.D.dis[z].cure
		freq[c] = freq.get(c, 0) + 1
		if not cures.has(c) and rooms.has(c) and sim.D.rooms.has(c): cures.append(c)
	var cheap = cures.duplicate()
	cheap.sort_custom(func(a, b): return sim.drm(a).cost < sim.drm(b).cost)
	# most common cures first, cheaper first on ties
	cures.sort_custom(func(a, b): return freq[a] > freq[b] or (freq[a] == freq[b] and sim.drm(a).cost < sim.drm(b).cost))
	var dg = []
	# finish() picks the shorter queue of diag/lab, so both share the load: lab (cheap, 7 s, standing) first, then diag
	for t in ["lab", "diag"]:
		if rooms.has(t) and sim.D.rooms.has(t): dg.append(t)
	var out = ["reception", "gp", cheap[0] if cheap.size() else "pharmacy", "toilet", "staffroom"]
	if dg.size(): out.append(dg[0])
	out.append("gp")
	if dg.size() > 1: out.append(dg[1])
	if l.get("locked") and rooms.has("research"): out.append("research")
	# other cure rooms: built on demand (demand()), or ahead of time only when cash is comfortable
	var rich = sim.S.day > 30 and sim.S.money > 60000 + sim.S.staff.size() * 900
	if rich:
		for c in cures:
			if not out.has(c): out.append(c)
	if rooms.has("icu") and sim.S.day > 25 and sim.S.money > 20000: out.append("icu")
	if rich:
		for t in dg.slice(1): out.append(t)
	if rooms.has("morgue") and sim.S.day > 40 and sim.S.litter.size() > 4: out.append("morgue")
	return out.filter(func(t): return t != null and sim.D.rooms.has(t))

func hireNeeds() -> void:
	var S = sim.S
	var need = {}
	for r in S.rooms:
		var t = sim.drm(r.type).get("staff")
		if t and not (r.type == "research" and sim.resDone()): need[t] = need.get(t, 0) + 1
	var mach = S.rooms.filter(func(r): return sim.drm(r.type).get("machine")).size()
	need.handyman = 1 + mach / 2 + S.pats.size() / 25 + mini(3, S.litter.size() / 8)
	if S.litter.size() > 6 and sim.D.staff.has("orderly") and sim.L().rooms.has("morgue"): need.orderly = maxi(need.get("orderly", 0), 1 + S.litter.size() / 10)
	for t in need:
		var have = S.staff.filter(func(s): return s.type == t).size()
		for a in S.get("away", []):
			if a.s.type == t: have += 1
		while have < need[t] and S.cands.get(t) and S.cands[t].size() and S.money > 2000:
			var bi = 0
			var cs: Array = S.cands[t]
			for i in cs.size():
				if cs[i].skill - cs[i].salary / salk() > cs[bi].skill - cs[bi].salary / salk(): bi = i
			sim.hire(t, bi)
			have += 1
			st.log.append([S.day, "hire", t])

func items() -> void:
	var S = sim.S
	if S.money < RES() + 3000: return
	var benches = S.items.filter(func(i): return i.type == "bench").size()
	var want = mini(14, 2 + S.rooms.size())
	if benches < want: tryPlace("bench")
	if S.items.filter(func(i): return i.type == "bin").size() < mini(12, 2 + S.rooms.size() / 2): tryPlace("bin")
	if S.items.filter(func(i): return i.type == "plant").size() < mini(6, S.rooms.size() / 3): tryPlace("plant")

func tryPlace(type: String) -> bool:
	var S = sim.S
	var rs: Array = S.rooms.duplicate()
	rs.shuffle()
	for r in rs:
		var o = sim.doorOut(r)
		for k in 12:
			var x: int = o.x + sim.ri(0, 6) - 3
			var y: int = o.y + sim.ri(0, 6) - 3
			if absi(x - S.ent.x) <= 1: continue
			if absi(x - o.x) + absi(y - o.y) <= 1: continue
			var n = S.items.size()
			var m0 = S.money
			var nm = sim.msgs.size()
			sim.placeItem(type, x, y)
			while sim.msgs.size() > nm: sim.msgs.pop_back()
			if S.items.size() > n and S.money < m0:
				st.log.append([S.day, "item", type])
				return true
	return false

# a player builds the room the moment patients are waiting for one that does not exist yet
func demand() -> void:
	var S = sim.S
	var want = {}
	for p in S.pats:
		if p.state == "seek" and sim.rooms_of(p.need).is_empty() and sim.D.rooms.has(p.need) and sim.L().rooms.has(p.need):
			want[p.need] = want.get(p.need, 0) + 1
	for t in want:
		if sim.roomLocked(t): continue
		tryBuild(t)

# triage like a player: a patient about to die in a queue is sent home (rep -2) instead of dying (rep -15)
func triage() -> void:
	var S = sim.S
	for p in S.pats.duplicate():
		if p.state in ["queue", "seek", "walk", "wait"] and p.health < 9.0 and not p.get("vip"):
			sim.leavePat(p.id)
			st.log.append([S.day, "home", p.need])

func events() -> void:
	var S = sim.S
	# ЧП: 3-7 patients with one disease within 20 days -> a second cure room for it pays for itself (bonus = n x fee)
	if S.get("em") and S.em.get("dis"):
		var cure = sim.D.dis[S.em.dis].cure
		if count(cure) < 2 and not sim.roomLocked(cure): tryBuild(cure, false, 1500)
	for p in S.pats.duplicate():
		if p.get("inf") and not p.get("immune") and S.money > 500: sim.vacc(p.id)
		var o = sim.needOrgan(p)
		if o and not p.get("organ") and p.known and S.money > RES() + 15000 and not sim.freeOrgan(o): sim.buyOrgan(p.id)

func expand() -> void:
	var S = sim.S
	var qs = {}
	var cn = {}
	for r in S.rooms:
		qs[r.type] = qs.get(r.type, 0) + r.queue.size()
		if not r.get("par"): cn[r.type] = cn.get(r.type, 0) + 1
		else: cn[r.type] = cn.get(r.type, 0) + 1
	var arr = []
	for t in qs:
		if sim.drm(t).get("staff") or t == "toilet": arr.append([float(qs[t]) / cn[t], t])
	arr.sort_custom(func(a, b): return a[0] > b[0])
	for a in arr:
		var t: String = a[1]
		var thr = 3 if (t == "reception" or t == "gp") else 2.5
		# caps: gp is the funnel (every patient, plus re-checks), reception rarely needs >2, everything else 3
		var cap = int(OS.get_environment("AP_CAP")) if OS.get_environment("AP_CAP") != "" else 3
		if t == "gp": cap = 6
		elif t == "reception": cap = 2
		# funnel rooms (every patient passes gp + diag) get money first: only a small cushion is kept
		var need_cash = sim.drm(t).cost + (1500 if t in ["gp", "diag", "lab", "reception"] else RES() + 2000)
		if a[0] >= thr and cn[t] < cap and S.money > need_cash:
			if tryBuild(t, false, 1500 if t in ["gp", "diag", "lab", "reception"] else -1): return

func lots() -> void:
	var S = sim.S
	for i in S.lots.size():
		var l = S.lots[i]
		if not l.own and S.money > l.price + RES() + 15000 and S.rooms.size() >= 8:
			sim.buyLot(i); return

func loans() -> void:
	var S = sim.S
	if S.money < 3000 and S.loan + 10000 <= sim.loanMax() and S.day < 300: sim.takeLoan()
	elif S.loan > 0 and S.money > 40000: sim.repayLoan()

func tick() -> void:
	var S = sim.S
	if S.is_empty() or S.won or S.lost: return
	# player setting from the ☰ menu: only treat at >=75% chance (more diagnosis first, fewer fatal failures)
	S.minCh = float(OS.get_environment("AP_MINCH")) if OS.get_environment("AP_MINCH") != "" else 0.75
	var seen = {}
	for t in wanted():
		seen[t] = seen.get(t, 0) + 1
		if count(t) < seen[t]:
			if sim.roomLocked(t): continue   # waits for research; don't stall the rest of the plan
			if not tryBuild(t): break
	hireNeeds()
	demand()
	events()
	triage()
	expand()
	items()
	lots()
	loans()
	sim.v12Bot()

func salk() -> float:
	return float(OS.get_environment("AP_SALK")) if OS.get_environment("AP_SALK") != "" else 40.0
