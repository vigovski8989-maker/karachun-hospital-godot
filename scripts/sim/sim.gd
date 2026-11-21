# Final simulation class (top of the patch chain)
class_name Sim
extends SimBody

func _init() -> void:
	super._init()

# fixed-step driver identical to 45.x loop: substeps of <= 0.05 s, total dt*speed
func step(real_dt: float) -> void:
	if S.is_empty() or speed <= 0: return
	var tot = minf(real_dt, 0.1) * speed
	while tot > 1e-6:
		var d = minf(0.05, tot)
		update(d)
		tot -= d
		if S.won or S.lost: break

# ---------- 0.9.7 reception waiting (approved by the user) ----------
# Reception waiters take ANY free bench seat in the hospital (nearest to the reception door first, no 7-tile limit).
# When every seat is taken they stand in a single-file line leading away from the reception door, facing it;
# the line closes up as people are served, and a stander moves to a bench seat as soon as one frees up.
# Arrival rate, service time, patience and money are untouched (only where the waiters stand/sit changes).
func _free_bench_spot(r, p):
	var o = doorOut(r)
	var bs = []
	for i in S.items:
		if i.type == "bench": bs.append(i)
	bs.sort_custom(func(a, b): return absf(a.x - o.x) + absf(a.y - o.y) < absf(b.x - o.x) + absf(b.y - o.y))
	for b in bs:
		if b.get("occ") == null: b.occ = [0, 0]
		for k in b.occ.size():
			if not b.occ[k] or pat_by_id(b.occ[k]) == null:
				b.occ[k] = p.id
				var s = {"x": b.x + k, "y": b.y, "pose": "sit", "dir": 1, "seat": "bench", "bench": true, "slot": k}
				if b.get("dir") != null:
					if b.dir == 0 or b.dir == 2:
						s.x = b.x; s.y = b.y + k
					s.dir = b.dir
				return s
	return null

var _lines := {}   # runtime cache only (never saved)
# the line stays INSIDE the hospital (never the entrance/sidewalk row, never a room, a bench or a tile in front of
# a bench or another room's door); it starts at the reception door and snakes through the hall, preferring to keep
# going straight but never walking into a dead end (flood-fill look-ahead). Overflow waits outside the entrance.
func _rec_ok(t: Vector2i, res: Dictionary) -> bool:
	return t.y < S.h - 1 and walk(t.x, t.y) and roomAt(t.x, t.y) == null and res.get(t, 0) != 1
func _rec_reserved(r) -> Dictionary:
	var res = {}
	for r2 in S.rooms:
		if r2 == r: continue
		var o2 = doorOut(r2); res[Vector2i(o2.x, o2.y)] = 1
	for i in S.items:
		if i.type != "bench": continue
		var bd = int(i.get("dir")) if i.get("dir") != null else 1
		var dv = DIRS[bd]
		for k in 2:
			var bx = i.x + (0 if bd == 0 or bd == 2 else k); var by = i.y + (k if bd == 0 or bd == 2 else 0)
			var bt = Vector2i(bx + dv[0], by + dv[1])
			if not res.has(bt): res[bt] = 2   # in front of a bench: allowed, but avoided
	# keep the entrance lane clear
	for yy in range(S.h - 3, S.h): res[Vector2i(S.ent.x, yy)] = 1
	return res
func _rec_flood(start: Vector2i, used: Dictionary, res: Dictionary, cap: int) -> int:
	var seen = {start: true}; var q = [start]; var n = 0
	while q.size() and n < cap:
		var c = q.pop_front(); n += 1
		for d in DIRS:
			var nx = c + Vector2i(d[0], d[1])
			if seen.has(nx) or used.has(nx) or not _rec_ok(nx, res): continue
			seen[nx] = true; q.append(nx)
	return n
func _rec_line(r) -> Array:
	var key = str(r.door.x, ",", r.door.y, ":", S.items.size(), ":", S.rooms.size(), ":", S.w, "x", S.h)
	if _lines.has(r.id) and _lines[r.id][0] == key: return _lines[r.id][1]
	var res = _rec_reserved(r)
	var d = DIRS[int(r.side)]
	var o = doorOut(r)
	var line = []
	var used = {}
	var cur = Vector2i(o.x, o.y)
	var dir = Vector2i(d[0], d[1])
	used[cur] = true
	var prv = cur
	if o.y >= S.h - 1:
		# the desk opens onto the street: one waits at the counter, the rest line up inside from the entrance
		line.append({"x": o.x, "y": o.y, "pose": "stand", "dir": (int(r.side) + 2) % 4})
		# first inside tile: next to (not in) the entrance lane, on the side of the desk
		var e0 = Vector2i(S.ent.x, S.h - 2)
		var st0 = null; var sd = 1e9
		for yy in range(S.h - 5, S.h - 1):
			for xx in range(S.ent.x - 3, S.ent.x + 4):
				var t0 = Vector2i(xx, yy)
				if not _rec_ok(t0, res) or res.get(t0, 0) == 2: continue
				var dd = absi(xx - e0.x) * 10 + absi(yy - e0.y) * 10 + (0 if signi(xx - e0.x) == signi(o.x - e0.x) else 5)
				if dd < sd: sd = dd; st0 = t0
		if st0 == null: cur = Vector2i(-99, -99)
		else:
			line.append({"x": st0.x, "y": st0.y, "pose": "stand", "dir": 1})
			cur = st0; dir = Vector2i(0, -1); used[cur] = true; prv = cur
	for n in 24:
		if cur.x < 0: break
		var best = null; var bsc = -1
		for c in [dir, Vector2i(-dir.y, dir.x), Vector2i(dir.y, -dir.x)]:
			var nx = cur + c
			if used.has(nx) or not _rec_ok(nx, res): continue
			# single file: never side by side with an earlier part of the line (a snake keeps an empty row between legs)
			# (legs of the snake keep two empty rows between them, so the line never reads as a crowd)
			var touch = false
			for u in used:
				if u == cur or u == prv: continue
				if absi(u.x - nx.x) + absi(u.y - nx.y) <= 2: touch = true; break
			if touch: continue
			used[nx] = true
			var room = _rec_flood(nx, used, res, 30)
			used.erase(nx)
			var sc = mini(room, 24 - n) * 4 + (2 if c == dir else 0) - (5 if res.get(nx, 0) == 2 else 0)
			if sc > bsc: bsc = sc; best = c
		if best == null: break
		var nx2 = cur + best
		used[nx2] = true
		var f = cur - nx2
		var fd = 1 if f.y > 0 else (3 if f.y < 0 else (0 if f.x > 0 else 2))
		line.append({"x": nx2.x, "y": nx2.y, "pose": "stand", "dir": fd})
		prv = cur; cur = nx2; dir = best
	# overflow: a loose group on the street either side of the entrance lane (two per tile, spread out by the view)
	var ov = []
	for k in [2, -2, 3, -3, 4, -4, 5, -5, 6, -6]:
		var x = S.ent.x + k
		if x < 0 or x >= S.w or not walk(x, S.h - 1): continue
		var near_counter = false
		for t in line:
			if t.y == S.h - 1 and absi(t.x - x) <= 1: near_counter = true
		if near_counter: continue
		for sl in 2: ov.append({"x": x, "y": S.h - 1, "pose": "stand", "dir": 3, "loose": true})
	_lines[r.id] = [key, line, ov]
	return line
func _rec_spot(r, idx: int) -> Dictionary:
	var line = _rec_line(r)
	if idx < line.size(): return line[idx]
	var ov = _lines[r.id][2]
	if ov.is_empty(): return line[line.size() - 1] if line.size() else {}
	return ov[mini(idx - line.size(), ov.size() - 1)]

func waitSpot(r, p) -> Dictionary:
	if r.type != "reception": return super.waitSpot(r, p)
	var s = _free_bench_spot(r, p)
	if s != null:
		p.wsp = null
		return s
	var idx = 0
	for id in r.queue:
		if id == p.id: break
		var q = pat_by_id(id)
		if q and q.get("wsp") != null and q.state == "queue": idx += 1
	var t = _rec_spot(r, idx)
	if t.is_empty(): return super.waitSpot(r, p)
	p.wsp = {"x": t.x, "y": t.y}
	return t

func _pat_queue(p, dt: float) -> void:
	super._pat_queue(p, dt)
	if p.state != "queue" or p.vs: return
	var r = room_by_id(p.room)
	if r == null or r.type != "reception" or p.get("wsp") == null: return
	if r.queue.size() and r.queue[0] == p.id and r.busy == null and staffReady(r): return
	p.rq_t = gnum(p, "rq_t", 0.0) + dt
	if p.rq_t < 0.5: return
	p.rq_t = 0.0
	# a seat freed up -> go and sit
	var s = _free_bench_spot(r, p)
	if s != null:
		p.wsp = null; p.wantSeat = s
		goTo(p, s.x, s.y)
		return
	# close up the line
	var idx = 0
	for id in r.queue:
		if id == p.id: break
		var q = pat_by_id(id)
		if q and q.get("wsp") != null and q.state == "queue": idx += 1
	var t = _rec_spot(r, idx)
	if t.is_empty(): return
	if int(p.wsp.x) != int(t.x) or int(p.wsp.y) != int(t.y):
		p.wsp = {"x": t.x, "y": t.y}
		goTo(p, t.x, t.y)
	elif p.path.is_empty():
		p.dir = t.dir
