# debug: reception waiting layout (benches + line) after a crowd spawn. godot --headless -s res://harness/recq.gd -- --lv=1
extends SceneTree
func _init() -> void:
	var lv = 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lv="): lv = int(a.substr(5))
	var sim = Sim.new(); sim.rng.seed = 7919 + lv * 104729; seed(31 + lv)
	sim.load_data(); sim.newGame(lv)
	var ap = AutoPlayer.new(sim)
	var fr = 0
	sim.speed = 4
	while sim.S.day < 3:
		sim.step(0.05); fr += 1
		if fr % 30 == 0: ap.tick()
	for i in int(OS.get_environment("NC") if OS.get_environment("NC") != "" else "14"): sim.spawnPatient()
	for k in 1200:
		sim.step(0.05); fr += 1
		if fr % 30 == 0: ap.tick()
		if k % 300 == 299:
			for r in sim.S.rooms:
				if r.type != "reception": continue
				print("REC ", r.id, " door ", r.door, " side ", r.side, " q ", r.queue.size(), " line ", sim._rec_line(r).size())
				for id in r.queue:
					var p = sim.pat_by_id(id)
					if p: print("   ", id, " ", p.state, " pos ", snappedf(p.x, .1), ",", snappedf(p.y, .1), " wsp ", p.get("wsp"), " seat ", p.get("wantSeat") != null, " vs ", p.vs != null, " path ", p.path.size())
			for p in sim.S.pats:
				if p.x >= 15 and p.x <= 22 and p.y >= 22:
					print("  AREA ", p.id, " ", p.state, " need ", p.get("need"), " room ", p.room, " pos ", snappedf(p.x, .1), ",", snappedf(p.y, .1), " wsp ", p.get("wsp"), " path ", p.path.size())
			var nb = 0
			for i in sim.S.items: if i.type == "bench": nb += 1
			print("benches ", nb, " ent ", sim.S.ent)
	for r in sim.S.rooms:
		if r.type != "reception": continue
		var ln = sim._rec_line(r); var lm = {}
		for i in ln.size(): lm[Vector2i(ln[i].x, ln[i].y)] = i
		for t in sim._lines[r.id][2]: lm[Vector2i(t.x, t.y)] = -1
		var occ = {}
		for p in sim.S.pats: occ[Vector2i(int(round(p.x)), int(round(p.y)))] = occ.get(Vector2i(int(round(p.x)), int(round(p.y))), 0) + 1
		for y in sim.S.h:
			var row = ""
			for x in sim.S.w:
				var v = Vector2i(x, y)
				var ch = "."
				if sim.isHole(x, y): ch = " "
				elif sim.roomAt(x, y) != null: ch = "R" if sim.roomAt(x, y) == r else "#"
				elif sim.blk().has(y * sim.S.w + x): ch = "="
				if lm.has(v): ch = "o" if lm[v] < 0 else String.chr(65 + lm[v] % 26)
				if occ.has(v): ch = ch.to_lower() if ch >= "A" and ch <= "Z" else str(mini(occ[v], 9))
				row += ch
			print(row)
	quit()
