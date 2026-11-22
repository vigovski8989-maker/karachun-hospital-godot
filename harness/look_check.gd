extends SceneTree
func _init():
	var bad = 0
	for id in 2000:
		var e = {"id": id}
		var a = LookPool.roll(e, "", false)
		for d in ["balloonhead", "lostshadow", "cloudhead", "spotty"]:
			var b = LookPool.roll(e, d, false)
			for k in ["glb", "tex", "tint", "hair", "hcol", "bald", "beard", "age", "female", "scale", "shape", "blouse", "trous"]:
				if str(a[k]) != str(b[k]): bad += 1; if bad < 5: print("DIFF ", id, " ", d, " ", k, " ", a[k], " vs ", b[k])
	print("LOOK_STABLE mismatches ", bad, " of ", 2000 * 4)
	quit()
