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
