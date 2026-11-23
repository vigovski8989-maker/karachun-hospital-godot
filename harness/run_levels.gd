# Headless verification harness: godot --headless -s res://harness/run_levels.gd -- --lv=0 --days=400 --seed=1
extends SceneTree

func _init() -> void:
	var args = {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv = a.substr(2).split("=")
			args[kv[0]] = kv[1]
	var lvs: Array = []
	if args.has("lv"):
		for s in str(args.lv).split(","): lvs.append(int(s))
	else:
		lvs = range(12)
	var maxd = int(args.get("days", "500"))
	var seed = int(args.get("seed", "1"))
	var spd = float(args.get("speed", "4"))
	var results = []
	var all_ok = true
	for lv in lvs:
		var r = run_level(lv, maxd, seed, spd, args.has("saveday"), int(args.get("saveday", "60")))
		results.append(r)
		print("RESULT ", JSON.stringify(r))
		if not r.won: all_ok = false
	var f = FileAccess.open("user://harness_results.json", FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(results, " "))
	print("ALL_WON " if all_ok else "NOT_ALL_WON ", lvs)
	quit(0 if all_ok else 1)

var repd = {}
func run_level(lv: int, maxd: int, seed: int, spd: float, do_save: bool, saveday: int) -> Dictionary:
	var sim = Sim.new()
	sim.rng.seed = seed * 7919 + lv * 104729
	seed(seed * 31 + lv)
	sim.load_data()
	sim.newGame(lv)
	var ap = AutoPlayer.new(sim)
	var t0 = Time.get_ticks_msec()
	var frame = 0
	var stuck_max = 0.0
	var stuck_info = []
	var save_ok = null
	var fms = 1.0 / 30.0
	sim.speed = spd
	var last_day = -1
	var trace = OS.get_cmdline_user_args().has("--trace")
	repd = {}
	while not sim.S.won and not sim.S.lost and sim.S.day < maxd:
		sim.speed = spd
		var rep0: float = sim.S.rep
		var nm0 = sim.msgs.size()
		var mlast = sim.msgs[-1] if nm0 > 0 else null
		sim.step(fms)
		var drep: float = sim.S.rep - rep0
		if absf(drep) > 0.001:
			var key = "drift"
			if sim.msgs.size() > 0 and not is_same(sim.msgs[-1], mlast):
				var tx: String = sim.msgs[-1].text
				key = tx.substr(0, 2) + ("" if tx.length() < 2 else "")
			repd[key] = repd.get(key, 0.0) + drep
		frame += 1
		if frame % 30 == 0: ap.tick()
		if trace and sim.S.day != last_day and sim.S.day % 20 == 0:
			last_day = sim.S.day
			var ang = 0
			var dl = sim.S.get("lvw", {})
			for k in dl: if str(k).begins_with("😠") or str(k).begins_with("😞"): ang += dl[k]
			print("TRACE d", sim.S.day, " rep ", int(sim.S.rep), " $", int(sim.S.money), " cured ", sim.S.cured, " deaths ", sim.S.deaths, " litter ", sim.S.litter.size(), " bad ", ang, " pats ", sim.S.pats.size(), " staff ", sim.S.staff.size(), " hm ", sim.S.staff.filter(func(x): return x.type == "handyman").size(), " closed ", sim.S.rooms.filter(func(r): return r.get("cond", 100) <= 20).size())
		if frame % 30 == 0:
			for e in sim.S.pats:
				var key = str(int(round(e.x * 4)), ",", int(round(e.y * 4)), e.state, e.need)
				if e.get("_k") != key:
					e._k = key; e._kt = sim.S.t
				var still: float = sim.S.t - e._kt
				if e.state != "dead" and e.state != "queue" and e.state != "treat" and e.state != "vip" and not (e.vs and e.vs.ph == "sat") and still > 120:
					if still > stuck_max:
						stuck_max = still
						stuck_info = [e.state, e.need, e.x, e.y, e.path.size(), e.vs != null]
		if do_save and save_ok == null and sim.S.day >= saveday:
			save_ok = save_roundtrip(sim)
		if sim.S.day != last_day and sim.S.day % (10 if trace else 50) == 0:
			last_day = sim.S.day
			print("  L", lv + 1, " d", sim.S.day, " cured ", sim.S.cured, "/", sim.L().goals.cured, " net ", int(sim.netCash()), "/", sim.L().goals.money, " rep ", int(sim.S.rep), "/", sim.L().goals.rep, " val ", int(sim.hospValue()), " pats ", sim.S.pats.size(), " rooms ", sim.S.rooms.size(), " staff ", sim.S.staff.size(), " deaths ", sim.S.deaths, " repd ", JSON.stringify(repd), " hist ", JSON.stringify(_hist(sim)))
	var maxQ = 0
	for r in sim.S.rooms: maxQ = maxi(maxQ, r.queue.size())
	return {"lv": lv + 1, "won": sim.S.won, "lost": sim.S.lost, "day": sim.S.day, "cured": sim.S.cured, "deaths": sim.S.deaths, "rep": int(sim.S.rep), "net": int(sim.netCash()), "val": int(sim.hospValue()), "goals": sim.L().goals, "rooms": sim.S.rooms.size(), "staff": sim.S.staff.size(), "maxQ": maxQ, "stuckMax": int(stuck_max), "stuck": stuck_info, "save": save_ok, "built": ap.st.built, "fails": ap.st.fails, "wall_s": (Time.get_ticks_msec() - t0) / 1000.0, "dl": sim.S.get("dl"), "dstat": sim.dstat, "lvw": sim.S.get("lvw"), "repd": repd, "left": sim.S.v18.left if sim.S.get("v18") else 0, "dz": {"n": sim.S.get("dzN", 0), "wcDirty": sim.S.get("wcDirty", 0), "acc": sim.S.get("dzAcc", 0), "dirtyNow": sim.S.rooms.filter(func(r): return r.type == "toilet" and r.get("dirty")).size()}, "lastMsgs": sim.msgs.slice(-5).map(func(m): return m.text)}

func save_roundtrip(sim: Sim) -> Dictionary:
	var before = {"lv": sim.S.lv, "day": sim.S.day, "money": sim.S.money, "cured": sim.S.cured, "rooms": sim.S.rooms.size(), "staff": sim.S.staff.size(), "pats": sim.S.pats.size()}
	var j = sim.save_json()
	var s2 = Sim.new()
	s2.load_data()
	var parsed = JSON.parse_string(j)
	s2.load_state(parsed.S)
	var after = {"lv": s2.S.lv, "day": s2.S.day, "money": s2.S.money, "cured": s2.S.cured, "rooms": s2.S.rooms.size(), "staff": s2.S.staff.size(), "pats": s2.S.pats.size()}
	var ok = true
	for k in before:
		if float(before[k]) != float(after[k]): ok = false
	# continue the run on the reloaded state to prove it is playable
	sim.S = s2.S
	sim.invBlk()
	return {"ok": ok, "before": before, "after": after, "bytes": j.length()}


func _hist(sim) -> Dictionary:
	var h = {}
	for p in sim.S.pats:
		var k = str(p.state, ":", p.need)
		h[k] = h.get(k, 0) + 1
	var idle = 0
	for s in sim.S.staff:
		if s.state == "idle" or s.state == "wait": idle += 1
	h["_staff_idle"] = idle
	h["_money"] = int(sim.S.money)
	return h
