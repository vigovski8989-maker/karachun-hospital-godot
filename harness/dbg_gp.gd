extends SceneTree
func _init() -> void:
	var sim = Sim.new(); sim.rng.seed = 7919 + 4 * 104729; seed(31 + 4)
	sim.load_data(); sim.newGame(4)
	var ap = AutoPlayer.new(sim); sim.speed = 4
	var fr = 0
	var D = int(OS.get_environment("DBG_DAY")) if OS.get_environment("DBG_DAY") != "" else 120
	while sim.S.day < D:
		sim.step(1.0 / 30.0); fr += 1
		if fr % 30 == 0: ap.tick()
	for r in sim.S.rooms:
		if r.type in ["gp", "lab", "reception"]:
			var s = null
			for q in sim.S.staff: if q.id == r.get("staff"): s = q
			print("R ", r.type, " id ", r.id, " q ", r.queue.size(), " busy ", r.busy, " staff ", r.get("staff"), " st ", (s.state if s else "-"), " fat ", (int(s.fat) if s else -1), " ready ", sim.staffReady(r))
	for s in sim.S.staff:
		print("S ", s.type, " id ", s.id, " st ", s.state, " room ", s.get("room"), " fat ", int(s.fat), " away ", s.get("course"))
	print("away ", sim.S.get("away", []).size())
	quit()
