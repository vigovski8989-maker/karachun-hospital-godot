extends SceneTree
func _init():
	var s = load("res://assets/anim/UAL1_Standard.glb").instantiate()
	var a: AnimationPlayer = s.find_child("AnimationPlayer", true, false)
	var out = []
	for n in a.get_animation_list(): out.append("%s(%.2f)" % [n, a.get_animation(n).length])
	print(" ".join(out))
	var sk: Skeleton3D = s.find_child("Skeleton3D", true, false)
	var bones = []
	for i in sk.get_bone_count(): bones.append(sk.get_bone_name(i))
	print(" ".join(bones))
	var c = load("res://assets/chars/patient_a.glb").instantiate()
	var sk2: Skeleton3D = c.find_child("Skeleton3D", true, false)
	var pi = sk2.find_bone("pelvis")
	print("pelvis rest y ", sk2.get_bone_global_rest(pi).origin, " skel scale ", sk2.global_transform.basis.get_scale() if sk2.is_inside_tree() else sk2.transform.basis.get_scale(), " head ", sk2.get_bone_global_rest(sk2.find_bone("Head")).origin)
	quit()
