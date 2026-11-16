extends SceneTree
func _init() -> void:
	for f in ["s00_core", "s01_motion", "s02_mech", "s11", "s12", "s17", "s18", "s24", "s25", "s41", "s42", "s45body", "sim"]:
		var s = load("res://scripts/sim/" + f + ".gd")
		print(f, " -> ", s != null and s.can_instantiate())
	quit()
