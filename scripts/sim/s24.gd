# v24.js: room sizes S/M/L, cost by area, real capacity (throughput)
class_name Sim24
extends Sim18

const V24SZ := ["S", "M", "L"]

func v24MinA(type) -> int:
	var m = drm(type).min
	return (m[0] + 2) * (m[1] + 2)
func v24Rat(type, w, h) -> float: return float(w * h) / v24MinA(type)
func v24Cap(type, w, h) -> int:
	var k = v24Rat(type, w, h)
	return 3 if k >= 2 else (2 if k >= 1.4 else 1)
func v24Cost(type, w, h) -> int:
	var d = drm(type)
	var k = v24Rat(type, w, h)
	return int(round(d.cost * (1 + .75 * (k - 1)) / 50.0)) * 50
func rCap(r) -> float:
	if r == null: return 1.0
	return float(r.cap) if gnum(r, "cap", 0) else float(v24Cap(r.type, r.w, r.h))
func v24Spd(c) -> float: return 1 + .3 * (c - 1)

func v24Pre(g: Dictionary, n: int) -> void:
	var m = drm(g.type).min
	var a = [[0, 0], [1, 1], [2, 2]][n]
	g.w = mini(12, m[0] + 2 + a[0])
	g.h = mini(12, m[1] + 2 + a[1])
	var s = 0
	if n == 2:
		while v24Cap(g.type, g.w, g.h) < 3 and s < 6:
			s += 1
			if g.w <= g.h: g.w = mini(12, g.w + 1)
			else: g.h = mini(12, g.h + 1)
	if n == 1:
		while v24Cap(g.type, g.w, g.h) < 2 and s < 6:
			s += 1
			g.w = mini(12, g.w + 1)

func ghostLabel(g: Dictionary) -> String:
	var c = v24Cap(g.type, g.w, g.h)
	return str(g.w - 2) + "×" + str(g.h - 2) + " " + V24SZ[c - 1] + ((" ⚡×%.1f" % v24Spd(c)) if c > 1 else "")

func roomBuildCost(g: Dictionary) -> int: return v24Cost(g.type, g.w, g.h)

func after_build(r) -> void:
	super.after_build(r)
	r.cap = v24Cap(r.type, r.w, r.h)

func r_dur(p) -> float:
	var r = room_by_id(p.room)
	return super.r_dur(p) / v24Spd(rCap(r))
