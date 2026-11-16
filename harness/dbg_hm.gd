extends SceneTree
func _init() -> void:
	var sim = Sim.new(); sim.load_data(); sim.newGame(1)
	var ap = AutoPlayer.new(sim); sim.speed = 4
	var fr = 0
	while sim.S.day < 120:
		sim.step(1.0 / 30.0); fr += 1
		if fr % 30 == 0: ap.tick()
	for s in sim.S.staff:
		if s.type == "handyman":
			var t = s.get("task")
			print("HM ", s.id, " st=", s.state, " task=", (t.k if t else null), " pos=", Vector2(s.x, s.y), " path=", s.path.size(), " fat=", int(s.fat), " cl=", s.get("cl") != null, " oa=", s.get("oa"))
	print("litter ", sim.S.litter.size(), " ", sim.S.litter.slice(0, 5))
	for r in sim.S.rooms:
		if sim.drm(r.type).get("machine"): print("M ", r.type, " cond ", r.cond)
	quit()
