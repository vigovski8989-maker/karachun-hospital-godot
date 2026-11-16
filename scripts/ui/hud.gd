# HUD + panels + modals (port of game.js/v11/v12/v17/v18/v24/v25/v41/v42 UI), all texts in Russian as in 45.x
class_name Hud
extends Control

var game   # GameMain
var sim
var top_money: Label
var top_rep: Label
var top_date: Label
var top_cured: Label
var chips_box: HFlowContainer
var speed_btns = {}
var msg_box: VBoxContainer
var build_bar: HFlowContainer
var panel: PanelContainer
var panel_vb: VBoxContainer
var panel_scroll: ScrollContainer
var modal_bg: ColorRect
var modal_vb: VBoxContainer
var modal_panel: PanelContainer
var tut_lbl: Label
var tut_box: PanelContainer
var bar: HBoxContainer
var panel_kind = ""
var panel_arg = null
var refresh_t = 0.0
var shown_msgs = 0
var ghost_info: Label
var ghost_ok: Button
var item_rot_btn: Button
var hud_t = 0.0
var bottom_pc: PanelContainer
var _last_chips = ""

func _ready() -> void:
	theme = UIKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top()
	_build_msgs()
	_build_tut()
	_build_bottom()
	_build_buildbar()
	_build_panel()
	_build_modal()

# ---------- layout ----------
func _build_top() -> void:
	var pc = PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UIKit.bar_style())
	pc.set_anchors_preset(Control.PRESET_TOP_WIDE)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(pc)
	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	pc.add_child(hb)
	top_money = _stat(hb, "💰")
	top_rep = _stat(hb, "⭐")
	top_date = _stat(hb, "📅")
	top_cured = _stat(hb, "✅")
	chips_box = HFlowContainer.new()
	chips_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips_box.add_theme_constant_override("h_separation", 4)
	chips_box.add_theme_constant_override("v_separation", 2)
	hb.add_child(chips_box)
	var sp = HBoxContainer.new()
	sp.add_theme_constant_override("separation", 4)
	hb.add_child(sp)
	for s in [[0, "⏸"], [1, "▶"], [2, "▶▶"], [4, "▶▶▶"]]:
		var b = Button.new()
		b.text = s[1]
		b.custom_minimum_size = Vector2(52, 40)
		var spd: int = s[0]
		b.pressed.connect(func(): game.set_speed(spd))
		sp.add_child(b)
		speed_btns[spd] = b

func _stat(hb: HBoxContainer, icon: String) -> Label:
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var i = Label.new(); i.text = icon
	h.add_child(i)
	var l = Label.new()
	l.add_theme_font_override("font", UIKit.font_800)
	l.add_theme_color_override("font_color", UIKit.C_GOLD)
	h.add_child(l)
	hb.add_child(h)
	return l

func _build_msgs() -> void:
	msg_box = VBoxContainer.new()
	msg_box.position = Vector2(8, 66)
	msg_box.custom_minimum_size = Vector2(560, 0)
	msg_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg_box.add_theme_constant_override("separation", 2)
	add_child(msg_box)

func _build_tut() -> void:
	tut_box = PanelContainer.new()
	var sb = UIKit.chip_style(Color(0.95, 0.75, 0.2, 0.95))
	sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	tut_box.add_theme_stylebox_override("panel", sb)
	tut_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tut_box.position = Vector2(0, 66)
	tut_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tut_lbl = Label.new()
	tut_lbl.add_theme_color_override("font_color", Color(0.15, 0.1, 0.0))
	tut_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tut_lbl.custom_minimum_size = Vector2(420, 0)
	tut_box.add_child(tut_lbl)
	tut_box.visible = false
	add_child(tut_box)

func _build_bottom() -> void:
	var pc = PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UIKit.bar_style())
	pc.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	pc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(pc)
	bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	pc.add_child(bar)
	pc.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE)
	bottom_pc = pc
	for b in [["🏗", "Кабинеты", show_rooms], ["🪴", "Предметы", show_items], ["👩‍⚕️", "Нанять", show_hire], ["👥", "Персонал", show_staff], ["🎯", "Цели", show_goals], ["☰", "Меню", show_menu]]:
		var bt = Button.new()
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bt.custom_minimum_size = Vector2(0, 62)
		var vb = VBoxContainer.new()
		vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", -2)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for t in [[b[0], 28], [b[1], 15]]:
			var l = Label.new(); l.text = t[0]; l.add_theme_font_size_override("font_size", t[1])
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if t[1] == 15: l.add_theme_font_override("font", UIKit.font_800)
			vb.add_child(l)
		bt.add_child(vb)
		var cb: Callable = b[2]
		bt.pressed.connect(func(): game.click(); cb.call())
		bar.add_child(bt)
	call_deferred("_fix_bottom")

func _fix_bottom() -> void:
	if OS.get_cmdline_user_args().has("--dbgui"): print("HUD size ", size, " vp ", get_viewport_rect().size, " bottom ", bottom_pc.get_global_rect())
	bottom_pc.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE)

func _build_buildbar() -> void:
	build_bar = HFlowContainer.new()
	build_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	build_bar.offset_top = -150; build_bar.offset_bottom = -76
	build_bar.alignment = FlowContainer.ALIGNMENT_CENTER
	build_bar.add_theme_constant_override("h_separation", 6)
	build_bar.add_theme_constant_override("v_separation", 6)
	build_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_bar.visible = false
	add_child(build_bar)

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 8; panel.offset_right = -8
	panel.offset_bottom = -78
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	panel_scroll = ScrollContainer.new()
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(panel_scroll)
	panel_vb = VBoxContainer.new()
	panel_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_vb.add_theme_constant_override("separation", 2)
	panel_scroll.add_child(panel_vb)
	panel.visible = false

func _build_modal() -> void:
	modal_bg = ColorRect.new()
	modal_bg.color = Color(0, 0, 0, 0.6)
	modal_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal_bg)
	var cc = CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_bg.add_child(cc)
	modal_panel = PanelContainer.new()
	var sb: StyleBoxFlat = UIKit.theme().get_stylebox("panel", "PanelContainer").duplicate()
	sb.bg_color = Color("#20384a")
	modal_panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(modal_panel)
	var sc = ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(560, 0)
	modal_panel.add_child(sc)
	modal_vb = VBoxContainer.new()
	modal_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_vb.add_theme_constant_override("separation", 6)
	sc.add_child(modal_vb)
	modal_bg.visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and panel:
		_fit()

func _fit() -> void:
	var vh = get_viewport_rect().size.y
	panel_scroll.custom_minimum_size.y = 0
	var want = panel_vb.get_combined_minimum_size().y
	panel_scroll.custom_minimum_size = Vector2(0, minf(want, vh * 0.58))
	var sc: ScrollContainer = modal_panel.get_child(0)
	var mw = modal_vb.get_combined_minimum_size().y
	sc.custom_minimum_size = Vector2(minf(620, get_viewport_rect().size.x - 40), minf(mw, vh - 60))

# ---------- frame update ----------
func tick(dt: float) -> void:
	if sim == null or sim.S.is_empty(): return
	hud_t -= dt
	if hud_t <= 0:
		hud_t = 0.25
		_hud()
	_msgs()
	if panel.visible and panel_kind in ["sel_room", "sel_pat", "sel_staff", "staff", "goals"]:
		refresh_t -= dt
		if refresh_t <= 0:
			refresh_t = 1.0
			_reopen()
	if build_bar.visible and game.ghost != null and ghost_info:
		ghost_info.text = sim.ghostLabel(game.ghost)
		ghost_ok.text = "✔ $" + str(sim.roomBuildCost(game.ghost))

func _hud() -> void:
	var S: Dictionary = sim.S
	top_money.text = "$" + str(int(S.money))
	top_money.add_theme_color_override("font_color", Color("#f66") if S.money < 0 else UIKit.C_GOLD)
	top_rep.text = str(int(round(S.rep)))
	var m = int(floor(S.day / float(sim.MONTH_DAYS)))
	top_date.text = "Мес " + str(m + 1) + ", день " + str(int(S.day) % sim.MONTH_DAYS + 1)
	top_cured.text = str(int(S.cured)) + "/" + str(int(sim.L().goals.cured))
	var ch: Array = sim.chips()
	var key = str(ch)
	if key != _last_chips:
		_last_chips = key
		for c in chips_box.get_children(): c.queue_free()
		for c in ch:
			var pc = PanelContainer.new()
			var col = Color("#345") if str(c[1]) == "" else Color(str(c[1]))
			pc.add_theme_stylebox_override("panel", UIKit.chip_style(col))
			var l = Label.new(); l.text = c[0]; l.add_theme_font_size_override("font_size", 15)
			pc.add_child(l)
			if str(c[0]).begins_with("🏆"):
				pc.mouse_filter = Control.MOUSE_FILTER_STOP
				pc.gui_input.connect(func(ev): if ev is InputEventMouseButton and ev.pressed: show_rank())
			chips_box.add_child(pc)
	for s in speed_btns:
		var b: Button = speed_btns[s]
		UIKit.style_btn(b, "on" if s == sim.speed else "blue")
	var ts: int = sim.tutStep() if not S.get("tutOff") else -1
	tut_box.visible = ts >= 0 and not panel.visible and not modal_bg.visible
	if ts >= 0: tut_lbl.text = "🎓 " + sim.TUT_TEXT[ts]
	tut_box.position.x = (get_viewport_rect().size.x - tut_box.size.x) / 2.0

func _msgs() -> void:
	var now = Time.get_ticks_msec() / 1000.0
	while shown_msgs < sim.msgs.size():
		var m = sim.msgs[shown_msgs]
		shown_msgs += 1
		var pc = PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UIKit.chip_style(Color(0, 0, 0, 0.5)))
		var l = Label.new(); l.text = m.text; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 16)
		pc.add_child(l)
		pc.set_meta("t", now)
		msg_box.add_child(pc)
		msg_box.move_child(pc, 0)
		while msg_box.get_child_count() > 3:
			var last = msg_box.get_child(msg_box.get_child_count() - 1)
			msg_box.remove_child(last); last.queue_free()
	for c in msg_box.get_children():
		var age: float = now - float(c.get_meta("t"))
		c.modulate.a = clampf(1.0 - (age - 5.0) / 0.8, 0, 1)
		if age > 5.8:
			msg_box.remove_child(c); c.queue_free()

func reset_msgs() -> void:
	shown_msgs = sim.msgs.size()
	for c in msg_box.get_children(): c.queue_free()

# ---------- panel builder ----------
func _clear(vb: VBoxContainer) -> void:
	for c in vb.get_children():
		vb.remove_child(c); c.queue_free()

func open_panel(kind: String, arg = null) -> void:
	panel_kind = kind; panel_arg = arg
	_clear(panel_vb)
	panel.visible = true
	refresh_t = 1.0

func close_panel() -> void:
	panel.visible = false
	panel_kind = ""

func finish_panel() -> void:
	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_child(btn("Закрыть", func(): close_panel()))
	panel_vb.add_child(hb)
	call_deferred("_fit")

func _reopen() -> void:
	var sc = panel_scroll.scroll_vertical
	match panel_kind:
		"sel_room": show_sel({"k": "room", "id": panel_arg})
		"sel_pat": show_sel({"k": "pat", "id": panel_arg})
		"sel_staff": show_sel({"k": "staff", "id": panel_arg})
		"staff": show_staff()
		"goals": show_goals()
	panel_scroll.set_deferred("scroll_vertical", sc)

func h3(t: String, vb: VBoxContainer = null) -> void:
	var l = Label.new(); l.text = t
	l.add_theme_font_override("font", UIKit.font_800)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color("#e9f4ff"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(vb if vb else panel_vb).add_child(l)
	var sep = ColorRect.new(); sep.color = Color(110 / 255.0, 180 / 255.0, 235 / 255.0, 0.35); sep.custom_minimum_size = Vector2(0, 2)
	(vb if vb else panel_vb).add_child(sep)

func h4(t: String, vb: VBoxContainer = null) -> void:
	var l = Label.new(); l.text = t
	l.add_theme_font_override("font", UIKit.font_800)
	(vb if vb else panel_vb).add_child(l)

func small(t: String, vb: VBoxContainer = null) -> void:
	var l = Label.new(); l.text = t
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color("#9bb"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	(vb if vb else panel_vb).add_child(l)

func btn(t: String, cb: Callable, kind := "", disabled := false) -> Button:
	var b = Button.new(); b.text = t
	b.disabled = disabled
	b.pressed.connect(func(): game.click(); cb.call())
	UIKit.style_btn(b, kind)
	return b

# row: left title (bold optional) + optional small subtitle, right = String value or Array[Button]
func row(left: String, right = null, sub := "", vb: VBoxContainer = null, bold := false, right_col = null) -> HBoxContainer:
	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var lv = VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_theme_constant_override("separation", 0)
	var l = Label.new(); l.text = left
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(160, 0)
	if bold: l.add_theme_font_override("font", UIKit.font_800)
	lv.add_child(l)
	if sub != "":
		var s = Label.new(); s.text = sub
		s.add_theme_font_size_override("font_size", 15)
		s.add_theme_color_override("font_color", Color("#9bb"))
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size = Vector2(160, 0)
		lv.add_child(s)
	hb.add_child(lv)
	if right is String:
		var r = Label.new(); r.text = right
		r.add_theme_font_override("font", UIKit.font_800)
		if right_col != null: r.add_theme_color_override("font_color", right_col)
		hb.add_child(r)
	elif right is Array:
		for b in right: hb.add_child(b)
	elif right is Control:
		hb.add_child(right)
	var cont = VBoxContainer.new()
	cont.add_theme_constant_override("separation", 0)
	cont.add_child(hb)
	var line = ColorRect.new(); line.color = Color("#345"); line.custom_minimum_size = Vector2(0, 1)
	cont.add_child(line)
	(vb if vb else panel_vb).add_child(cont)
	return hb

# ---------- modal ----------
func open_modal() -> void:
	_clear(modal_vb)
	modal_bg.visible = true

func close_modal() -> void:
	modal_bg.visible = false
	game.on_modal_closed()

func modal_title(t: String) -> void:
	var l = Label.new(); l.text = t
	l.add_theme_font_override("font", UIKit.font_800)
	l.add_theme_font_size_override("font_size", 28)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_vb.add_child(l)

func modal_text(t: String) -> void:
	var l = Label.new(); l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	modal_vb.add_child(l)

func modal_buttons(bs: Array) -> void:
	var hf = HFlowContainer.new()
	hf.alignment = FlowContainer.ALIGNMENT_CENTER
	hf.add_theme_constant_override("h_separation", 8)
	for b in bs: hf.add_child(b)
	modal_vb.add_child(hf)

func modal_done() -> void:
	call_deferred("_fit")

# ---------- screens ----------
func show_rooms() -> void:
	game.cancel_modes()
	open_panel("rooms")
	h3("🏗 Построить кабинет")
	var S: Dictionary = sim.S
	for k in sim.L().rooms:
		var d: Dictionary = sim.D.rooms[k]
		var lk: float = sim.lockCost(k)
		if lk > 0:
			row("🔒 " + d.name, null, "Исследование: " + str(int(floor(S.get("rp", 0)))) + "/" + str(int(lk)) + " очков (постройте Лабораторию исследований)", null, true)
			continue
		var kk: String = k
		row(d.name + " — $" + str(int(d.cost)), [btn("Строить", func(): game.start_room(kk), "", S.money < d.cost)], str(d.get("desc", "")) + ((" Персонал: " + sim.D.staff[d.staff].name) if d.get("staff") else ""), null, true)
	finish_panel()

func show_items() -> void:
	open_panel("items")
	h3("🪴 Предметы для коридора")
	small("Выберите предмет, наведите его на пол коридора и нажмите ✔ Поставить.")
	for k in sim.D.items:
		var d: Dictionary = sim.D.items[k]
		var kk: String = k
		row(d.name + " — $" + str(int(d.cost)), [btn("Выбрать", func(): game.pick_item(kk), "on" if game.item_mode == kk else "")], "", null, true)
	row("Режим размещения", [btn("Выйти", func(): game.item_done(); close_panel(), "red")])
	finish_panel()

func show_hire() -> void:
	open_panel("hire")
	h3("👩‍⚕️ Наём персонала")
	var S: Dictionary = sim.S
	for k in S.cands:
		h4(sim.D.staff[k].name)
		var arr: Array = S.cands[k]
		for i in arr.size():
			var c = arr[i]
			var kk: String = k
			var ii: int = i
			row(c.name, [btn("Нанять", func(): sim.hire(kk, ii); game.snd("click"); show_hire())], "Навык " + str(int(c.skill)) + " · $" + str(int(c.salary)) + "/мес")
	finish_panel()

func _skill_txt(s) -> String:
	var x = int(floor(float(s.get("xp", 0.0)) * 100))
	return str(int(s.skill)) + (("  +" + str(x) + "%") if x > 0 else "")

func show_staff() -> void:
	sim.v17Init()
	var S: Dictionary = sim.S
	open_panel("staff")
	h3("👥 Персонал (" + str(S.staff.size()) + ((" + " + str(S.away.size()) + " на курсах") if S.get("away") and S.away.size() else "") + ")")
	var list: Array = S.staff.duplicate()
	list.sort_custom(func(a, b): return int(a.get("room") != null or a.type == "handyman") < int(b.get("room") != null or b.type == "handyman"))
	for s in list:
		var r = sim.room_by_id(s.get("room"))
		var c: Array = sim.COURSE[s.type]
		var where = ""
		if r: where = "👔 Главврач" if r.type == "chief" else (("🔄 подменяет: " if s.get("cover") else "") + sim.drm(r.type).name)
		elif s.state == "read": where = "📚 в библиотеке"
		elif s.type == "handyman": where = "обход"
		else: where = "⚠ БЕЗ КАБИНЕТА"
		var bs = []
		var sid: int = s.id
		if s.skill < 100: bs.append(btn("🎓 $" + str(int(c[0])), func(): sim.sendCourse(sid); show_staff(), "", S.money < c[0]))
		if s.type == "doctor" and not s.get("spec") and s.skill >= 50: bs.append(btn("⚕", func(): show_spec(sid)))
		bs.append(btn("✖", func(): sim.fire(sid); show_staff(), "red"))
		row(sim.D.staff[s.type].name + " " + s.name + ((" · " + sim.SPEC[s.spec].n) if s.get("spec") else ""), bs, "Навык " + _skill_txt(s) + " · $" + str(int(s.salary)) + " · Устал. " + str(int(round(s.fat))) + "% · " + where)
	for a in S.get("away", []):
		row("🎓 " + a.s.name, null, "На курсах до дня " + str(int(a.back)) + " · +" + str(int(a.gain)) + " навыка" + ((" · " + sim.SPEC[a.spec].n) if a.get("spec") else ""))
	small("🎓 Курсы за счёт больницы: сотрудник отсутствует несколько дней и возвращается с ростом навыка. ⚕ — специализация для врача (навык ≥50). 📚 Библиотека: свободный персонал и отдыхающие сами повышают навык.")
	finish_panel()

func show_spec(id) -> void:
	var s = sim.staff_by_id(id)
	if s == null: return
	var c: Array = sim.COURSE.doctor
	open_panel("spec", id)
	h3("⚕ Специализация: " + s.name)
	small("Курсы $" + str(int(c[0] * 2)) + ", " + str(int(c[1] + 3)) + " дн., +" + str(int(c[2])) + " навыка и +8% к шансу излечения в профильных кабинетах.")
	for k in sim.SPEC:
		var kk: String = k
		var names: Array = sim.SPEC[k].rooms.map(func(t): return sim.drm(t).name)
		row(sim.SPEC[k].n, [btn("Отправить", func(): sim.specCourse(id, kk); show_staff(), "", sim.S.money < c[0] * 2)], ", ".join(names), null, true)
	finish_panel()

func show_goals() -> void:
	var S: Dictionary = sim.S
	var g: Dictionary = sim.L().goals
	var l: Dictionary = sim.L().lose
	var ok = func(a, b): return "✅ " if a >= b else "⬜ "
	open_panel("goals")
	h3("🎯 Цели: " + sim.L().name)
	row(ok.call(S.cured, g.cured) + "Вылечить пациентов", str(int(S.cured)) + "/" + str(int(g.cured)))
	row(ok.call(sim.netCash(), g.money) + "Баланс" + (" (за вычетом кредита)" if sim.gnum(S, "loan", 0) else ""), "$" + str(int(sim.netCash())) + "/$" + str(int(g.money)))
	row(ok.call(S.rep, g.rep) + "Репутация", str(int(round(S.rep))) + "/" + str(int(g.rep)))
	if g.get("value"): row(ok.call(sim.hospValue(), g.value) + "Стоимость больницы", "$" + str(int(sim.hospValue())) + "/$" + str(int(g.value)))
	if sim.gnum(S, "loan", 0): row("Кредит", "$" + str(int(S.loan)))
	if S.get("em"): row("🚑 ЧП «" + sim.D.dis[S.em.dis].name + "»", str(int(S.em.cured)) + "/" + str(int(S.em.n)) + " до дня " + str(int(S.em.until) + 1))
	if S.get("epi"): row("🦠 Заражённых", str(S.pats.filter(func(p): return p.get("inf")).size()))
	if sim.L().get("locked"): row("🔬 Очки исследований", str(int(floor(S.get("rp", 0)))))
	h4("Поражение если")
	small("Смертей ≥ " + str(int(l.deaths)) + " (сейчас " + str(int(S.deaths)) + ") · репутация < " + str(int(l.rep)) + " · 2 месяца подряд долг больше $10 000")
	sim.v18Init()
	row("😠 Ушли не дождавшись", str(int(S.v18.left)) + " (−$" + str(int(S.v18.lost)) + ")")
	small("Терпение падает от длинных очередей и долгого ожидания; лавки, растения, батареи, автомат с напитками и высокий рейтинг его сохраняют.")
	row("🏆 Рейтинг больниц: " + str(sim.myRank()) + " место из 5", [btn("Таблица", show_rank)])
	finish_panel()

func show_rank() -> void:
	var a: Array = sim.ranking()
	var rk = 0
	for i in a.size():
		if a[i].get("me"): rk = i
	open_panel("rank")
	h3("🏆 Рейтинг больниц")
	for i in a.size():
		var hb = row(str(i + 1) + ". " + a[i].name, str(int(a[i].v)))
		if a[i].get("me"): hb.get_child(0).get_child(0).add_theme_color_override("font_color", Color("#8f8"))
	small("Индекс = репутация, вылеченные и стоимость больницы. Место " + str(rk + 1) + " → поток пациентов ×" + ("%.2f" % sim.RANK_MUL[rk]) + ". Чем выше место, тем больше пациентов и состоятельных клиентов.")
	finish_panel()

func show_menu() -> void:
	var S: Dictionary = sim.S
	open_panel("menu")
	h3("☰ Меню")
	var gq: String = game.gfx
	row("Графика", [btn("Низкая", func(): game.set_gfx("low"); game.gfx_user = true; show_menu(), "on" if gq == "low" else ""), btn("Средняя", func(): game.set_gfx("medium"); game.gfx_user = true; show_menu(), "on" if gq == "medium" else ""), btn("Высокая", func(): game.set_gfx("high"); game.gfx_user = true; show_menu(), "on" if gq == "high" else "")])
	if sim.L().get("loanMax"): row("Банк / кредит", [btn("🏦", show_bank)])
	var mc: float = 0.6 if S.get("minCh") == null else float(S.minCh)
	var bs = []
	for v in [0.4, 0.6, 0.75]:
		var vv: float = v
		bs.append(btn(str(int(v * 100)) + "%", func(): S.minCh = vv; show_menu(), "on" if absf(mc - v) < 0.001 else ""))
	row("Лечить при шансе ≥", bs)
	row("Сохранить игру", [btn("💾", func(): game.save_game(false); close_panel())])
	row("Загрузить", [btn("📂", func(): game.load_game(); close_panel())])
	row("Импорт сохранения 45.x (JSON из буфера обмена)", [btn("📋", func(): game.import_clipboard(); close_panel())])
	row("Экспорт сохранения в буфер обмена", [btn("📤", func(): game.export_clipboard())])
	row("Выбор уровня", [btn("🗺", func(): close_panel(); game.show_levels())])
	row("Звук", [btn("🔊" if game.sound_on else "🔇", func(): game.toggle_sound(); show_menu())])
	row("Центрировать камеру", [btn("🎯", func(): game.center_cam())])
	small("Больница «Карачун» 3D (Godot) — оригинальная игра, вдохновлённая жанром симуляторов больниц.")
	finish_panel()

func show_bank() -> void:
	var S: Dictionary = sim.S
	var mx: float = sim.L().get("loanMax", 40000)
	open_panel("bank")
	h3("🏦 Банк")
	row("Долг", "$" + str(int(sim.gnum(S, "loan", 0))))
	row("Лимит", "$" + str(int(mx)))
	small("Процент " + str(int(round(float(sim.L().get("loanRate", 0.03)) * 100))) + "% в месяц")
	row("Взять $10 000", [btn("Взять", func(): sim.takeLoan(); show_bank(), "", sim.gnum(S, "loan", 0) + 10000 > mx)])
	row("Вернуть $10 000", [btn("Вернуть", func(): sim.repayLoan(); show_bank(), "", sim.gnum(S, "loan", 0) < 10000 or S.money < 10000)])
	finish_panel()

func show_sel(sel: Dictionary) -> void:
	var S: Dictionary = sim.S
	if sel.k == "room":
		var r = sim.room_by_id(sel.id)
		if r == null: close_panel(); return
		var d: Dictionary = sim.drm(r.type)
		var st = sim.staff_by_id(r.get("staff"))
		open_panel("sel_room", sel.id)
		h3(d.name)
		small(str(d.get("desc", "")))
		row("Персонал", ((st.name + " (" + str(int(st.skill)) + ")") if st else ("нет — наймите " + sim.D.staff[d.staff].name)) if d.get("staff") else "не нужен")
		row("Очередь", str(r.queue.size()))
		var cap = int(sim.rCap(r))
		var nS = int(r.get("nS", 1))
		var szs = ["S", "M", "L"]
		row("Размер / мест", str(int(r.w) - 2) + "×" + str(int(r.h) - 2) + " · " + ((szs[nS - 1] + " · " + str(nS) + " места") if nS > 1 else (szs[clampi(cap - 1, 0, 2)] + ((" (комфорт ×" + ("%.1f" % (1 + .3 * (cap - 1))) + ")") if cap > 1 else ""))))
		var grp: Array = sim.v25Group(r)
		if grp.size() >= 2:
			for i in grp.size():
				var s2 = grp[i]
				var st2 = sim.staff_by_id(s2.get("staff"))
				row("Место " + str(i + 1), (("👤 " + st2.name.split(" ")[0]) if st2 else "⚠️ нет персонала") + " · " + ("🩺" if s2.get("busy") != null else "—") + " · 👥" + str(s2.queue.size()))
		if d.get("machine"): row("Состояние аппарата", str(int(r.cond)) + "%")
		# v17 extras
		if r.type == "chief":
			var c = sim.chiefOf()
			row("Главврач", (c.name + " (" + str(int(c.skill)) + ")") if c else "не назначен")
			if c:
				small("Бонусы: −усталость персонала, рост навыков, экономия 8% зарплат ×" + ("%.2f" % sim.chiefK()) + (", +исследования" if sim.L().get("locked") else ""))
				row("Снять с должности", [btn("Снять", func(): sim.dismissChief(); show_sel(sel), "red")])
			h4("Назначить")
			var cand: Array = S.staff.filter(func(o): return (o.type == "doctor" or o.type == "nurse") and not is_same(o, c))
			cand.sort_custom(func(a, b): return a.skill > b.skill)
			for o in cand.slice(0, 6):
				var oid: int = o.id
				row(sim.D.staff[o.type].name + " " + o.name + " · " + str(int(o.skill)), [btn("👔", func(): sim.appointChief(oid); show_sel(sel), "grn")])
		elif r.type == "library":
			var rd: Array = S.staff.filter(func(o): return o.state == "read")
			row("Читают сейчас", str(rd.size()))
			for o in rd: small("📚 " + o.name + " · " + _skill_txt(o))
		elif r.type == "paygp":
			row("Доход с приёмов", "$" + str(int(S.v17.get("pay", 0))))
			small("💎 Сюда автоматически переводится самый опытный врач. Пациенты платят $" + str(sim.PAY_FEE) + " за приём.")
		elif st and st.get("cover"):
			row("🔄 Подмена", sim.D.staff[st.type].name + " " + st.name)
		var rid: int = r.id
		row("Продать (+$" + str(int(round(float(r.get("cost", d.cost)) / 2.0))) + ")", [btn("Продать", func(): sim.sellRoom(rid); close_panel(), "red")])
		finish_panel()
	elif sel.k == "pat":
		var p = sim.pat_by_id(sel.id)
		if p == null or p.state == "gone": close_panel(); return
		var dz: Dictionary = sim.D.dis[p.dis]
		open_panel("sel_pat", sel.id)
		h3(("🎩 VIP " if p.get("vip") else "🧍 ") + p.name + (" 🚑" if p.get("emg") else ""))
		var pid: int = p.id
		var no = sim.needOrgan(p)
		if no and p.known:
			var org: Array = sim.ORG[no]
			row(org[0] + " Нужен орган: " + org[1] + ((" — есть (" + str(int(round(p.organ.q * 100))) + "%)") if p.get("organ") else " — ждёт донора"), [] if p.get("organ") else [btn("Купить $" + str(sim.ORGAN_PRICE), func(): sim.buyOrgan(pid); show_sel(sel), "grn")])
		if p.get("inf"): row("🦠 Заразен!", [btn("💉 Вакцина $200", func(): sim.vacc(pid); close_panel(), "grn")])
		row("Болезнь", dz.name if p.known else "не определена")
		if p.known: small(str(dz.get("desc", "")))
		row("Уверенность диагноза", str(int(round(p.cert * 100))) + "%")
		if not p.get("vip"):
			var ch: float = sim.cureChance(p)
			row("Шанс излечения", str(int(round(ch * 100))) + "%", "", null, false, Color("#f88") if ch < .6 else Color("#8f8"))
			var hb = HBoxContainer.new(); hb.add_theme_constant_override("separation", 8)
			hb.add_child(btn("💊 Лечить сейчас", func(): sim.treatNow(pid); show_sel(sel), "grn"))
			hb.add_child(btn("🔍 Дообследовать", func(): sim.moreDiag(pid); show_sel(sel)))
			panel_vb.add_child(hb)
		row("Здоровье", str(int(round(p.health))) + "%")
		var v = maxi(0, int(round(p.pat)))
		var col = Color("#4c4") if v > 60 else (Color("#db3") if v > 30 else Color("#e44"))
		row("Терпение", str(v) + "%", "", null, false, col)
		var pb = ProgressBar.new(); pb.max_value = 100; pb.value = v; pb.show_percentage = false; pb.custom_minimum_size = Vector2(0, 6)
		var fsb = StyleBoxFlat.new(); fsb.bg_color = col; fsb.set_corner_radius_all(3)
		var bsb = StyleBoxFlat.new(); bsb.bg_color = Color("#333"); bsb.set_corner_radius_all(3)
		pb.add_theme_stylebox_override("fill", fsb); pb.add_theme_stylebox_override("background", bsb)
		panel_vb.add_child(pb)
		var f = p.get("_pf")
		if f: small("Уют ×" + ("%.2f" % f.c) + " (лавки, растения, батареи, туалет) · Очередь ×" + ("%.2f" % f.q) + " · Ожидание ×" + ("%.2f" % f.t) + (" · 🥤 автомат рядом" if f.soda < 1 else "") + " · Рейтинг ×" + ("%.2f" % f.rk))
		row("Направлен в", str(sim.D.rooms.get(p.need, {}).get("name", "—")))
		row("Отправить домой", [btn("Домой", func(): sim.leavePat(pid); close_panel(), "red")])
		finish_panel()
	else:
		var st = sim.staff_by_id(sel.id)
		if st == null: close_panel(); return
		open_panel("sel_staff", sel.id)
		h3(sim.D.staff[st.type].name + " " + st.name)
		row("Навык", _skill_txt(st))
		row("Зарплата", "$" + str(int(st.salary)))
		row("Усталость", str(int(round(st.fat))) + "%")
		var sid: int = st.id
		row("Уволить", [btn("Уволить", func(): sim.fire(sid); close_panel(), "red")])
		finish_panel()

func show_lot(i: int) -> void:
	var l = sim.S.lots[i]
	open_panel("lot", i)
	h3("🏞 Участок " + str(int(l.w)) + "×" + str(int(l.h)))
	small("Купите участок, чтобы расширить больницу.")
	row("Купить за $" + str(int(l.price)), [btn("Купить", func(): if sim.buyLot(i): game.snd("build"); close_panel(), "grn", sim.S.money < l.price)])
	finish_panel()

# ---------- build bars ----------
func show_build_bar_room() -> void:
	_clear_bar()
	ghost_info = Label.new()
	var pc = PanelContainer.new(); pc.add_theme_stylebox_override("panel", UIKit.chip_style(Color(15 / 255.0, 30 / 255.0, 45 / 255.0, 0.85)))
	pc.add_child(ghost_info)
	build_bar.add_child(pc)
	for n in 3:
		var nn: int = n
		build_bar.add_child(btn(["S", "M", "L"][n], func(): game.ghost_preset(nn)))
	build_bar.add_child(btn("↔−", func(): game.ghost_size(-1, 0)))
	build_bar.add_child(btn("↔+", func(): game.ghost_size(1, 0)))
	build_bar.add_child(btn("↕−", func(): game.ghost_size(0, -1)))
	build_bar.add_child(btn("↕+", func(): game.ghost_size(0, 1)))
	build_bar.add_child(btn("🚪", func(): game.ghost_door()))
	ghost_ok = btn("✔", func(): game.ghost_ok(), "grn")
	build_bar.add_child(ghost_ok)
	build_bar.add_child(btn("✖", func(): game.ghost_cancel(), "red"))
	build_bar.visible = true

func show_build_bar_item(k: String) -> void:
	_clear_bar()
	ghost_info = null
	var pc = PanelContainer.new(); pc.add_theme_stylebox_override("panel", UIKit.chip_style(Color(15 / 255.0, 25 / 255.0, 32 / 255.0, 0.85)))
	var l = Label.new(); l.text = "Наведите на пол: " + sim.D.items[k].name
	pc.add_child(l)
	build_bar.add_child(pc)
	item_rot_btn = btn(sim.v41RotLbl(), func(): game.item_rotate(); item_rot_btn.text = sim.v41RotLbl())
	build_bar.add_child(item_rot_btn)
	build_bar.add_child(btn("🪴 Другой", show_items))
	build_bar.add_child(btn("✔ Поставить", func(): game.item_confirm(), "grn"))
	build_bar.add_child(btn("✖ Готово", func(): game.item_done(), "red"))
	build_bar.visible = true

func _clear_bar() -> void:
	for c in build_bar.get_children():
		build_bar.remove_child(c); c.queue_free()

func hide_build_bar() -> void:
	build_bar.visible = false
	_clear_bar()
	ghost_info = null

# ---------- level select / win / lose ----------
func show_levels() -> void:
	var prog: Dictionary = game.progress()
	open_modal()
	modal_title("Выбор уровня")
	for i in sim.D.levels.size():
		var l: Dictionary = sim.D.levels[i]
		var ok: bool = game.unlocked(i)
		var dn: bool = i in prog.done
		var has: bool = game.has_save(i)
		var bs = []
		var ii: int = i
		if ok and has: bs.append(btn("📂", func(): if game.load_game(ii): close_modal(); game.set_speed(1), "grn"))
		bs.append(btn("Заново" if has else "Играть", func(): game.start_level(ii), "", not ok))
		row(("✅ " if dn else ("▶ " if ok else "🔒 ")) + str(int(l.id)) + ". " + l.name, bs, str(int(l.w)) + "×" + str(int(l.h)) + " · вылечить " + str(int(l.goals.cured)) + " · $" + str(int(l.goals.money)) + " · реп. " + str(int(l.goals.rep)), modal_vb, true)
	if game.in_game: modal_buttons([btn("Закрыть", func(): close_modal(); game.set_speed(1))])
	modal_done()

func show_win() -> void:
	var S: Dictionary = sim.S
	open_modal()
	modal_title("🏆 Уровень пройден!")
	modal_text("Вылечено: " + str(int(S.cured)) + ". Баланс $" + str(int(S.money)) + ". Репутация " + str(int(round(S.rep))) + ". Потери: " + str(int(S.deaths)) + ".")
	var bs = []
	if S.lv + 1 < sim.D.levels.size():
		var nx: int = S.lv + 1
		bs.append(btn("Следующий уровень ▶", func(): game.start_level(nx), "grn"))
	else:
		modal_text("Это последний уровень текущей версии!")
	bs.append(btn("Продолжить играть", func(): close_modal(); game.set_speed(1)))
	bs.append(btn("К выбору уровня", func(): show_levels()))
	modal_buttons(bs)
	modal_done()

func show_lose(why: String) -> void:
	open_modal()
	modal_title("😵 Вы уволены!")
	modal_text(why)
	var lv: int = sim.S.lv
	modal_buttons([btn("Начать заново", func(): game.start_level(lv)), btn("К выбору уровня", func(): show_levels())])
	modal_done()

func show_info(title: String, text: String) -> void:
	open_modal()
	modal_title(title)
	modal_text(text)
	modal_buttons([btn("OK", func(): close_modal())])
	modal_done()

func is_blocking(pos: Vector2) -> bool:
	if modal_bg.visible: return true
	for c in [panel, build_bar]:
		if c.visible and c.get_global_rect().has_point(pos):
			if c == build_bar:
				for b in build_bar.get_children():
					if b.get_global_rect().has_point(pos): return true
				return false
			return true
	return false
