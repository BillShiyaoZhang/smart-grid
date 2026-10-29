class_name GridModelFactory
extends RefCounted

## Original miniature construction set. One model fits a 2 m map cell.
const CREAM = Color("f5edda")
const WHITE = Color("fcfbf1")
const MINT = Color("8fc5aa")
const TEAL = Color("327c7c")
const BLUE = Color("295674")
const DARK = Color("23434f")
const ORANGE = Color("e7a36d")
const CORAL = Color("ce7465")
const METAL = Color("8caaa8")
const CONCRETE = Color("c6cfbd")

static func material(color: Color, metallic: float = 0.0, roughness: float = 0.82) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m

static func box(parent: Node3D, size: Vector3, at: Vector3, color: Color, title: String = "") -> MeshInstance3D:
	var mesh = BoxMesh.new()
	mesh.size = size
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material(color)
	instance.position = at
	if not title.is_empty(): instance.name = title
	parent.add_child(instance)
	return instance

static func cylinder(parent: Node3D, radius: float, height: float, at: Vector3, color: Color, sides: int = 12, top_radius: float = -1.0) -> MeshInstance3D:
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = sides
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material(color)
	instance.position = at
	parent.add_child(instance)
	return instance

static func beam(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var part = cylinder(parent, radius, a.distance_to(b), (a + b) * 0.5, color, 6)
	if a.distance_to(b) > 0.001:
		part.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	return part

static func building(kind: String) -> Node3D:
	var root = Node3D.new()
	root.name = kind.capitalize()
	box(root, Vector3(1.78, 0.10, 1.78), Vector3(0, 0.05, 0), CONCRETE, "Foundation")
	# Small aprons and curbs make every asset legible at a distance.
	box(root, Vector3(1.82, 0.035, 0.08), Vector3(0, 0.115, 0.86), CREAM)
	match kind:
		"home": _home(root)
		"gas": _gas(root)
		"solar": _solar(root)
		"wind": _wind(root)
		"battery": _battery(root)
		"substation": _substation(root)
		"intertie": _intertie(root)
		"control": _control(root)
		"relay": _relay(root)
		"soc": _soc(root)
		"factory": _factory(root)
		"hospital": _hospital(root)
		"sensor": _sensor(root)
		_: _home(root)
	return root

static func _home(root: Node3D) -> void:
	box(root, Vector3(1.1, 0.8, 1.05), Vector3(-0.1, 0.5, -0.08), CREAM)
	box(root, Vector3(1.16, 0.10, 1.11), Vector3(-0.1, 0.95, -0.08), WHITE)
	# Two sloping roof planes meet in a sculpted ridge.
	var roof_a = box(root, Vector3(0.68, 0.10, 1.22), Vector3(-0.4, 1.12, -0.08), TEAL)
	roof_a.rotation.z = deg_to_rad(30)
	var roof_b = box(root, Vector3(0.68, 0.10, 1.22), Vector3(0.2, 1.12, -0.08), TEAL)
	roof_b.rotation.z = deg_to_rad(-30)
	box(root, Vector3(0.15, 0.42, 0.16), Vector3(0.24, 1.2, -0.33), CORAL)
	box(root, Vector3(0.22, 0.4, 0.025), Vector3(-0.08, 0.31, 0.46), BLUE)
	box(root, Vector3(0.26, 0.25, 0.025), Vector3(-0.45, 0.63, 0.46), BLUE)
	box(root, Vector3(0.26, 0.25, 0.025), Vector3(0.25, 0.63, 0.46), BLUE)
	box(root, Vector3(0.025, 0.24, 0.28), Vector3(0.46, 0.65, -0.15), BLUE)
	box(root, Vector3(0.7, 0.08, 0.22), Vector3(-0.1, 0.15, 0.58), WHITE)
	box(root, Vector3(0.5, 0.055, 0.18), Vector3(-0.1, 0.12, 0.75), CREAM)
	cylinder(root, 0.14, 0.18, Vector3(0.65, 0.2, 0.55), CORAL, 7)
	cylinder(root, 0.20, 0.25, Vector3(0.65, 0.4, 0.55), MINT, 7, 0.12)

static func _gas(root: Node3D) -> void:
	box(root, Vector3(1.08, 0.74, 1.10), Vector3(-0.18, 0.48, -0.05), CREAM)
	box(root, Vector3(1.17, 0.12, 1.2), Vector3(-0.18, 0.9, -0.05), TEAL)
	box(root, Vector3(0.67, 0.3, 0.4), Vector3(-0.25, 1.1, -0.12), MINT)
	for x in [-0.54, -0.18, 0.18]:
		box(root, Vector3(0.23, 0.23, 0.025), Vector3(x, 0.55, 0.51), BLUE)
	box(root, Vector3(0.025, 0.41, 0.52), Vector3(0.37, 0.4, -0.05), DARK)
	for z in [-0.4, 0.35]:
		cylinder(root, 0.18, 1.55, Vector3(0.61, 0.89, z), METAL, 10, 0.13)
		cylinder(root, 0.16, 0.22, Vector3(0.61, 1.4, z), ORANGE, 10)
		cylinder(root, 0.18, 0.07, Vector3(0.61, 1.7, z), DARK, 10)
	beam(root, Vector3(0.6, 0.35, -0.4), Vector3(0.6, 0.35, 0.35), 0.08, TEAL)
	box(root, Vector3(0.25, 0.30, 0.025), Vector3(-0.55, 0.29, 0.51), ORANGE)

static func _solar(root: Node3D) -> void:
	box(root, Vector3(0.3, 0.4, 0.32), Vector3(0.57, 0.3, 0.56), WHITE)
	box(root, Vector3(0.22, 0.13, 0.025), Vector3(0.57, 0.37, 0.73), TEAL)
	for row in range(2):
		for col in range(2):
			var support = Node3D.new()
			root.add_child(support)
			support.position = Vector3(-0.42 + col * 0.78, 0.43, -0.43 + row * 0.72)
			support.rotation.x = -0.28
			box(support, Vector3(0.70, 0.065, 0.59), Vector3.ZERO, WHITE)
			box(support, Vector3(0.65, 0.015, 0.54), Vector3(0, 0.042, 0), BLUE)
			for segment in range(1, 4):
				box(support, Vector3(0.009, 0.006, 0.53), Vector3(-0.325 + segment * 0.1625, 0.052, 0), Color("7caec0"))
			box(support, Vector3(0.65, 0.006, 0.009), Vector3(0, 0.052, 0), Color("7caec0"))
			cylinder(root, 0.035, 0.36, Vector3(support.position.x, 0.25, support.position.z), METAL, 6)

static func _wind(root: Node3D) -> void:
	cylinder(root, 0.38, 0.16, Vector3(0, 0.18, 0), WHITE, 12)
	cylinder(root, 0.14, 2.2, Vector3(0, 1.3, 0), WHITE, 10, 0.075)
	cylinder(root, 0.15, 0.20, Vector3(0, 0.40, 0), TEAL, 10, 0.14)
	box(root, Vector3(0.26, 0.25, 0.55), Vector3(0, 2.43, 0), CREAM)
	var rotor = Node3D.new()
	rotor.name = "Rotor"
	rotor.position = Vector3(0, 2.43, 0.34)
	root.add_child(rotor)
	var hub = cylinder(rotor, 0.14, 0.16, Vector3.ZERO, WHITE, 10, 0.09)
	hub.rotation.x = PI * 0.5
	for i in range(3):
		var blade = Node3D.new()
		rotor.add_child(blade)
		blade.rotation.z = i * TAU / 3.0
		var surface = box(blade, Vector3(0.115, 0.95, 0.045), Vector3(0.05, 0.57, 0), WHITE)
		surface.rotation.z = -0.1
		box(blade, Vector3(0.09, 0.15, 0.048), Vector3(0.09, 0.98, 0), ORANGE)

static func _battery(root: Node3D) -> void:
	for x in [-0.49, 0.02, 0.53]:
		box(root, Vector3(0.42, 1.02, 0.95), Vector3(x, 0.62, -0.06), WHITE)
		box(root, Vector3(0.44, 0.08, 1.0), Vector3(x, 1.17, -0.06), TEAL)
		box(root, Vector3(0.31, 0.66, 0.025), Vector3(x, 0.65, 0.425), MINT)
		for v in range(4):
			box(root, Vector3(0.22, 0.022, 0.015), Vector3(x, 0.46 + v * 0.11, 0.445), TEAL)
		box(root, Vector3(0.10, 0.05, 0.018), Vector3(x, 0.98, 0.445), ORANGE)
	box(root, Vector3(1.51, 0.13, 0.13), Vector3(0.0, 0.2, 0.64), METAL)

static func _substation(root: Node3D) -> void:
	for x in [-0.38, 0.32]:
		box(root, Vector3(0.5, 0.5, 0.7), Vector3(x, 0.41, 0), TEAL)
		box(root, Vector3(0.58, 0.10, 0.77), Vector3(x, 0.7, 0), CREAM)
		for fin in range(5):
			box(root, Vector3(0.56, 0.37, 0.032), Vector3(x, 0.43, -0.25 + fin * 0.125), METAL)
		for z in [-0.18, 0.18]:
			cylinder(root, 0.055, 0.34, Vector3(x, 0.89, z), CREAM, 8)
			for rib in range(3):
				cylinder(root, 0.08, 0.035, Vector3(x, 0.81 + rib * 0.09, z), DARK, 8)
	for x in [-0.72, 0.72]:
		box(root, Vector3(0.075, 1.43, 0.075), Vector3(x, 0.8, -0.65), METAL)
	box(root, Vector3(1.6, 0.075, 0.075), Vector3(0, 1.5, -0.65), DARK)
	for x in [-0.4, 0.0, 0.4]:
		cylinder(root, 0.055, 0.23, Vector3(x, 1.4, -0.65), CREAM, 8)
	box(root, Vector3(0.32, 0.53, 0.27), Vector3(0.64, 0.39, 0.6), WHITE)
	box(root, Vector3(0.18, 0.08, 0.02), Vector3(0.64, 0.47, 0.745), ORANGE)

static func _intertie(root: Node3D) -> void:
	# A coastal exchange terminal: HV portal, step-down transformer and data hut.
	box(root, Vector3(0.88, 0.63, 0.64), Vector3(0.11, 0.46, -0.12), BLUE, "IntertieTransformer")
	box(root, Vector3(0.99, 0.09, 0.74), Vector3(0.11, 0.82, -0.12), CREAM)
	for x in [-0.22, -0.06, 0.10, 0.26, 0.42]:
		box(root, Vector3(0.035, 0.47, 0.72), Vector3(x, 0.49, -0.12), METAL)
	for x in [-0.18, 0.35]:
		cylinder(root, 0.07, 0.36, Vector3(x, 1.04, -0.1), WHITE, 8)
		for rib in range(4):
			cylinder(root, 0.105, 0.035, Vector3(x, 0.92 + rib * 0.075, -0.1), TEAL, 8)
	# Tall paired gantries distinguish the terminal from the small substation.
	for z in [-0.66, 0.22]:
		for x in [-0.70, 0.70]:
			box(root, Vector3(0.095, 1.6, 0.095), Vector3(x, 0.92, z), METAL)
			box(root, Vector3(0.19, 0.17, 0.19), Vector3(x, 0.2, z), CREAM)
		box(root, Vector3(1.57, 0.10, 0.1), Vector3(0, 1.73, z), TEAL)
		for x in [-0.42, 0, 0.42]:
			cylinder(root, 0.052, 0.27, Vector3(x, 1.92, z), WHITE, 7)
			for rib in range(3):
				cylinder(root, 0.082, 0.032, Vector3(x, 1.84 + rib * 0.075, z), DARK, 7)
	for x in [-0.42, 0, 0.42]:
		beam(root, Vector3(x, 2.07, -0.66), Vector3(x, 2.07, 0.22), 0.021, ORANGE)
	# Operator / trading communications cabinet; deliberately no baked-in text.
	box(root, Vector3(0.48, 0.67, 0.40), Vector3(-0.52, 0.46, 0.57), WHITE, "TradingTerminal")
	box(root, Vector3(0.53, 0.075, 0.44), Vector3(-0.52, 0.84, 0.57), TEAL)
	box(root, Vector3(0.31, 0.19, 0.024), Vector3(-0.52, 0.58, 0.785), BLUE)
	box(root, Vector3(0.26, 0.035, 0.027), Vector3(-0.52, 0.41, 0.787), MINT)
	box(root, Vector3(0.08, 0.055, 0.027), Vector3(-0.62, 0.30, 0.787), ORANGE)
	cylinder(root, 0.016, 0.37, Vector3(-0.66, 1.06, 0.56), METAL, 6)
	cylinder(root, 0.035, 0.07, Vector3(-0.66, 1.27, 0.56), ORANGE, 6)
	# Orange-rimmed cable reel and landing duct suggest the off-island sea cable.
	var reel = Node3D.new()
	reel.name = "SeaCableReel"
	root.add_child(reel)
	reel.position = Vector3(0.39, 0.35, 0.64)
	reel.rotation.x = PI * 0.5
	cylinder(reel, 0.18, 0.30, Vector3.ZERO, DARK, 12)
	for side in [-1, 1]:
		cylinder(reel, 0.235, 0.035, Vector3(0, side * 0.165, 0), ORANGE, 12)
		cylinder(reel, 0.075, 0.045, Vector3(0, side * 0.18, 0), CREAM, 8)
	box(root, Vector3(0.26, 0.075, 0.25), Vector3(0.7, 0.16, 0.63), TEAL)
	beam(root, Vector3(0.60, 0.2, 0.63), Vector3(0.84, 0.2, 0.63), 0.05, DARK)

static func _control(root: Node3D) -> void:
	box(root, Vector3(1.5, 0.88, 1.12), Vector3(0, 0.56, -0.05), CREAM, "DispatchOffice")
	box(root, Vector3(1.57, 0.11, 1.22), Vector3(0, 1.05, -0.05), TEAL)
	box(root, Vector3(1.27, 0.46, 0.025), Vector3(0, 0.69, 0.527), BLUE, "ControlRoomGlazing")
	for x in [-0.43, 0.0, 0.43]:
		box(root, Vector3(0.035, 0.48, 0.035), Vector3(x, 0.69, 0.545), WHITE)
	box(root, Vector3(1.31, 0.025, 0.035), Vector3(0, 0.69, 0.545), METAL)
	box(root, Vector3(0.025, 0.40, 0.75), Vector3(0.762, 0.70, -0.05), BLUE)
	box(root, Vector3(0.35, 0.36, 0.04), Vector3(-0.47, 0.31, 0.54), TEAL)
	box(root, Vector3(0.47, 0.06, 0.32), Vector3(-0.47, 0.52, 0.67), ORANGE)
	box(root, Vector3(0.60, 0.07, 0.24), Vector3(-0.47, 0.15, 0.69), WHITE)
	# Compact rooftop equipment and a steerable satellite dish.
	box(root, Vector3(0.50, 0.24, 0.42), Vector3(-0.31, 1.23, -0.17), MINT)
	for z in [-0.29, -0.17, -0.05]:
		box(root, Vector3(0.39, 0.025, 0.02), Vector3(-0.31, 1.36, z), TEAL)
	cylinder(root, 0.045, 0.31, Vector3(0.43, 1.25, 0.12), METAL, 8)
	var dish = Node3D.new()
	dish.name = "SatelliteDish"
	dish.position = Vector3(0.43, 1.47, 0.12)
	dish.rotation.x = -0.58
	dish.rotation.z = -0.26
	root.add_child(dish)
	cylinder(dish, 0.25, 0.09, Vector3.ZERO, WHITE, 16, 0.30)
	cylinder(dish, 0.255, 0.015, Vector3(0, 0.052, 0), METAL, 16)
	beam(dish, Vector3(-0.20, 0.06, 0), Vector3(0, 0.25, 0), 0.013, WHITE)
	beam(dish, Vector3(0.20, 0.06, 0), Vector3(0, 0.25, 0), 0.013, WHITE)
	cylinder(dish, 0.045, 0.09, Vector3(0, 0.27, 0), ORANGE, 8)
	cylinder(root, 0.018, 0.64, Vector3(-0.60, 1.43, -0.43), METAL, 6)
	box(root, Vector3(0.36, 0.025, 0.025), Vector3(-0.60, 1.63, -0.43), WHITE)
	cylinder(root, 0.038, 0.055, Vector3(-0.60, 1.78, -0.43), ORANGE, 6)

static func _relay(root: Node3D) -> void:
	box(root, Vector3(0.61, 0.83, 0.62), Vector3(-0.43, 0.52, 0.39), MINT, "RelayCabinet")
	box(root, Vector3(0.68, 0.08, 0.69), Vector3(-0.43, 0.98, 0.39), WHITE)
	box(root, Vector3(0.47, 0.66, 0.025), Vector3(-0.43, 0.55, 0.713), TEAL)
	for y in [0.36, 0.46, 0.56, 0.66]:
		box(root, Vector3(0.31, 0.02, 0.014), Vector3(-0.43, y, 0.733), MINT)
	box(root, Vector3(0.12, 0.055, 0.016), Vector3(-0.43, 0.81, 0.734), ORANGE)
	box(root, Vector3(0.46, 0.43, 0.48), Vector3(0.44, 0.33, 0.49), ORANGE, "BackupUPS")
	box(root, Vector3(0.48, 0.06, 0.50), Vector3(0.44, 0.58, 0.49), CREAM)
	box(root, Vector3(0.25, 0.12, 0.025), Vector3(0.44, 0.39, 0.744), DARK)
	# Three legs taper towards a tall mast, all within the original tile.
	var tip := Vector3(0.18, 2.72, -0.30)
	for foot in [Vector3(-0.26, 0.13, -0.64), Vector3(0.59, 0.13, -0.64), Vector3(0.18, 0.13, 0.12)]:
		beam(root, foot, tip, 0.036, METAL)
		box(root, Vector3(0.19, 0.10, 0.18), foot, CREAM)
	for y in [0.65, 1.15, 1.65, 2.15]:
		var width: float = 0.72 * (1.0 - float(y) / 3.0)
		box(root, Vector3(width, 0.035, 0.08), Vector3(0.18, y, -0.41), DARK)
	cylinder(root, 0.025, 0.40, Vector3(0.18, 2.80, -0.30), METAL, 6)
	cylinder(root, 0.055, 0.075, Vector3(0.18, 3.035, -0.30), ORANGE, 8)
	for side in [-1, 1]:
		var sector = Node3D.new()
		sector.name = "SectorAntennaLeft" if side < 0 else "SectorAntennaRight"
		sector.position = Vector3(0.18 + side * 0.27, 2.27, -0.12)
		sector.rotation.y = side * 0.58
		root.add_child(sector)
		box(sector, Vector3(0.32, 0.72, 0.12), Vector3.ZERO, WHITE)
		box(sector, Vector3(0.22, 0.025, 0.012), Vector3(0, -0.25, 0.069), MINT)
		beam(root, Vector3(0.18, 2.35, -0.30), sector.position, 0.027, METAL)

static func _soc(root: Node3D) -> void:
	box(root, Vector3(1.52, 0.67, 1.26), Vector3(0, 0.45, -0.01), BLUE, "SecurityOperations")
	box(root, Vector3(1.60, 0.09, 1.34), Vector3(0, 0.83, -0.01), TEAL)
	box(root, Vector3(1.11, 0.44, 0.65), Vector3(-0.06, 1.10, -0.20), CREAM, "SecureServerRoom")
	box(root, Vector3(1.18, 0.075, 0.71), Vector3(-0.06, 1.36, -0.20), WHITE)
	for x in [-0.39, -0.08, 0.23]:
		box(root, Vector3(0.21, 0.28, 0.025), Vector3(x, 1.11, 0.135), TEAL)
		for led in range(3):
			box(root, Vector3(0.11, 0.018, 0.014), Vector3(x, 1.03 + led * 0.065, 0.154), MINT)
	for x in [-0.59, 0.59]:
		box(root, Vector3(0.18, 0.32, 0.025), Vector3(x, 0.49, 0.637), MINT)
	box(root, Vector3(0.025, 0.20, 0.79), Vector3(0.772, 0.53, -0.04), DARK)
	for z in [-0.31, -0.11, 0.09, 0.29]:
		box(root, Vector3(0.025, 0.15, 0.09), Vector3(0.789, 0.53, z), METAL)
	box(root, Vector3(0.45, 0.11, 0.25), Vector3(0, 0.16, 0.73), WHITE)
	_shield(root, Vector3(0, 0.52, 0.652), 1.0, WHITE)
	_shield(root, Vector3(0, 0.52, 0.660), 0.76, TEAL)
	box(root, Vector3(0.07, 0.17, 0.015), Vector3(0, 0.51, 0.670), ORANGE)
	var seal = cylinder(root, 0.057, 0.015, Vector3(0, 0.60, 0.675), ORANGE, 10)
	seal.rotation.x = PI * 0.5
	cylinder(root, 0.10, 0.12, Vector3(0.62, 0.97, -0.47), METAL, 10)

static func _shield(root: Node3D, at: Vector3, factor: float, color: Color) -> void:
	var outline = [Vector2(-0.25, 0.25), Vector2(0.25, 0.25), Vector2(0.21, -0.08), Vector2(0, -0.30), Vector2(-0.21, -0.08)]
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	for i in range(outline.size()):
		for point in [Vector2.ZERO, outline[i], outline[(i + 1) % outline.size()]]:
			vertices.append(Vector3(point.x * factor, point.y * factor, 0))
			normals.append(Vector3.BACK)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	var mat = material(color)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = mat
	root.add_child(instance)

static func _factory(root: Node3D) -> void:
	box(root, Vector3(1.4, 0.76, 1.05), Vector3(0, 0.49, 0.11), CREAM)
	box(root, Vector3(1.48, 0.14, 1.13), Vector3(0, 0.93, 0.11), ORANGE)
	for x in [-0.44, 0, 0.44]:
		box(root, Vector3(0.31, 0.20, 0.025), Vector3(x, 0.66, 0.647), BLUE)
		box(root, Vector3(0.32, 0.18, 0.7), Vector3(x, 1.07, 0), TEAL)
	box(root, Vector3(0.50, 0.43, 0.025), Vector3(0.36, 0.33, 0.65), METAL)
	for j in range(4):
		box(root, Vector3(0.50, 0.015, 0.015), Vector3(0.36, 0.2 + j * 0.085, 0.67), DARK)
	cylinder(root, 0.17, 1.6, Vector3(-0.58, 0.91, -0.59), CORAL, 8, 0.12)
	cylinder(root, 0.16, 0.16, Vector3(-0.58, 1.65, -0.59), CREAM, 8, 0.15)
	box(root, Vector3(0.25, 0.35, 0.25), Vector3(-0.52, 0.29, 0.69), TEAL)

static func _hospital(root: Node3D) -> void:
	box(root, Vector3(1.38, 1.2, 1.2), Vector3(0, 0.71, -0.04), WHITE)
	box(root, Vector3(1.5, 0.11, 1.33), Vector3(0, 1.36, -0.04), TEAL)
	box(root, Vector3(1.38, 0.1, 1.23), Vector3(0, 0.78, -0.04), MINT)
	for x in [-0.49, -0.16, 0.17, 0.5]:
		for y in [0.52, 1.04]:
			box(root, Vector3(0.23, 0.24, 0.025), Vector3(x, y, 0.571), BLUE)
	box(root, Vector3(0.3, 0.39, 0.03), Vector3(0, 0.31, 0.59), TEAL)
	box(root, Vector3(0.73, 0.07, 0.35), Vector3(0, 0.62, 0.69), ORANGE)
	box(root, Vector3(0.72, 0.43, 0.62), Vector3(0, 1.6, -0.04), CREAM)
	box(root, Vector3(0.12, 0.32, 0.025), Vector3(0, 1.64, 0.285), CORAL)
	box(root, Vector3(0.33, 0.12, 0.025), Vector3(0, 1.64, 0.29), CORAL)

static func _sensor(root: Node3D) -> void:
	box(root, Vector3(0.65, 0.55, 0.65), Vector3(-0.4, 0.39, 0.35), CREAM)
	box(root, Vector3(0.71, 0.09, 0.7), Vector3(-0.4, 0.72, 0.35), TEAL)
	box(root, Vector3(0.25, 0.30, 0.025), Vector3(-0.4, 0.34, 0.686), BLUE)
	for x in [-0.23, 0.23]:
		beam(root, Vector3(0.27 + x, 0.12, -0.4), Vector3(0.27, 2.2, -0.4), 0.045, METAL)
	beam(root, Vector3(0.27, 0.12, -0.66), Vector3(0.27, 2.2, -0.4), 0.045, METAL)
	for y in [0.5, 0.9, 1.3, 1.7]:
		box(root, Vector3(0.40 * (1.0 - y / 2.5), 0.04, 0.16), Vector3(0.27, y, -0.4), DARK)
	cylinder(root, 0.035, 0.55, Vector3(0.27, 2.35, -0.4), ORANGE, 6)
	for z in [-0.48, -0.27]:
		box(root, Vector3(0.23, 0.38, 0.08), Vector3(0.27, 1.98, z), WHITE)

static func tree(seed: int = 0) -> Node3D:
	var root = Node3D.new()
	root.name = "Pine"
	var variation = 0.88 + (seed % 7) * 0.055
	cylinder(root, 0.085, 0.47, Vector3(0, 0.23, 0), Color("8c7760"), 6)
	var greens = [Color("4d8c73"), Color("629a78"), Color("82ab85")]
	for i in range(3):
		cylinder(root, (0.43 - i * 0.095) * variation, 0.66 * variation, Vector3(0, (0.65 + i * 0.36) * variation, 0), greens[(i + seed) % 3], 7, 0.025)
	root.rotation.y = seed * 1.27
	return root

static func rock(seed: int = 0) -> Node3D:
	var root = Node3D.new()
	root.name = "CoastalRock"
	var mesh = SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	mesh.radial_segments = 6
	mesh.rings = 2
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material(Color("99afa1") if seed % 2 == 0 else Color("b8c4af"))
	instance.scale = Vector3(1.1 + (seed % 3) * 0.2, 0.65, 0.9)
	instance.position.y = 0.15
	instance.rotation.y = seed * 0.89
	root.add_child(instance)
	return root

static func pylon() -> Node3D:
	var root = Node3D.new()
	root.name = "PowerPole"
	cylinder(root, 0.045, 1.12, Vector3(0, 0.56, 0), Color("b89e79"), 6)
	box(root, Vector3(0.56, 0.055, 0.065), Vector3(0, 1.07, 0), DARK)
	for x in [-0.22, 0.22]:
		cylinder(root, 0.045, 0.10, Vector3(x, 1.13, 0), CREAM, 6)
	return root

static func vehicle() -> Node3D:
	var root = Node3D.new()
	root.name = "UtilityVan"
	box(root, Vector3(0.4, 0.28, 0.77), Vector3(0, 0.26, 0), ORANGE)
	box(root, Vector3(0.37, 0.21, 0.4), Vector3(0, 0.48, 0.1), WHITE)
	box(root, Vector3(0.30, 0.13, 0.015), Vector3(0, 0.49, 0.31), BLUE)
	box(root, Vector3(0.24, 0.04, 0.04), Vector3(0, 0.63, 0.10), ORANGE)
	for x in [-0.21, 0.21]:
		for z in [-0.24, 0.24]:
			var wheel = cylinder(root, 0.095, 0.065, Vector3(x, 0.15, z), DARK, 10)
			wheel.rotation.z = PI * 0.5
	return root
