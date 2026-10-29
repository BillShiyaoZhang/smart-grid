class_name GridIslandFactory
extends RefCounted

const Models = preload("res://scripts/art/model_factory.gd")

## The flat top is y = -0.04. A cell is ((x-7.5)*2, 0, (y-7.5)*2).
static func create(size: int = 16, spacing: float = 2.0) -> Node3D:
	var root = Node3D.new()
	root.name = "BayIsland"
	var half = size * spacing * 0.5
	Models.box(root, Vector3(180, 0.2, 180), Vector3(0, -1.5, 0), Color("72b8ba"), "Sea")
	_prism(root, _octagon(half + 1.7, 2.0), -0.75, -1.42, Color("a7bbae"), Color("8aa99d"), "Bedrock")
	_prism(root, _octagon(half + 1.4, 1.8), -0.32, -0.88, Color("dcd9b7"), Color("c5c5a7"), "Beach")
	_prism(root, _octagon(half + 1.05, 1.5), -0.04, -0.36, Color("a9c9a1"), Color("86ad86"), "Meadow")
	# Subtle patchwork makes the terrain read as a hand built model.
	for x in range(size):
		for z in range(size):
			if (x * 13 + z * 7) % 5 == 0:
				Models.box(root, Vector3(spacing - 0.06, 0.012, spacing - 0.06), Vector3((x - (size - 1) * 0.5) * spacing, -0.035, (z - (size - 1) * 0.5) * spacing), Color("accda3"))
	var road_x = (6 - (size - 1) * 0.5) * spacing
	var road_z = (7 - (size - 1) * 0.5) * spacing
	_road(root, Vector3(road_x, 0.003, 0), Vector3(1.06, 0.04, half * 2 + 0.2), false)
	_road(root, Vector3(0, 0.006, road_z), Vector3(half * 2 + 0.2, 0.04, 1.06), true)
	# Two smaller streets frame the town rather than covering the building plots.
	_road(root, Vector3(7.0, 0.001, 3.0), Vector3(0.72, 0.035, 16.0), false, false)
	_road(root, Vector3(1.0, 0.002, 9.0), Vector3(12.0, 0.035, 0.72), true, false)
	for i in range(-7, 8):
		if i == -1: continue
		Models.box(root, Vector3(0.045, 0.012, 0.5), Vector3(road_x, 0.032, i * 2.0), Color("e4e5c8"))
		if i != -2:
			Models.box(root, Vector3(0.5, 0.012, 0.045), Vector3(i * 2.0, 0.034, road_z), Color("e4e5c8"))
	for i in range(6):
		Models.box(root, Vector3(0.13, 0.015, 0.83), Vector3(road_x + 0.55 + i * 0.22, 0.04, road_z), Color("f4efd8"))
	# Trees stay in the perimeter strip outside all sixteen playable rows.
	for i in range(18):
		var t = float(i) / 17.0
		var along = lerpf(-half + 1.5, half - 1.5, t)
		for edge in range(4):
			if (i + edge * 3) % 5 == 0: continue
			var tree = Models.tree(i + edge * 19)
			root.add_child(tree)
			var off = half + 0.30 + sin(i * 1.9 + edge) * 0.15
			match edge:
				0: tree.position = Vector3(along, -0.04, -off)
				1: tree.position = Vector3(along, -0.04, off)
				2: tree.position = Vector3(-off, -0.04, along)
				3: tree.position = Vector3(off, -0.04, along)
			tree.scale *= 0.75 + (i % 4) * 0.06
	for i in range(16):
		var rock = Models.rock(i)
		root.add_child(rock)
		var theta = i * TAU / 16.0
		var dir = Vector2(cos(theta), sin(theta))
		dir /= maxf(absf(dir.x), absf(dir.y))
		rock.position = Vector3(dir.x * (half + 1.25), -0.28, dir.y * (half + 1.25))
	# A little service pier on the southeastern shore.
	Models.box(root, Vector3(1.4, 0.15, 4.5), Vector3(10.5, -0.22, half + 2.2), Color("b6a78b"), "ServicePier")
	for i in range(15):
		Models.box(root, Vector3(1.45, 0.025, 0.035), Vector3(10.5, -0.13, half + 0.1 + i * 0.29), Color("d6c8a8"))
	for z in [half + 0.25, half + 2.3, half + 4.1]:
		for x in [9.87, 11.13]:
			Models.cylinder(root, 0.07, 0.8, Vector3(x, -0.5, z), Color("8a8e77"), 7)
	# Decorative wave ribbons use real geometry so they remain crisp when zoomed.
	for i in range(28):
		var side = -1.0 if i % 2 == 0 else 1.0
		var x = sin(i * 13.7) * (half + 14)
		var z = side * (half + 3.8 + (i % 7) * 2.1)
		var stripe = Models.box(root, Vector3(0.7 + (i % 4) * 0.5, 0.008, 0.045), Vector3(x, -1.389, z), Color("8cc8c6"))
		stripe.rotation.y = -0.23
		if i % 3 == 0:
			Models.box(root, Vector3(0.45, 0.008, 0.04), Vector3(x + 0.2, -1.388, z + 0.18), Color("8cc8c6"))
	var van = Models.vehicle()
	root.add_child(van)
	van.position = Vector3(road_x + 0.25, 0.04, 3.6)
	return root

static func _road(root: Node3D, at: Vector3, size: Vector3, horizontal: bool, curb: bool = true) -> void:
	Models.box(root, size, at, Color("91a8a0"), "Street")
	if curb:
		if horizontal:
			for side in [-1, 1]:
				Models.box(root, Vector3(size.x, 0.045, 0.10), at + Vector3(0, 0, side * (size.z * 0.5 + 0.06)), Color("d3d6bb"))
		else:
			for side in [-1, 1]:
				Models.box(root, Vector3(0.10, 0.045, size.z), at + Vector3(side * (size.x * 0.5 + 0.06), 0, 0), Color("d3d6bb"))

static func _octagon(half: float, bevel: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-half + bevel, -half), Vector2(half - bevel, -half),
		Vector2(half, -half + bevel), Vector2(half, half - bevel),
		Vector2(half - bevel, half), Vector2(-half + bevel, half),
		Vector2(-half, half - bevel), Vector2(-half, -half + bevel)
	])

static func _prism(root: Node3D, outline: PackedVector2Array, top: float, bottom: float, top_color: Color, side_color: Color, title: String) -> void:
	var mesh = ArrayMesh.new()
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()
	for i in range(outline.size()):
		var j = (i + 1) % outline.size()
		var a = Vector3(outline[i].x, top, outline[i].y)
		var b = Vector3(outline[j].x, top, outline[j].y)
		# Godot front faces use clockwise winding; keep the top visible from above.
		for v in [Vector3(0, top, 0), a, b]:
			vertices.append(v)
			normals.append(Vector3.UP)
			colors.append(top_color)
		var ab = Vector3(a.x, bottom, a.z)
		var bb = Vector3(b.x, bottom, b.z)
		var normal = Vector3(b.z - a.z, 0, a.x - b.x).normalized()
		for v in [a, bb, b, a, ab, bb]:
			vertices.append(v)
			normals.append(normal)
			colors.append(side_color)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	var instance = MeshInstance3D.new()
	instance.name = title
	instance.mesh = mesh
	instance.material_override = mat
	root.add_child(instance)
