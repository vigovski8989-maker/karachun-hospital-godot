# Main scene driver: sim + 3D view + HUD + input + saves (user://), level progress, 45.x save import.
class_name GameMain
extends Node3D

const SAVE_KEY := "hohotun_trial45_save_v1"
const PROG_FILE := "user://progress.json"
const SETTINGS_FILE := "user://settings.json"

var sim: Sim
var view: WorldView
var cam: IsoCam
var hud: Hud
var snd_node: Snd
var sun: DirectionalLight3D
var env: WorldEnvironment
var ghost = null            # room ghost {type,w,h,side,x,y}
var ghost_node: Node3D
var item_mode = null        # item key while placing
var item_ghost: Node3D
var ig = Vector2i(0, 0)
var in_game = false
var sound_on = true
var gfx = "medium"
var gfx_user = false
var perf_t = 0.0
var perf_n = 0
var autosave_t = 0.0
var drag_ghost = null
var auto_play = false
var ap = null
var ap_frame = 0
var start_lv = -1
var dbg_ui = ""
var dbg_zoom = 0.0
var dbg_focus = ""
var dbg_watch = ""
var dbg_demo = ""
var dbg_watch_q = 0.5
var dbg_watch_n = 0
var dbg_wmax = 20000
var ff_days = 0
var shot_path = ""
var shot_frames = -1
var dbg_speed = 0
var dbg_big = 0
var dbg_staff = "doctor"
var dbg_audit = null

func _ready() -> void:
	_load_settings()
	sim = Sim.new()
	sim.load_data()
	_env()
	view = WorldView.new()
	view.sim = sim
	add_child(view)
	cam = IsoCam.new()
	add_child(cam)
	view.cam = cam
	cam.tapped.connect(_on_tap)
	cam.drag_start_cb = _on_drag_start
	cam.dragged.connect(_on_drag)
	ghost_node = Node3D.new(); add_child(ghost_node)
	item_ghost = Node3D.new(); add_child(item_ghost)
	snd_node = Snd.new(); add_child(snd_node)
	snd_node.on = sound_on
	var cl = CanvasLayer.new(); add_child(cl)
	hud = Hud.new()
	hud.game = self
	hud.sim = sim
	cl.add_child(hud)
	cam.hud = hud
	set_gfx(gfx, false)
	_parse_args()
	_apply_sh_dbg()
	# start: continue last level if saved, else level 1, then show level select (as 45.x)
	var last = _last_lv()
	sim.newGame(0)
	if last >= 0 and has_save(last): load_game(last)
	_after_new()
	if start_lv >= 0:
		start_level(start_lv)
		hud.close_modal()
		# fast-forward headless-style for screenshots
		if ff_days > 0:
			ap = AutoPlayer.new(sim) if auto_play else null
			sim.speed = 4
			var fr = 0
			while sim.S.day < ff_days and not sim.S.won and not sim.S.lost:
				sim.step(0.05)
				fr += 1
				if ap and fr % 30 == 0: ap.tick()
			sim.events = []
		if auto_play: set_speed(dbg_speed if dbg_speed > 0 else 1)
		if dbg_demo != "" and ap:
			# debug-only screenshot scenario: make sure a <type> room exists and route a few patients to it
			sim.S.money += 60000
			if dbg_big > 0:
				for r0 in sim.rooms_of(dbg_demo).duplicate(): sim.sellRoom(r0.id)
				sim.S.money += 60000
				print("BIG ", ap.tryBuild(dbg_demo, true, 0, dbg_big), " slots ", sim.rooms_of(dbg_demo).size())
			if sim.rooms_of(dbg_demo).is_empty(): ap.tryBuild(dbg_demo)
			ap.hireNeeds()
			var n = 0
			for p in sim.S.pats:
				if n < (6 if dbg_big > 0 else 3) and p.state in ["queue", "seek"] and not p.get("vs"):
					sim.unqueue(p); p.need = dbg_demo; p.known = true; p.cert = 1.0; p.state = "seek"; n += 1
			var keep_w = dbg_watch.begins_with("seat:")
			if not keep_w: dbg_watch = dbg_demo
			if dbg_demo == "staffroom":
				for s0 in sim.S.staff: s0.fat = 96.0
				if not keep_w: dbg_watch = "s_" + dbg_staff
			print("DEMO ", dbg_demo, " rooms ", sim.rooms_of(dbg_demo).size(), " routed ", n)
		if dbg_zoom > 0: cam.zoom = dbg_zoom
		if dbg_focus != "":
			var f = dbg_focus.split(",")
			if dbg_focus == "ent": cam.focus = Vector3(sim.S.ent.x + .5, 0, sim.S.h - 2.0)
			elif dbg_focus == "leaf": pass
			elif dbg_focus.begins_with("door:") and not sim.rooms_of(dbg_focus.substr(5)).is_empty():
				var rd = sim.rooms_of(dbg_focus.substr(5))[0].door
				cam.focus = Vector3(rd.x + .5, 0, rd.y + .5)
			else: cam.focus = Vector3(float(f[0]), 0, float(f[1]))
		cam.apply()
		_dbg_ui()
	elif not auto_play:
		show_levels()
	else:
		set_speed(4)

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot_path = a.substr(7)
		elif a.begins_with("--frames="): shot_frames = int(a.substr(9))
		elif a == "--auto": auto_play = true
		elif a.begins_with("--ui="): dbg_ui = a.substr(5)
		elif a.begins_with("--zoom="): dbg_zoom = float(a.substr(7))
		elif a.begins_with("--focus="): dbg_focus = a.substr(8)
		elif a.begins_with("--demo="): dbg_demo = a.substr(7)
		elif a.begins_with("--camrot="): cam.dir = cam.dir.rotated(Vector3.UP, deg_to_rad(float(a.substr(9))))
		elif a.begins_with("--watch="):
			var w = a.substr(8).split(":")
			dbg_watch = w[0]
			if w.size() > 1: dbg_watch_q = float(w[1])
		elif a.begins_with("--lv="): start_lv = int(a.substr(5))
		elif a.begins_with("--days="): ff_days = int(a.substr(7))
		elif a.begins_with("--campitch="):
			var pd = deg_to_rad(float(a.substr(11)))
			var hd = Vector3(cam.dir.x, 0, cam.dir.z).normalized()
			cam.dir = (hd * cos(pd) + Vector3.UP * sin(pd)).normalized()
		elif a.begins_with("--burst="):
			var bw = a.substr(8).split(",")
			dbg_burst_n = int(bw[0]); dbg_burst_step = int(bw[1]) if bw.size() > 1 else 20
		elif a.begins_with("--sh="):
			var w2 = a.substr(5).split(",")
			dbg_sh = Array(w2)
		elif a.begins_with("--staff="): dbg_staff = a.substr(8)
		elif a.begins_with("--big="): dbg_big = int(a.substr(6))
		elif a.begins_with("--wmax="): dbg_wmax = int(a.substr(7))
		elif a.begins_with("--speed="): dbg_speed = int(a.substr(8))
		elif a.begins_with("--audit="):
			var au = load("res://harness/audit.gd").new()
			au.game = self; au.frames_left = int(a.substr(8))
			view.audit_all = true
			add_child(au); dbg_audit = au
		elif a.begins_with("--trace=") and dbg_audit: dbg_audit.trace_room = a.substr(8)
		elif a.begins_with("--ashot=") and dbg_audit: dbg_audit.shot_dir = a.substr(8)

var dbg_sh: Array = []
var dbg_burst_n = 0
var dbg_burst_step = 20
var burst_i = -1
var burst_wait = 0
func _apply_sh_dbg() -> void:
	if dbg_sh.size() >= 5:
		sun.directional_shadow_max_distance = float(dbg_sh[0]); sun.shadow_bias = float(dbg_sh[1])
		sun.shadow_normal_bias = float(dbg_sh[2]); sun.shadow_blur = float(dbg_sh[3])
		RenderingServer.directional_shadow_atlas_set_size(int(dbg_sh[4]), true)

func _env() -> void:
	env = WorldEnvironment.new()
	var e = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#1d2a33")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.78, 0.82, 0.88)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.15
	e.adjustment_contrast = 1.05
	e.tonemap_exposure = 0.85
	e.tonemap_white = 3.0
	e.glow_enabled = true
	e.glow_intensity = 0.3
	e.glow_bloom = 0.03
	e.glow_hdr_threshold = 1.1
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_blur = 1.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.8
	RenderingServer.directional_shadow_atlas_set_size(4096, true)
	add_child(sun)

func set_gfx(q: String, persist := true) -> void:
	gfx = q
	var vp = get_viewport()
	match q:
		"low":
			sun.shadow_enabled = false
			vp.scaling_3d_scale = 0.7
			vp.msaa_3d = Viewport.MSAA_DISABLED
			env.environment.glow_enabled = false
		"medium":
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 80.0
			vp.scaling_3d_scale = 0.85
			vp.msaa_3d = Viewport.MSAA_2X
			env.environment.glow_enabled = true
		_:
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 90.0
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_4X
			env.environment.glow_enabled = true
	if persist: _save_settings()

# ---------- loop ----------
func _process(delta: float) -> void:
	if sim.S.is_empty(): return
	var dt = minf(delta, 0.1)
	if auto_play and ap:
		ap_frame += 1
		if ap_frame % 30 == 0: ap.tick()
	sim.step(dt)
	_events()
	var gdt = dt * sim.speed   # animations advance in game time
	view.sync(gdt)
	_sync_ghost()
	hud.tick(dt)
	autosave_t += dt
	# auto quality: on a fresh install drop to «низкая» if the device can't hold ~40 fps
	if not gfx_user and gfx != "low":
		perf_t += delta; perf_n += 1
		if perf_t > 6.0:
			if perf_n / perf_t < 40.0:
				set_gfx("low"); gfx_user = true
			perf_t = 0.0; perf_n = 0
	if autosave_t > 60:
		autosave_t = 0
		save_game(true)
	if dbg_focus == "leaf" and view.wb and not view.wb.doors.is_empty():
		var lf = view.wb.doors.values()[int(dbg_watch_q * 10) % view.wb.doors.size()]
		cam.focus = Vector3(lf.position.x, 0, lf.position.z); cam.apply()
		print("LEAF ", view.wb.doors.keys(), " ", lf.position)
		dbg_focus = "leaf_done"
	if dbg_watch != "":
		var hit = null
		if dbg_watch.begins_with("s_"):
			for q in sim.S.staff:
				if q.type == dbg_watch.substr(2): hit = q; break
			if hit:
				cam.focus = Vector3(hit.x + .5, 0, hit.y + .5); cam.apply()
			hit = null
		for p in sim.S.pats:
			if p.state == "treat":
				var r = sim.room_by_id(p.get("room"))
				if r and r.type == dbg_watch: hit = p; break
		if hit:
			cam.focus = Vector3(hit.x + .5, 0, hit.y + .5)
			cam.apply()
		dbg_watch_n += 1
		if dbg_watch.begins_with("seat:"):
			# debug: follow someone seated on a given seat kind (sofa / chair / bench ...)
			var ok = false
			if dbg_watch_n % 120 == 0:
				for q in sim.S.staff + sim.S.pats:
					if q.get("vs"): print("SEATW ", q.id, " ", q.vs.pose, " ", q.vs.ph, " ", q.vs.t, " ", q.vs.get("sp"))
			for q in sim.S.staff + sim.S.pats:
				var qv = q.get("vs")
				if qv and qv.ph == "sat" and qv.pose == "sit" and qv.get("sp") and str(qv.sp.get("seat")) == dbg_watch.substr(5) and float(qv.t) > 1.2:
					cam.focus = Vector3(q.x + .5, 0, q.y + .5); cam.apply(); ok = true; break
			if shot_frames == 1 and not ok and dbg_watch_n < dbg_wmax: shot_frames = 2
		elif shot_frames == 1 and not dbg_watch.begins_with("s_") and dbg_watch_n < dbg_wmax and (hit == null or CharPuppet.procQ(hit) < dbg_watch_q):
			shot_frames = 2
	if shot_frames >= 0:
		shot_frames -= 1
		if shot_frames == 0 and shot_path != "":
			if dbg_burst_n > 0:
				burst_i = 0; burst_wait = 0
				shot_frames = -1
			else:
				get_viewport().get_texture().get_image().save_png(shot_path)
				get_tree().quit()
	if burst_i >= 0:
		burst_wait -= 1
		if burst_wait <= 0:
			get_viewport().get_texture().get_image().save_png(shot_path.replace(".png", "_%02d.png" % burst_i))
			burst_i += 1; burst_wait = dbg_burst_step
			if burst_i >= dbg_burst_n: get_tree().quit()

func _events() -> void:
	var ev: Array = sim.events
	if ev.is_empty(): return
	sim.events = []
	for e in ev:
		match e[0]:
			"snd": snd(e[1])
			"won":
				_mark_done(sim.S.lv)
				save_game(true)
				hud.show_win()
			"lost":
				_delete_save(sim.S.lv)
				hud.show_lose(e[1])
			"modal": hud.show_info("", str(e[1]))
			"autosave": save_game(true)
			"quake": cam.shake(1.2)
			"explode": cam.shake(0.6)
			"died": view.on_died(e[1])
			"healed": view.on_healed(e[1])

func snd(n: String) -> void:
	if snd_node: snd_node.play(n)
func click() -> void: snd("click")

func set_speed(s: int) -> void:
	if sim.S.get("won") and s > 0 and hud.modal_bg.visible: return
	sim.speed = s

func on_modal_closed() -> void:
	pass

func _dbg_ui() -> void:
	for u in dbg_ui.split("+", false):
		var a = u.split(":")
		match a[0]:
			"rooms": hud.show_rooms()
			"hire": hud.show_hire()
			"staff": hud.show_staff()
			"goals": hud.show_goals()
			"menu": hud.show_menu()
			"levels": hud.show_levels()
			"win": hud.show_win()
			"lose": hud.show_lose("Репутация упала ниже допустимой.")
			"ghost": start_room(a[1])
			"ok":
				ghost_ok(); print("GHOST after ok: ", ghost, " rooms ", sim.S.rooms.size())
			"item": pick_item(a[1])
			"pat":
				for p in sim.S.pats:
					if p.state == a[1] if a.size() > 1 else true:
						hud.show_sel({"k": "pat", "id": p.id}); break
			"room":
				var r = sim.first_room(a[1])
				if r: hud.show_sel({"k": "room", "id": r.id})

# ---------- levels / progress ----------
func progress() -> Dictionary:
	if not FileAccess.file_exists(PROG_FILE): return {"done": []}
	var j = JSON.parse_string(FileAccess.get_file_as_string(PROG_FILE))
	if j == null or not j is Dictionary: return {"done": []}
	var done = []
	for x in j.get("done", []): done.append(int(x))
	return {"done": done}

func _mark_done(i: int) -> void:
	var p = progress()
	if not i in p.done: p.done.append(i)
	var f = FileAccess.open(PROG_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(p))

func unlocked(i: int) -> bool:
	return i == 0 or (i - 1) in progress().done

func start_level(i: int) -> void:
	hud.close_modal()
	hud.close_panel()
	cancel_modes()
	sim.newGame(i)
	_after_new()
	set_speed(1)
	var intro = sim.L().get("intro")
	if intro: hud.show_info("🏥 " + sim.L().name, str(intro))

func _after_new() -> void:
	in_game = true
	view.sig = ""
	hud.reset_msgs()
	center_cam()
	if auto_play:
		ap = AutoPlayer.new(sim)

func show_levels() -> void:
	set_speed(0)
	hud.show_levels()

func center_cam() -> void:
	var S: Dictionary = sim.S
	cam.map_size = Vector2(S.w, S.h)
	cam.focus = Vector3(S.ent.x + 0.5, 0, S.h - 7.0)
	var vsz = get_viewport().get_visible_rect().size
	cam.zoom = 16.0 if vsz.y > vsz.x else 22.0
	cam.apply()

# ---------- saves ----------
func slot_path(lv: int) -> String: return "user://" + SAVE_KEY + "_L" + str(lv) + ".json"
func has_save(lv: int) -> bool: return FileAccess.file_exists(slot_path(lv))
func _last_lv() -> int:
	var st = _settings()
	return int(st.get("last", -1))
func _delete_save(lv: int) -> void:
	if has_save(lv): DirAccess.remove_absolute(slot_path(lv))

func save_game(silent: bool) -> void:
	if sim.S.get("lost"):
		if not silent: sim.msg("Проигранную игру нельзя сохранить")
		return
	var f = FileAccess.open(slot_path(sim.S.lv), FileAccess.WRITE)
	if f == null:
		sim.msg("Ошибка сохранения"); return
	f.store_string(sim.save_json())
	var st = _settings(); st.last = sim.S.lv; _write_settings(st)
	if not silent: sim.msg("💾 Игра сохранена")

func load_game(lv := -1) -> bool:
	if lv < 0: lv = int(sim.S.lv) if not sim.S.is_empty() else _last_lv()
	if not has_save(lv):
		sim.msg("Нет сохранения"); return false
	return _load_text(FileAccess.get_file_as_string(slot_path(lv)))

func _load_text(t: String) -> bool:
	var j = JSON.parse_string(t)
	if j == null or not j is Dictionary or not j.has("S"):
		sim.msg("⚠ Не удалось прочитать сохранение"); return false
	cancel_modes()
	sim.load_state(j.S)
	view.sig = ""
	hud.reset_msgs()
	center_cam()
	sim.msg("📂 Игра загружена")
	in_game = true
	return true

# 45.x importer: the WebView localStorage is not reachable from a native app, so the player copies the save JSON
# (value of hohotun_trial45_save_v1_L<n>) to the clipboard / a file; both {"S":..,"v":1} and bare S are accepted.
func import_clipboard() -> void:
	var t = DisplayServer.clipboard_get().strip_edges()
	if t == "":
		hud.show_info("📋 Импорт", "Буфер обмена пуст. Скопируйте JSON сохранения 45.x (ключ " + SAVE_KEY + "_L<номер>) и нажмите снова.")
		return
	import_text(t)

func import_text(t: String) -> bool:
	var j = JSON.parse_string(t)
	if j is Dictionary and not j.has("S") and j.has("rooms") and j.has("lv"):
		t = JSON.stringify({"S": j, "v": 1})
	if _load_text(t):
		save_game(true)
		sim.msg("📥 Сохранение 45.x импортировано")
		return true
	return false

func export_clipboard() -> void:
	DisplayServer.clipboard_set(sim.save_json())
	sim.msg("📤 Сохранение скопировано в буфер обмена")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if sim and not sim.S.is_empty() and in_game: save_game(true)

# ---------- settings ----------
func _settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_FILE): return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_FILE))
	return j if j is Dictionary else {}
func _write_settings(st: Dictionary) -> void:
	var f = FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(st))
func _load_settings() -> void:
	var st = _settings()
	sound_on = st.get("sound", true)
	gfx = st.get("gfx", "medium" if OS.get_name() == "Android" else "high")
	gfx_user = st.has("gfx")
func _save_settings() -> void:
	var st = _settings(); st.sound = sound_on; st.gfx = gfx; _write_settings(st)
func toggle_sound() -> void:
	sound_on = not sound_on
	snd_node.on = sound_on
	_save_settings()

# ---------- building ----------
func cancel_modes() -> void:
	ghost_cancel()
	item_done()

func start_room(type: String) -> void:
	item_done()
	var d: Dictionary = sim.drm(type)
	if sim.roomLocked(type):
		sim.msg("🔬 Сначала исследуйте «" + d.name + "»"); snd("bad"); return
	if sim.S.money < d.cost:
		sim.msg("Недостаточно денег"); return
	hud.close_panel()
	var c = cam.focus
	ghost = {"type": type, "w": int(d.min[0]) + 2, "h": int(d.min[1]) + 2, "side": 0, "x": int(floor(c.x)) - 2, "y": int(floor(c.z)) - 2}
	sim.ui.ghost = ghost
	hud.show_build_bar_room()

func ghost_size(dw: int, dh: int) -> void:
	if ghost == null: return
	sim.gsz_clamp(ghost, dw, dh)
func ghost_preset(n: int) -> void:
	if ghost == null: return
	sim.v24Pre(ghost, n)
func ghost_door() -> void:
	if ghost == null: return
	ghost.side = (int(ghost.side) + 1) % 4
func ghost_ok() -> void:
	if ghost == null: return
	var r = sim.buildRoom(ghost)
	if r is String:
		snd("bad"); return
	# built (v25 buildRoom returns null on success): leave build mode, no new ghost
	snd("build")
	ghost_cancel()
func ghost_cancel() -> void:
	ghost = null
	sim.ui.ghost = null
	hud.hide_build_bar()
	for c in ghost_node.get_children(): c.queue_free()

func pick_item(k: String) -> void:
	ghost_cancel()
	item_mode = k
	sim.ui.mode = {"item": k}
	hud.close_panel()
	ig = Vector2i(int(floor(cam.focus.x)), int(floor(cam.focus.z)))
	hud.show_build_bar_item(k)
	_item_ghost_rebuild()
func item_rotate() -> void:
	sim.v41Rot()
	_item_ghost_rebuild()
func item_confirm() -> void:
	if item_mode == null: return
	var res = sim.placeItem(item_mode, ig.x, ig.y, sim.ui.get("v41rot"))
	if res is Dictionary:
		snd("build")
		_item_ghost_rebuild()
func item_done() -> void:
	item_mode = null
	sim.ui.mode = null
	hud.hide_build_bar()
	for c in item_ghost.get_children(): c.queue_free()

var _ig_key = ""
func _item_ghost_rebuild() -> void:
	for c in item_ghost.get_children(): c.queue_free()
	_ig_key = ""

var _gh_key = ""
var _gh_mat_ok: StandardMaterial3D
var _gh_mat_bad: StandardMaterial3D
func _sync_ghost() -> void:
	if _gh_mat_ok == null:
		_gh_mat_ok = Geo.mat(Color(0.2, 1, 0.2, 0.28), 0.8); _gh_mat_ok.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_gh_mat_ok.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_gh_mat_bad = Geo.mat(Color(1, 0.15, 0.15, 0.3), 0.8); _gh_mat_bad.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_gh_mat_bad.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if ghost != null:
		var bad = sim.validRoom(ghost)
		if sim.roomLocked(ghost.type): bad = "не исследовано"
		var key = str(ghost.x, ",", ghost.y, ",", ghost.w, ",", ghost.h, ",", ghost.side, ",", bad == null, ",", sim.S.rooms.size())
		if key != _gh_key:
			_gh_key = key
			for c in ghost_node.get_children(): c.queue_free()
			var m: Material = _gh_mat_ok if bad == null else _gh_mat_bad
			var gw: float = ghost.w
			var gh: float = ghost.h
			Geo.box(ghost_node, Vector3(gw - 0.04, 0.06, gh - 0.04), m, Vector3(ghost.x + gw / 2.0, 0.03, ghost.y + gh / 2.0), 0.0)
			# walls outline
			for e in [[Vector3(gw, 0.5, 0.18), Vector3(ghost.x + gw / 2.0, 0.25, ghost.y + 0.5)], [Vector3(gw, 0.5, 0.18), Vector3(ghost.x + gw / 2.0, 0.25, ghost.y + gh - 0.5)], [Vector3(0.18, 0.5, gh), Vector3(ghost.x + 0.5, 0.25, ghost.y + gh / 2.0)], [Vector3(0.18, 0.5, gh), Vector3(ghost.x + gw - 0.5, 0.25, ghost.y + gh / 2.0)]]:
				Geo.box(ghost_node, e[0], m, e[1], 0.0)
			# door marker (arrow)
			var dp = _ghost_door_tile(ghost)
			var dm = Geo.mat(Color(1, 0.85, 0.2), 0.5)
			Geo.box(ghost_node, Vector3(0.8, 0.9, 0.8), dm, Vector3(dp.x + 0.5, 0.45, dp.y + 0.5), 0.05)
			var lab = Label3D.new()
			lab.text = sim.drm(ghost.type).name + ("" if bad == null else "\n⚠ " + str(bad))
			lab.font_size = 56; lab.pixel_size = 0.009; lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED; lab.outline_size = 10
			lab.no_depth_test = true
			lab.modulate = Color(0.85, 1, 0.85) if bad == null else Color(1, 0.75, 0.75)
			lab.position = Vector3(ghost.x + gw / 2.0, 1.6, ghost.y + gh / 2.0)
			ghost_node.add_child(lab)
	if item_mode != null:
		var rot = sim.ui.get("v41rot")
		var d = rot if rot != null else sim.v41AutoDir(item_mode, ig.x, ig.y)
		var fp: Array = sim.fpDir(item_mode, d if d != null else 1)
		var ok: bool = sim.v41Fits(item_mode, ig.x, ig.y, d if d != null else 1)
		var key = str(item_mode, ig, d, ok, sim.S.items.size())
		if key != _ig_key:
			_ig_key = key
			for c in item_ghost.get_children(): c.queue_free()
			Furn.build(item_ghost, item_mode, ig.x, ig.y, fp, d)
			var m: Material = _gh_mat_ok if ok else _gh_mat_bad
			Geo.box(item_ghost, Vector3(fp[0] - 0.06, 0.04, fp[1] - 0.06), m, Vector3(ig.x + fp[0] / 2.0, 0.02, ig.y + fp[1] / 2.0), 0.0)

func _ghost_door_tile(g: Dictionary) -> Vector2i:
	var cx: int = g.x + int(floor(g.w / 2.0))
	var cy: int = g.y + int(floor(g.h / 2.0))
	match int(g.side):
		0: return Vector2i(cx, g.y + g.h - 1)
		1: return Vector2i(g.x + g.w - 1, cy)
		2: return Vector2i(cx, g.y)
		_: return Vector2i(g.x, cy)

# ---------- input ----------
func _ground(sp: Vector2) -> Vector2:
	var o = cam.project_ray_origin(sp)
	var d = cam.project_ray_normal(sp)
	if absf(d.y) < 1e-5: return Vector2(-1, -1)
	var t = -o.y / d.y
	var p = o + d * t
	return Vector2(p.x, p.z)

func _on_drag_start(sp: Vector2) -> bool:
	# start dragging the room ghost / item ghost when the finger lands on it
	var w = _ground(sp)
	if ghost != null and w.x >= ghost.x and w.y >= ghost.y and w.x < ghost.x + ghost.w and w.y < ghost.y + ghost.h:
		drag_ghost = Vector2(w.x - ghost.x, w.y - ghost.y)
		return true
	if item_mode != null and absf(w.x - ig.x - 0.5) < 1.2 and absf(w.y - ig.y - 0.5) < 1.2:
		drag_ghost = Vector2(w.x - ig.x, w.y - ig.y)
		return true
	drag_ghost = null
	return false

func _on_drag(sp: Vector2) -> void:
	if drag_ghost == null: return
	var w = _ground(sp)
	if ghost != null:
		ghost.x = int(floor(w.x - drag_ghost.x + 0.5))
		ghost.y = int(floor(w.y - drag_ghost.y + 0.5))
	elif item_mode != null:
		ig = Vector2i(int(floor(w.x - drag_ghost.x + 0.5)), int(floor(w.y - drag_ghost.y + 0.5)))

func _on_tap(sp: Vector2) -> void:
	var w = _ground(sp)
	var x = int(floor(w.x))
	var y = int(floor(w.y))
	if ghost != null:
		ghost.x = x - int(floor(ghost.w / 2.0)); ghost.y = y - int(floor(ghost.h / 2.0))
		return
	if item_mode != null:
		ig = Vector2i(x, y)
		return
	var id = view.puppet_at_screen(sp, 36.0)
	if id != null:
		if sim.pat_by_id(id) != null:
			hud.show_sel({"k": "pat", "id": id}); click(); return
		if sim.staff_by_id(id) != null:
			hud.show_sel({"k": "staff", "id": id}); click(); return
	var li = sim.lotAt(x, y)
	if li != null:
		var idx: int = sim.S.lots.find(li)
		if idx >= 0 and not li.own:
			hud.show_lot(idx); click(); return
	var r = sim.roomAt(x, y)
	if r != null:
		hud.show_sel({"k": "room", "id": r.id}); click(); return
	hud.close_panel()
