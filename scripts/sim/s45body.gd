# Body layer (replaces the render-coupled gait gates of r3d.js 45.x with a headless model, so the harness covers it):
# - bodies have yaw + speed; they accelerate/decelerate, slow down in corners and turn in place for sharp turns (no sliding)
# - arrival gate: sitting/lying starts only after the body has turned to the seat direction
# - courtesy wait: a walker yields to a body standing right in front of it (limited time, avoids deadlocks)
# - waiting spots never stack two standing patients on one tile
# - cured patients celebrate for REACT_T seconds before walking out (45.x REACT46)
class_name SimBody
extends Sim42

const TURN_W := 5.5          # rad/s turning speed
const ACC := 2.4
const DEC := 3.0
const PAT_VMAX := 1.45
const STAFF_VMAX := 1.7
const REACT_T := 2.75
const PERSONAL := 0.62       # metres

var occ_grid = {}           # tile -> [entities] rebuilt each step

static func dirYaw(d) -> float:
	match int(d if d != null else 1):
		0: return PI / 2
		1: return 0.0
		2: return -PI / 2
		_: return PI
static func angd(a: float, b: float) -> float:
	return wrapf(a - b, -PI, PI)

func body_init(e) -> void:
	if e.get("yaw") == null: e.yaw = dirYaw(e.get("dir"))
	if e.get("v") == null: e.v = 0.0

func is_pat(e) -> bool: return e.has("dis")

func move(e, dt: float, sp := 2.2) -> bool:
	if e.path.is_empty():
		e.v = 0.0
		return true
	body_init(e)
	var vmax: float = minf(sp, PAT_VMAX if is_pat(e) else STAFF_VMAX)
	if sp > 2.5: vmax = minf(sp, 2.2)  # orderly fetch hurry
	var n = e.path[0]
	var dx: float = n.x - e.x
	var dy: float = n.y - e.y
	var d = hyp(dx, dy)
	if d < 1e-5:
		e.x = float(n.x); e.y = float(n.y)
		e.path.pop_front()
		return _arrived(e)
	var goal = atan2(dx, dy)
	var err = angd(goal, e.yaw)
	e.dir = (0 if dx > 0 else 2) if absf(dx) >= absf(dy) else (1 if dy > 0 else 3)
	# remaining distance along the path (for braking)
	var rem = d
	var last = n
	for i in range(1, mini(e.path.size(), 6)):
		var q = e.path[i]
		rem += hyp(q.x - last.x, q.y - last.y)
		last = q
	if e.path.size() > 6: rem += 10.0
	var turn = clampf(err, -TURN_W * dt, TURN_W * dt)
	e.yaw = wrapf(e.yaw + turn, -PI, PI)
	var aerr = absf(angd(goal, e.yaw))
	var target = minf(vmax, sqrt(2.0 * DEC * maxf(0.0, rem)))
	e.turning = false
	if aerr > 1.75 or (e.v < 0.2 and aerr > 0.6):
		target = 0.0  # turn in place first
		e.turning = absf(turn) > 1e-4
	else:
		target *= clampf(cos(aerr) * 1.15, 0.25, 1.0)
		target = maxf(0.12, target)
	# courtesy wait: someone standing right ahead
	if target > 0 and _blocked_ahead(e, goal):
		e.yw = gnum(e, "yw", 0.0) + dt
		if e.yw < 1.6: target = 0.0
	else:
		e.yw = 0.0
	if e.v < target: e.v = minf(target, e.v + ACC * dt)
	else: e.v = maxf(target, e.v - DEC * 1.6 * dt)
	var st: float = e.v * dt
	if st <= 0.0: return false
	if d <= st:
		e.x = float(n.x); e.y = float(n.y)
		e.path.pop_front()
		if e.path.is_empty(): e.v = 0.0
		return _arrived(e)
	e.x += dx / d * st
	e.y += dy / d * st
	return false

func _arrived(e) -> bool:
	return e.path.is_empty()

func _blocked_ahead(e, yaw: float) -> bool:
	var fx = sin(yaw)
	var fy = cos(yaw)
	for o in S.pats:
		if _blocks(e, o, fx, fy): return true
	for o in S.staff:
		if _blocks(e, o, fx, fy): return true
	return false

func _blocks(e, o, fx: float, fy: float) -> bool:
	if is_same(o, e) or o.get("vs") or o.state == "dead": return false
	var ox: float = o.x - e.x
	var oy: float = o.y - e.y
	var ahead = ox * fx + oy * fy
	if ahead <= 0.05 or ahead > PERSONAL: return false
	var side = absf(ox * fy - oy * fx)
	if side > 0.38: return false
	# only yield to bodies that stand still or walk towards us; never inside rooms on a final approach
	if gnum(o, "v", 0.0) > 0.3:
		var oyaw: float = o.get("yaw", 0.0)
		if sin(oyaw) * fx + cos(oyaw) * fy > 0.3: return false
	# the other one yields to us if it has lower id (break symmetry)
	if not o.path.is_empty() and o.id < e.id: return false
	return true

# arrival gate for seats: the down phase starts after the body faces the seat direction
func tickVs(e, dt: float) -> void:
	var v = e.get("vs")
	if v and v.ph == "down" and v.t == 0.0:
		body_init(e)
		var want = dirYaw(e.dir)
		var err = angd(want, e.yaw)
		if absf(err) > 0.06:
			e.yaw = wrapf(e.yaw + clampf(err, -TURN_W * dt, TURN_W * dt), -PI, PI)
			e.turning = true
			return
		e.turning = false
	super.tickVs(e, dt)

func body_tick(e, dt: float) -> void:
	# idle bodies turn to their dir (in place) when standing still
	body_init(e)
	if e.path.is_empty() and not e.get("vs"):
		e.v = 0.0
		var want = dirYaw(e.get("dir"))
		var err = angd(want, e.yaw)
		e.turning = absf(err) > 0.05
		if e.turning: e.yaw = wrapf(e.yaw + clampf(err, -TURN_W * dt, TURN_W * dt), -PI, PI)

func update(dt: float) -> void:
	super.update(dt)
	for e in S.pats: body_tick(e, dt)
	for e in S.staff: body_tick(e, dt)

# cured celebration hold before leaving
func updPatient(p, dt: float) -> void:
	if p.state == "leave" and p.get("healed") and not p.get("angry") and not p.get("vs") and not p.get("reactDone"):
		if p.get("react") == null: p.react = {"t": 0.0, "path": p.path}
		if p.react.t < REACT_T:
			p.react.t += dt
			p.path = []
			return
		p.path = p.react.path
		p.reactDone = true
	super.updPatient(p, dt)

# no two standing patients on one waiting tile
func waitSpot(r, p) -> Dictionary:
	var s = super.waitSpot(r, p)
	if s.get("pose") == "stand":
		var taken = {}
		for q in S.pats:
			if is_same(q, p): continue
			var t = q.get("wsp")
			if t and q.state == "queue": taken[str(t.x, ",", t.y)] = true
			if q.path.is_empty() and q.state == "queue": taken[str(int(round(q.x)), ",", int(round(q.y)))] = true
		if taken.has(str(s.x, ",", s.y)):
			var o = doorOut(r)
			var best = null
			var bd = 1e9
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var x: int = o.x + dx
					var y: int = o.y + dy
					if taken.has(str(x, ",", y)) or not walk(x, y) or roomAt(x, y): continue
					if x == o.x and y == o.y: continue
					var d = absi(dx) + absi(dy) + rand() * 0.5
					if d < bd:
						bd = d; best = {"x": x, "y": y, "pose": "stand", "dir": (1 if o.y > y else (3 if o.y < y else (0 if o.x > x else 2)))}
			if best: s = best
		p.wsp = {"x": s.x, "y": s.y}
	else:
		p.wsp = null
	return s
