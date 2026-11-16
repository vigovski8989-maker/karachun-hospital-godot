class_name Geo
## Procedural geometry helpers: rounded boxes, cylinders, materials.

static func _axis_coords(h: float, r: float, seg: int) -> PackedFloat32Array:
	var c = PackedFloat32Array()
	r = min(r, h * 0.999)
	for i in range(seg + 1):
		var th = PI * 0.5 * float(i) / seg
		c.append(-h + r - r * cos(th))
	for i in range(seg, -1, -1):
		var th = PI * 0.5 * float(i) / seg
		var v = h - r + r * cos(th)
		if v > c[c.size() - 1] + 0.00001:
			c.append(v)
	return c

## Rounded box centred at origin, size s, edge radius r.
static func rbox(s: Vector3, r: float = 0.03, seg: int = 3) -> ArrayMesh:
	var h = s * 0.5
	r = min(r, min(h.x, min(h.y, h.z)) * 0.98)
	var cx = _axis_coords(h.x, r, seg)
	var cy = _axis_coords(h.y, r, seg)
	var cz = _axis_coords(h.z, r, seg)
	var inner = h - Vector3(r, r, r)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 6 faces: (axis, sign)
	var faces = [[0, 1], [0, -1], [1, 1], [1, -1], [2, 1], [2, -1]]
	for f in faces:
		var ax: int = f[0]
		var sg: int = f[1]
		var ua: int = (ax + 1) % 3
		var va: int = (ax + 2) % 3
		var cu: PackedFloat32Array = [cx, cy, cz][ua]
		var cv: PackedFloat32Array = [cx, cy, cz][va]
		var verts = []
		for j in cv.size():
			var row = []
			for i in cu.size():
				var p = Vector3()
				p[ax] = h[ax] * sg
				p[ua] = cu[i]
				p[va] = cv[j]
				var q = p.clamp(-inner, inner)
				var n = p - q
				if n.length() < 1e-6:
					n = Vector3(); n[ax] = sg
				n = n.normalized()
				row.append([q + n * r, n])
			verts.append(row)
		for j in range(cv.size() - 1):
			for i in range(cu.size() - 1):
				var a = verts[j][i]; var b = verts[j][i + 1]; var c = verts[j + 1][i + 1]; var d = verts[j + 1][i]
				var tri = [a, c, b, a, d, c] if sg > 0 else [a, b, c, a, c, d]
				for t in tri:
					st.set_normal(t[1])
					var pp: Vector3 = t[0]
					st.set_uv(Vector2(pp[ua], pp[va]))
					st.add_vertex(pp)
	st.generate_tangents()
	return st.commit()

static func mat(col: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m

static func tex_mat(path: String, col: Color = Color.WHITE, rough: float = 0.7, uv_scale: Vector3 = Vector3.ONE, triplanar: bool = false) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.albedo_color = col
	m.roughness = rough
	m.uv1_scale = uv_scale
	m.uv1_triplanar = triplanar
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

static func mi(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot_y: float = 0.0, shadow: bool = true) -> MeshInstance3D:
	var n = MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = m
	n.position = pos
	n.rotation.y = rot_y
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(n)
	return n

static var _rb_cache := {}
static func box(parent: Node3D, size: Vector3, m: Material, pos: Vector3, r: float = 0.025, rot_y: float = 0.0) -> MeshInstance3D:
	var key = "%.3f,%.3f,%.3f,%.3f" % [size.x, size.y, size.z, r]
	if not _rb_cache.has(key): _rb_cache[key] = rbox(size, r)
	return mi(parent, _rb_cache[key], m, pos, rot_y)

static func cyl(parent: Node3D, rad_top: float, rad_bot: float, h: float, m: Material, pos: Vector3, seg: int = 20) -> MeshInstance3D:
	var c = CylinderMesh.new()
	c.top_radius = rad_top; c.bottom_radius = rad_bot; c.height = h; c.radial_segments = seg; c.rings = 1
	return mi(parent, c, m, pos)

static func sphere(parent: Node3D, rad: float, m: Material, pos: Vector3, sy: float = 1.0) -> MeshInstance3D:
	var s = SphereMesh.new()
	s.radius = rad; s.height = rad * 2.0 * sy; s.radial_segments = 20; s.rings = 10
	return mi(parent, s, m, pos)

## Flat textured quad (poster / sign), facing +Z of its local frame, uv rect into atlas.
static func quad(parent: Node3D, size: Vector2, m: Material, pos: Vector3, rot_y: float, uv_rect: Rect2 = Rect2(0, 0, 1, 1)) -> MeshInstance3D:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx = size.x * 0.5; var hy := size.y * 0.5
	var p = [Vector3(-hx, -hy, 0), Vector3(hx, -hy, 0), Vector3(hx, hy, 0), Vector3(-hx, hy, 0)]
	var u = [Vector2(uv_rect.position.x, uv_rect.end.y), Vector2(uv_rect.end.x, uv_rect.end.y), Vector2(uv_rect.end.x, uv_rect.position.y), uv_rect.position]
	for i in [0, 2, 1, 0, 3, 2]:
		st.set_normal(Vector3(0, 0, 1)); st.set_uv(u[i]); st.add_vertex(p[i])
	st.generate_tangents()
	var n = mi(parent, st.commit(), m, pos, rot_y, false)
	return n
