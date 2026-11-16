# Offline converter: data/furn46.json (exported from 45.x furn_i46.js by tools/furnexp/export.mjs) -> res://furn46/*.scn
# Each prefab: Node3D with one MeshInstance3D "Static" (surfaces merged per material, auto LODs) + named animated parts.
extends SceneTree

var mats := {}

func _init() -> void:
	var j = JSON.parse_string(FileAccess.get_file_as_string("res://data/furn46.json"))
	DirAccess.make_dir_recursive_absolute("res://furn46/mats")
	var n = 0
	for sec in ["F", "DECOR", "EXTRA"]:
		for k in j[sec]:
			var root = _build(k, j[sec][k])
			var ps = PackedScene.new()
			ps.pack(root)
			var pre = "" if sec == "F" else ("decor_" if sec == "DECOR" else "extra_")
			ResourceSaver.save(ps, "res://furn46/%s%s.scn" % [pre, k], ResourceSaver.FLAG_COMPRESS)
			root.free()
			n += 1
	print("built ", n, " prefabs, mats ", mats.size())
	quit()

func _f32(s) -> PackedFloat32Array:
	if s == null: return PackedFloat32Array()
	return Marshalls.base64_to_raw(s).to_float32_array()

func _mat(m: Dictionary) -> Material:
	var key = JSON.stringify(m, "", true)
	if mats.has(key): return mats[key]
	var sm = StandardMaterial3D.new()
	sm.albedo_color = Color(m.c)
	sm.roughness = m.get("r", 0.72)
	sm.metallic = m.get("m", 0.0)
	if m.has("e"):
		sm.emission_enabled = true
		sm.emission = Color(m.e)
		sm.emission_energy_multiplier = m.get("ei", 0.55)
	if m.has("op"):
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.albedo_color.a = m.op
	if m.has("map") and str(m.map).begins_with("assets/"):
		var p = "res://" + str(m.map)
		if ResourceLoader.exists(p):
			sm.albedo_texture = load(p)
			sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			var rep = m.get("rep", [1, 1])
			sm.uv1_scale = Vector3(rep[0], rep[1], 1)
	if m.has("at"):
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		sm.alpha_scissor_threshold = m.at
	if m.has("dbl"): sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	if m.has("basic"): sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var path = "res://furn46/mats/m%d.tres" % mats.size()
	ResourceSaver.save(sm, path)
	var lm = load(path)
	mats[key] = lm
	return lm

# three.js is CCW-front, Godot is CW-front -> reverse each triangle
func _arrays(p: PackedFloat32Array, n: PackedFloat32Array, uv: PackedFloat32Array) -> Array:
	var vc = p.size() / 3
	var V = PackedVector3Array(); V.resize(vc)
	var N = PackedVector3Array(); N.resize(vc)
	var U = PackedVector2Array()
	var has_uv = uv.size() == vc * 2
	if has_uv: U.resize(vc)
	for t in vc / 3:
		for c in 3:
			var src = t * 3 + c
			var dst = t * 3 + (2 - c)
			V[dst] = Vector3(p[src * 3], p[src * 3 + 1], p[src * 3 + 2])
			N[dst] = Vector3(n[src * 3], n[src * 3 + 1], n[src * 3 + 2])
			if has_uv: U[dst] = Vector2(uv[src * 2], 1.0 - uv[src * 2 + 1])
	var a = []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = V
	a[Mesh.ARRAY_NORMAL] = N
	if has_uv: a[Mesh.ARRAY_TEX_UV] = U
	return a

func _mesh(surfs: Array) -> ArrayMesh:
	var im = ImporterMesh.new()
	for s in surfs:
		var a = _arrays(_f32(s.p), _f32(s.n), _f32(s.uv))
		var st = SurfaceTool.new()
		st.create_from_arrays(a)
		st.index()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, _mat(s.mat))
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()

func _build(k: String, d: Dictionary) -> Node3D:
	var root = Node3D.new()
	root.name = k
	if d.surf.size():
		var mi = MeshInstance3D.new()
		mi.name = "Static"
		mi.mesh = _mesh(d.surf)
		root.add_child(mi)
		mi.owner = root
	var i = 0
	for p in d.parts:
		var mi = MeshInstance3D.new()
		mi.name = str(p.name) + ("" if i == 0 else "_" + str(i))
		mi.set_meta("part", str(p.name))
		mi.mesh = _mesh([{"p": p.p, "n": p.n, "uv": p.uv, "mat": p.mat}])
		var e = p.xf
		mi.transform = Transform3D(Basis(Vector3(e[0], e[1], e[2]), Vector3(e[4], e[5], e[6]), Vector3(e[8], e[9], e[10])), Vector3(e[12], e[13], e[14]))
		root.add_child(mi)
		mi.owner = root
		i += 1
	return root
