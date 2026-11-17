# Isometric orthographic camera: drag pans, pinch / wheel zooms, short press = tap. Emits world-independent screen events.
class_name IsoCam
extends Camera3D

signal tapped(pos: Vector2)
signal dragged(pos: Vector2)
signal drag_started(pos: Vector2)

var focus = Vector3(10, 0, 10)
var zoom = 13.0
var dir = Vector3(1.0, 0.92, 1.0).normalized()
var map_size = Vector2(40, 28)
var touches = {}
var pinch_d = 0.0
var min_zoom = 5.0
var max_zoom = 34.0
var press_pos = Vector2.ZERO
var moved = false
var pressing = false
var ghost_drag = false
var hud
var drag_start_cb: Callable
var shake_t = 0.0

func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	# portrait phones: the ortho size is the visible WIDTH (in metres), the tall screen shows more depth
	keep_aspect = Camera3D.KEEP_WIDTH
	near = 0.1
	far = 200.0
	apply()

func get_focus() -> Vector3: return focus

func apply() -> void:
	focus.x = clampf(focus.x, -2.0, map_size.x + 2.0)
	focus.z = clampf(focus.z, -2.0, map_size.y + 2.0)
	size = zoom
	var sh = Vector3.ZERO
	if shake_t > 0:
		var t = Time.get_ticks_msec() / 1000.0
		sh = Vector3(sin(t * 33.0), 0, cos(t * 43.0)) * 0.12 * shake_t
	global_position = focus + sh + dir * 60.0
	look_at(focus + sh, Vector3.UP)

func shake(t: float) -> void: shake_t = maxf(shake_t, t)

func _process(delta: float) -> void:
	if shake_t > 0:
		shake_t = maxf(0, shake_t - delta)
		apply()

func _pan(rel: Vector2) -> void:
	var vp = get_viewport().get_visible_rect().size
	var wpp = size / vp.x
	var right = global_transform.basis.x
	var fwd = Vector3(-dir.x, 0, -dir.z).normalized()
	var pitch_k = 1.0 / dir.y * dir.length() if false else 1.0 / sin(asin(dir.y))
	focus -= right * rel.x * wpp + fwd * (-rel.y) * wpp * pitch_k
	apply()

func _blocked(pos: Vector2) -> bool:
	return hud != null and hud.is_blocking(pos)

func _press(pos: Vector2) -> void:
	pressing = true
	moved = false
	press_pos = pos
	ghost_drag = drag_start_cb.is_valid() and drag_start_cb.call(pos)

func _move(pos: Vector2, rel: Vector2) -> void:
	if not pressing: return
	if not moved and pos.distance_to(press_pos) > 10.0: moved = true
	if not moved: return
	if ghost_drag: dragged.emit(pos)
	else: _pan(rel)

func _release(pos: Vector2) -> void:
	if pressing and not moved: tapped.emit(pos)
	pressing = false
	ghost_drag = false

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			if _blocked(e.position): return
			touches[e.index] = e.position
			if touches.size() == 1: _press(e.position)
			else:
				pressing = false
				var k = touches.keys()
				pinch_d = touches[k[0]].distance_to(touches[k[1]])
		else:
			if touches.has(e.index):
				touches.erase(e.index)
				if touches.is_empty(): _release(e.position)
	elif e is InputEventScreenDrag:
		if not touches.has(e.index): return
		touches[e.index] = e.position
		if touches.size() == 1:
			_move(e.position, e.relative)
		elif touches.size() >= 2:
			var k = touches.keys()
			var d: float = touches[k[0]].distance_to(touches[k[1]])
			if pinch_d > 1.0 and d > 1.0:
				zoom = clampf(zoom * pinch_d / d, min_zoom, max_zoom)
			pinch_d = d
			apply()
	elif e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				if _blocked(e.position): return
				_press(e.position)
			else: _release(e.position)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 0.9, min_zoom, max_zoom); apply()
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom * 1.1, min_zoom, max_zoom); apply()
	elif e is InputEventMouseMotion:
		if e.button_mask & MOUSE_BUTTON_MASK_LEFT: _move(e.position, e.relative)
		elif e.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE): _pan(e.relative)
	elif e is InputEventMagnifyGesture:
		zoom = clampf(zoom / e.factor, min_zoom, max_zoom); apply()
	elif e is InputEventPanGesture:
		_pan(-e.delta * 8.0)
