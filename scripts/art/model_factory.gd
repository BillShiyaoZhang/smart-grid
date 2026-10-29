class_name GridModelFactory
extends RefCounted

## One reproducible source for every live miniature, editable scene and icon.
## Bases occupy a 2 m cell. Wind blades may overhang above their neighbours.
const KINDS := ["gas", "solar", "wind", "battery", "substation", "home", "factory", "hospital", "sensor", "intertie", "control", "relay", "soc", "dc_dynamo", "steam", "coal", "hydro", "cooling", "academy", "nuclear", "pumped_storage", "condenser", "hvdc", "ccgt", "flow_battery", "community_battery", "hydrogen", "thermal_storage", "fusion"]
const CREAM = Color("eee3cb")
const WHITE = Color("fbf3dd")
const MINT = Color("87bbaa")
const TEAL = Color("29676a")
const BLUE = Color("26495e")
const DARK = Color("213a43")
const ORANGE = Color("ce965c")
const CORAL = Color("b6755d")
const METAL = Color("93aaa4")
const CONCRETE = Color("bab9a4")
const STONE = Color("d6cbb3")
const BRICK = Color("a87055")
static var _materials: Dictionary = {}
static var _bevels: Dictionary = {}
static var _prefabs: Dictionary = {}

static func material(color: Color, metallic: float = 0.0, roughness: float = 0.82) -> StandardMaterial3D:
	var key := "%s:%.2f:%.2f" % [color.to_html(),metallic,roughness]
	if _materials.has(key): return _materials[key]
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	m.metallic_specular = 0.3
	_materials[key] = m
	return m

static func box(parent: Node3D, size: Vector3, at: Vector3, color: Color, title: String = "") -> MeshInstance3D:
	var instance = MeshInstance3D.new()
	instance.mesh = _bevel_mesh(size)
	instance.material_override = material(color)
	instance.position = at
	if not title.is_empty(): instance.name = title
	parent.add_child(instance)
	return instance

## Chamfered edges catch the light without a postprocessing dependency.
static func _bevel_mesh(size: Vector3) -> ArrayMesh:
	var key := str(size)
	if _bevels.has(key): return _bevels[key]
	var h := size * 0.5
	var bevel := minf(0.035,minf(size.x,minf(size.y,size.z))*0.17)
	var inner := h-Vector3.ONE*bevel
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for axis in range(3):
		var u: int=(axis+1)%3
		var v: int=(axis+2)%3
		for sign_ in [-1.0,1.0]:
			var normal := Vector3.ZERO
			normal[axis]=sign_
			var points: Array[Vector3]=[]
			for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
				var point := Vector3.ZERO
				point[axis]=h[axis]*sign_
				point[u]=inner[u]*corner.x
				point[v]=inner[v]*corner.y
				points.append(point)
			_quad(vertices,normals,points[0],points[1],points[2],points[3],normal)
	for axis in range(3):
		var u: int=(axis+1)%3
		var v: int=(axis+2)%3
		for su in [-1.0,1.0]:
			for sv in [-1.0,1.0]:
				var a := Vector3.ZERO
				var b := Vector3.ZERO
				a[axis]=-inner[axis]; b[axis]=-inner[axis]
				a[u]=h[u]*su; a[v]=inner[v]*sv
				b[u]=inner[u]*su; b[v]=h[v]*sv
				var c:=b; c[axis]=inner[axis]
				var d:=a; d[axis]=inner[axis]
				var normal:=Vector3.ZERO; normal[u]=su; normal[v]=sv
				_quad(vertices,normals,a,b,c,d,normal.normalized())
	for sx in [-1.0,1.0]:
		for sy in [-1.0,1.0]:
			for sz in [-1.0,1.0]:
				var sign_ := Vector3(sx,sy,sz)
				var a:=inner*sign_; a.x=h.x*sx
				var b:=inner*sign_; b.y=h.y*sy
				var c:=inner*sign_; c.z=h.z*sz
				_triangle(vertices,normals,a,b,c,sign_.normalized())
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_bevels[key]=mesh
	return mesh

static func _triangle(vertices: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	var points: Array=[a,c,b] if (b-a).cross(c-a).dot(normal)>0 else [a,b,c]
	for point in points:
		vertices.append(point)
		normals.append(normal)

static func _quad(vertices: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	_triangle(vertices,normals,a,b,c,normal)
	_triangle(vertices,normals,a,c,d,normal)

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
	if kind=="synchronous_condenser": kind="condenser"
	if _prefabs.has(kind): return _prefabs[kind].instantiate()
	var root = Node3D.new()
	root.name = kind.capitalize()
	root.set_meta("asset_kind",kind)
	root.set_meta("asset_revision",2)
	box(root, Vector3(1.84, 0.09, 1.84), Vector3(0, 0.045, 0), STONE, "Foundation")
	box(root, Vector3(1.76, 0.045, 1.76), Vector3(0, 0.105, 0), CONCRETE,"Courtyard")
	for i in range(4):
		box(root,Vector3(0.415,0.025,0.13),Vector3(-0.65+float(i)*0.435,0.14,0.80),CREAM)
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
		"dc_dynamo": _dynamo(root)
		"steam": _steam(root)
		"coal": _coal(root)
		"hydro": _hydro(root)
		"nuclear": _nuclear(root)
		"cooling": _cooling(root)
		"academy": _academy(root)
		"pumped_storage": _pumped_storage(root)
		"flow_battery": _flow_battery(root)
		"hydrogen": _hydrogen(root)
		"hvdc": _hvdc(root)
		"synchronous_condenser": _condenser(root)
		"condenser": _condenser(root)
		"ccgt": _ccgt(root)
		"community_battery": _community_battery(root)
		"thermal_storage": _thermal_storage(root)
		"fusion": _fusion(root)
		_: _home(root)
	_finish_building(root,kind)
	_merge_static_geometry(root)
	var bounds:=geometry_bounds(root)
	root.set_meta("bounds",bounds)
	root.set_meta("pick_height",maxf(0.65,bounds.end.y))
	root.set_meta("label_anchor",Vector3(0,bounds.end.y+0.3,0))
	_set_owner(root,root)
	var prefab:=PackedScene.new()
	if prefab.pack(root)==OK: _prefabs[kind]=prefab
	return root

static func _set_owner(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner=root
		_set_owner(child,root)

## One static mesh per paint material instead of one draw for every window rib.
## Movable rotor geometry remains separate and keeps its original local transforms.
static func _merge_static_geometry(root: Node3D) -> void:
	var buckets: Dictionary={}
	var sources: Array[MeshInstance3D]=[]
	_collect_static(root,Transform3D.IDENTITY,buckets,sources)
	for source in sources: source.free()
	var index:=0
	for key in buckets:
		var bucket: Dictionary=buckets[key]
		var arrays:=[]
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=bucket.vertices
		arrays[Mesh.ARRAY_NORMAL]=bucket.normals
		arrays[Mesh.ARRAY_INDEX]=bucket.indices
		var mesh:=ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var part:=MeshInstance3D.new()
		part.name="MiniaturePaint%02d" % index
		part.mesh=mesh
		part.material_override=bucket.material
		root.add_child(part)
		index+=1
	root.set_meta("static_material_count",index)

static func _collect_static(node: Node3D, transform_: Transform3D, buckets: Dictionary, sources: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if not child is Node3D or child.name=="Rotor": continue
		var local: Transform3D=transform_*child.transform
		if child is MeshInstance3D and child.mesh!=null:
			for surface in range(child.mesh.get_surface_count()):
				var paint: Material=child.material_override if child.material_override!=null else child.mesh.surface_get_material(surface)
				var key: int=paint.get_instance_id() if paint!=null else 0
				if not buckets.has(key):
					buckets[key]={"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"indices":PackedInt32Array(),"material":paint}
				var bucket: Dictionary=buckets[key]
				var arrays: Array=child.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
				var offset: int=bucket.vertices.size()
				var normal_basis:=local.basis.inverse().transposed()
				for i in range(vertices.size()):
					bucket.vertices.append(local*vertices[i])
					bucket.normals.append((normal_basis*normals[i]).normalized() if i<normals.size() else Vector3.UP)
				var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
				if indices.is_empty():
					for i in range(vertices.size()): bucket.indices.append(offset+i)
				else:
					for i in indices: bucket.indices.append(offset+i)
			sources.append(child)
		_collect_static(child,local,buckets,sources)

static func geometry_bounds(root: Node3D) -> AABB:
	return _bounds_recursive(root,Transform3D.IDENTITY)

static func _bounds_recursive(node: Node3D, transform_: Transform3D) -> AABB:
	var result:=AABB()
	if node is MeshInstance3D and node.mesh!=null:
		result=transform_*node.get_aabb()
	for child in node.get_children():
		if not child is Node3D: continue
		var bounds:=_bounds_recursive(child,transform_*child.transform)
		if bounds.size.length_squared()>0:
			result=bounds if result.size.length_squared()==0 else result.merge(bounds)
	return result

## A small architectural vocabulary supplies coherent materials, not shared silhouettes.
static func _finish_building(root: Node3D, kind: String) -> void:
	var detail:=Node3D.new()
	detail.name="CraftDetails"
	root.add_child(detail)
	# Inlaid brass identification plate and a recessed, low connection terminal.
	box(detail,Vector3(.23,.018,.075),Vector3(.56,.158,.80),ORANGE,"AssetPlate")
	box(detail,Vector3(.19,.12,.16),Vector3(-.68,.21,.65),DARK,"CableTerminal")
	box(detail,Vector3(.12,.025,.13),Vector3(-.68,.285,.65),METAL)
	match kind:
		"home":
			_roof(root,Vector3(-.1,.94,-.08),1.28,1.28,.33,TEAL)
			_arch_window(detail,Vector3(-.45,.62,.475),.19,.29)
			_arch_window(detail,Vector3(.25,.62,.475),.19,.29)
			box(detail,Vector3(.34,.04,.36),Vector3(-.08,.55,.63),ORANGE)
			_planter(detail,Vector3(.62,.18,-.55),.23)
		"factory":
			for x in [-.43,0,.43]:
				_arch_window(detail,Vector3(x,.67,.67),.23,.34)
				_roof(detail,Vector3(x,1.11,-.04),.45,.96,.18,TEAL)
			box(detail,Vector3(.45,.24,.24),Vector3(.48,.25,.65),ORANGE)
		"hospital":
			for x in [-.54,-.18,.18,.54]:
				box(detail,Vector3(.31,.04,.08),Vector3(x,.91,.63),WHITE)
			box(detail,Vector3(.48,.07,.27),Vector3(0,.17,.72),WHITE)
			_planter(detail,Vector3(.72,.18,.7),.17)
		"gas", "ccgt":
			for x in [-.52,-.18,.16]:
				box(detail,Vector3(.23,.025,.08),Vector3(x,.39,.55 if kind=="gas" else .73),STONE)
			for z in [-.48,.1,.48]:
				box(detail,Vector3(.025,.22,.15),Vector3(.42,.45,z),METAL)
			box(detail,Vector3(.47,.025,.4),Vector3(-.28,.965 if kind=="gas" else .91,.05),BLUE)
		"dc_dynamo":
			for x in [-.58,-.17,.24]:
				_arch_window(detail,Vector3(x,.51,.647),.24,.36)
			for y in [.25,.73]:
				box(detail,Vector3(1.3,.035,.035),Vector3(-.12,y,.655),STONE)
			_roof(detail,Vector3(-.12,.84,0),1.42,1.34,.27,TEAL)
			_brick_bands(detail,Vector3(-.12,.48,.64),1.30,.57)
		"coal":
			for x in [-.64,-.27,.10]:
				_arch_window(detail,Vector3(x,.66,.655),.22,.48)
			for y in [.26,.95]:
				box(detail,Vector3(1.15,.05,.06),Vector3(-.25,y,.65),STONE)
			box(detail,Vector3(.82,.08,.92),Vector3(-.25,1.25,0),TEAL)
			for x in [-.72,.22]:
				box(detail,Vector3(.055,.8,.06),Vector3(x,.65,.65),CREAM)
			_brick_bands(detail,Vector3(-.25,.6,.64),1.15,.9)
		"steam":
			for x in [-.55,.45]:
				box(detail,Vector3(.10,.12,.96),Vector3(x,.28,-.1),STONE)
			for z in [-.58,.18]:
				beam(detail,Vector3(-.55,.75,z),Vector3(.32,.75,z),.028,ORANGE)
			var flywheel:=Node3D.new()
			detail.add_child(flywheel)
			flywheel.position=Vector3(-.4,.52,.58)
			for i in range(8):
				var theta:=TAU*float(i)/8.0
				beam(flywheel,Vector3.ZERO,Vector3(cos(theta)*.23,sin(theta)*.23,0),.018,ORANGE)
		"wind":
			for i in range(3):
				var theta:=TAU*float(i)/3.0
				cylinder(detail,.035,.09,Vector3(cos(theta)*.27,.3,sin(theta)*.27),METAL,8)
			_planter(detail,Vector3(-.62,.18,-.62),.21)
		"solar":
			for x in [-.45,.35]:
				beam(detail,Vector3(x,.17,-.75),Vector3(x,.17,.65),.018,ORANGE)
			box(detail,Vector3(.33,.035,.36),Vector3(.57,.52,.56),TEAL)
		"battery", "community_battery":
			var xs: Array=[-.49,.02,.53] if kind=="battery" else [-.43,.22]
			for x in xs:
				box(detail,Vector3(.035,.21,.028),Vector3(float(x)+.11,.72,.47 if kind=="battery" else .36),METAL)
				_bolt(detail,Vector3(float(x)-.07,.8,.46 if kind=="battery" else .36),.13,MINT)
		"substation", "intertie":
			_fence(detail,-.78,.78,-.75,.73)
			for z in [-.3,.3]:
				beam(detail,Vector3(-.45,.25,z),Vector3(.45,.25,z),.026,ORANGE)
		"control":
			for x in [-.43,0,.43]:
				box(detail,Vector3(.3,.04,.14),Vector3(x,.47,.60),STONE)
			box(detail,Vector3(.45,.3,.48),Vector3(.42,1.23,-.23),CREAM)
			box(detail,Vector3(.49,.06,.52),Vector3(.42,1.42,-.23),TEAL)
		"soc":
			for z in [-.42,-.14,.14]:
				box(detail,Vector3(.07,.40,.025),Vector3(.78,.49,z),STONE)
			box(detail,Vector3(.18,.17,.18),Vector3(-.64,1.0,.44),MINT)
			box(detail,Vector3(.2,.035,.20),Vector3(-.64,1.1,.44),TEAL)
		"sensor", "relay":
			box(detail,Vector3(.25,.1,.23),Vector3(-.43,.82 if kind=="sensor" else 1.05,.35),WHITE)
			for x in [-.64,-.48,-.32]:
				box(detail,Vector3(.05,.025,.16),Vector3(x,.16,.72),ORANGE)
		"hydro":
			for x in [-.54,0,.54]:
				box(detail,Vector3(.23,.025,.36),Vector3(x,.23,.53),WHITE)
				box(detail,Vector3(.028,.035,.52),Vector3(x,.25,.51),MINT)
			_rail(detail,Vector3(-.78,1.18,-.26),Vector3(.78,1.18,-.26))
		"pumped_storage":
			for z in [-.69,-.18]:
				box(detail,Vector3(1.46,.09,.07),Vector3(0,.82,z),STONE)
			for x in [-.7,.7]:
				box(detail,Vector3(.07,.09,.5),Vector3(x,.82,-.43),STONE)
			_roof(detail,Vector3(0,.62,.12),.52,.55,.14,TEAL)
		"nuclear":
			for z in [-.48,-.2,.08,.36]:
				box(detail,Vector3(.025,.47,.06),Vector3(-.79,.48,z),STONE)
			cylinder(detail,.48,.065,Vector3(.26,.77,-.1),STONE,24)
			box(detail,Vector3(.18,.21,.025),Vector3(-.43,.51,.62),BLUE)
		"cooling":
			for x in [-.43,.43]:
				for i in range(10):
					var theta:=TAU*float(i)/10.0
					beam(detail,Vector3(x+cos(theta)*.30,.2,sin(theta)*.30),Vector3(x+cos(theta)*.23,.8,sin(theta)*.23),.013,STONE)
		"academy":
			_roof(detail,Vector3(0,1.02,0),1.48,1.27,.29,TEAL)
			for x in [-.48,0,.48]:
				box(detail,Vector3(.08,.74,.08),Vector3(x,.53,.65),STONE)
			box(detail,Vector3(.76,.09,.32),Vector3(0,.96,.65),WHITE)
		"hvdc":
			_fence(detail,-.8,.8,-.75,.73)
			for z in [-.44,-.1,.24]:
				box(detail,Vector3(.025,.35,.13),Vector3(-.825,.55,z),METAL)
		"condenser":
			for x in [-.45,-.3,-.15,0,.15,.3,.45]:
				var ring:=cylinder(detail,.355,.025,Vector3(x,.65,0),METAL,16)
				ring.rotation.z=PI*.5
			_rail(detail,Vector3(-.74,.27,.60),Vector3(.16,.27,.60))
		"flow_battery", "thermal_storage", "hydrogen":
			var tank_top:=1.2 if kind!="hydrogen" else 1.15
			var tank_xs: Array=[-.5,0,.5] if kind=="hydrogen" else [-.46,.46]
			for x in tank_xs:
				cylinder(detail,.055,.07,Vector3(float(x),tank_top,-.2 if kind!="hydrogen" else -.3),DARK,10)
				beam(detail,Vector3(float(x),.4,.33),Vector3(float(x),.4,.62),.026,ORANGE)
			box(detail,Vector3(.05,.52,.05),Vector3(-.79,.41,-.18),METAL)
			for y in [.2,.32,.44,.56]:
				box(detail,Vector3(.17,.02,.04),Vector3(-.72,float(y),-.18),METAL)
		"fusion":
			for i in range(8):
				var theta:=TAU*float(i)/8.0
				cylinder(detail,.055,.11,Vector3(sin(theta)*.74,.25,cos(theta)*.74),STONE,8)
			box(detail,Vector3(.24,.20,.028),Vector3(0,.4,.825),BLUE)

static func _arch_window(root: Node3D, at: Vector3, width: float, height: float) -> void:
	box(root,Vector3(width+.07,height,.035),at,STONE)
	var arch:=cylinder(root,(width+.07)*.5,.035,at+Vector3(0,height*.5,0),STONE,16)
	arch.rotation.x=PI*.5
	box(root,Vector3(width,height-.035,.025),at+Vector3(0,0,.025),BLUE)
	var glass:=cylinder(root,width*.5,.025,at+Vector3(0,height*.5,.027),BLUE,16)
	glass.rotation.x=PI*.5
	box(root,Vector3(.022,height+width*.38,.03),at+Vector3(0,.04,.045),CREAM)
	box(root,Vector3(width,.018,.035),at+Vector3(0,.025,.047),CREAM)
	box(root,Vector3(width+.12,.045,.10),at+Vector3(0,-height*.5-.02,.03),WHITE)

static func _roof(root: Node3D, at: Vector3, width: float, depth: float, rise: float, color: Color) -> void:
	var angle:=atan2(rise,width*.5)
	var plane_width:=sqrt(pow(width*.5,2)+rise*rise)
	for side in [-1.0,1.0]:
		var roof:=box(root,Vector3(plane_width+.045,.075,depth),at+Vector3(width*.25*side,rise*.5,0),color,"RoofPlane")
		roof.rotation.z=-angle*side
		for i in range(6):
			var rib:=box(root,Vector3(plane_width+.045,.013,.014),roof.position+Vector3(0,.048,-depth*.42+float(i)*depth*.168),color.lightened(.12))
			rib.rotation.z=roof.rotation.z
	box(root,Vector3(.065,.07,depth+.035),at+Vector3(0,rise+.025,0),ORANGE,"RoofRidge")

static func _brick_bands(root: Node3D, at: Vector3, width: float, height: float) -> void:
	for i in range(4):
		box(root,Vector3(width,.009,.008),at+Vector3(0,-height*.45+float(i)*height*.28,.01),CREAM.darkened(.1))

static func _planter(root: Node3D, at: Vector3, radius: float) -> void:
	cylinder(root,radius,.12,at,STONE,8)
	cylinder(root,radius*.85,.06,at+Vector3(0,.07,0),Color("5b7660"),8)
	for i in range(3):
		var angle:=float(i)*TAU/3.0
		cylinder(root,radius*.55,.22,at+Vector3(cos(angle)*radius*.35,.19,sin(angle)*radius*.35),MINT.darkened(float(i)*.12),7,.035)

static func _rail(root: Node3D, a: Vector3, b: Vector3) -> void:
	beam(root,a+Vector3.UP*.19,b+Vector3.UP*.19,.014,METAL)
	beam(root,a+Vector3.UP*.09,b+Vector3.UP*.09,.009,METAL)
	for i in range(5):
		var at:=a.lerp(b,float(i)/4.0)
		beam(root,at,at+Vector3.UP*.23,.014,ORANGE)

static func _fence(root: Node3D, left: float, right: float, back: float, front: float) -> void:
	for x in [left,right]:
		_rail(root,Vector3(x,.13,back),Vector3(x,.13,front))
	_rail(root,Vector3(left,.13,back),Vector3(right,.13,back))

static func _bolt(root: Node3D, at: Vector3, factor: float, color: Color) -> void:
	var a:=box(root,Vector3(.18,.7,.016)*factor,at+Vector3(-.05,.2,0)*factor,color)
	a.rotation.z=-.4
	var b:=box(root,Vector3(.18,.7,.016)*factor,at+Vector3(.05,-.2,0)*factor,color)
	b.rotation.z=-.4
	box(root,Vector3(.5,.16,.016)*factor,at,color)

static func _dynamo(root: Node3D) -> void:
	box(root,Vector3(1.3,.65,1.2),Vector3(-.12,.43,0),Color("b78061"))
	box(root,Vector3(1.42,.12,1.32),Vector3(-.12,.81,0),DARK)
	box(root,Vector3(.8,.31,.035),Vector3(-.12,.52,.62),ORANGE)
	for x in [-.4,-.08,.24]:
		box(root,Vector3(.025,.36,.045),Vector3(x,.52,.65),DARK)
	cylinder(root,.12,1.45,Vector3(.65,.82,-.46),CORAL,8)
	var wheel := cylinder(root,.27,.16,Vector3(.6,.43,.35),METAL,12)
	wheel.rotation.x = PI*.5
	cylinder(root,.09,.35,Vector3(-.45,1.04,-.1),ORANGE,8)
	box(root,Vector3(.5,.035,.035),Vector3(-.45,1.2,-.1),METAL)

static func _coal(root: Node3D) -> void:
	box(root,Vector3(1.15,1.0,1.25),Vector3(-.25,.61,0),BRICK)
	box(root,Vector3(1.2,.1,1.3),Vector3(-.25,1.15,0),DARK)
	for z in [-.44,.35]:
		cylinder(root,.15,1.8,Vector3(.58,1.0,z),CORAL,10,.11)
		cylinder(root,.135,.18,Vector3(.58,1.6,z),CREAM,10)
	for i in range(4):
		box(root,Vector3(.18,.3,.025),Vector3(-.65+i*.26,.65,.64),BLUE)
	box(root,Vector3(.7,.23,.28),Vector3(-.2,.23,.72),DARK)

static func _steam(root: Node3D) -> void:
	box(root,Vector3(1.3,.15,1.25),Vector3(0,.2,0),DARK)
	var boiler := cylinder(root,.33,1.15,Vector3(-.1,.58,-.2),CORAL,12)
	boiler.rotation.z = PI*.5
	cylinder(root,.1,1.1,Vector3(.45,1.15,-.2),DARK,10)
	var flywheel := cylinder(root,.29,.12,Vector3(-.4,.52,.49),METAL,12)
	flywheel.rotation.x = PI*.5
	beam(root,Vector3(-.4,.52,.55),Vector3(.45,.52,.55),.06,ORANGE)
	box(root,Vector3(.4,.45,.38),Vector3(.47,.43,.4),CREAM)
	beam(root,Vector3(.3,.88,-.2),Vector3(.47,.66,.4),.045,METAL)

static func _ccgt(root: Node3D) -> void:
	box(root,Vector3(1.2,.65,.75),Vector3(-.2,.46,.3),WHITE)
	box(root,Vector3(1.29,.09,.83),Vector3(-.2,.83,.3),TEAL)
	var turbine := cylinder(root,.23,1.15,Vector3(-.2,.41,-.46),METAL,12)
	turbine.rotation.z = PI*.5
	for x in [-.64,.38]:
		cylinder(root,.1,1.45,Vector3(x,.84,-.46),CREAM,10)
		cylinder(root,.11,.14,Vector3(x,1.43,-.46),ORANGE,10)
	beam(root,Vector3(-.64,.4,-.4),Vector3(-.64,.4,.3),.06,TEAL)
	for x in [-.5,-.15,.2]:
		box(root,Vector3(.2,.25,.025),Vector3(x,.5,.69),BLUE)

static func _community_battery(root: Node3D) -> void:
	for x in [-.43,.22]:
		box(root,Vector3(.51,.84,.6),Vector3(x,.53,0),WHITE)
		box(root,Vector3(.53,.08,.64),Vector3(x,.99,0),TEAL)
		box(root,Vector3(.36,.45,.025),Vector3(x,.57,.32),MINT)
		for y in [.4,.55,.7]:
			box(root,Vector3(.25,.018,.035),Vector3(x,y,.35),TEAL)
	box(root,Vector3(.3,.3,.32),Vector3(.58,.29,.45),ORANGE)
	beam(root,Vector3(-.43,.2,0),Vector3(.58,.2,.45),.025,METAL)

static func _thermal_storage(root: Node3D) -> void:
	for x in [-.45,.45]:
		cylinder(root,.34,1.02,Vector3(x,.63,-.2),ORANGE,16)
		cylinder(root,.35,.06,Vector3(x,1.17,-.2),WHITE,16)
		cylinder(root,.35,.06,Vector3(x,.18,-.2),METAL,16)
	box(root,Vector3(.8,.43,.45),Vector3(0,.35,.51),CREAM)
	for x in [-.45,.45]:
		beam(root,Vector3(x,.35,-.2),Vector3(x,.35,.51),.055,CORAL)
		beam(root,Vector3(x,.35,.51),Vector3(0,.35,.51),.055,CORAL)

static func _hydro(root: Node3D) -> void:
	box(root,Vector3(1.6,.08,1.55),Vector3(0,.15,0),Color("5ba7b5"))
	box(root,Vector3(1.65,.9,.32),Vector3(0,.63,-.12),CONCRETE)
	box(root,Vector3(1.7,.1,.43),Vector3(0,1.1,-.12),CREAM)
	for x in [-.55,0,.55]:
		box(root,Vector3(.16,.67,.47),Vector3(x,.55,-.12),METAL)
		box(root,Vector3(.21,.09,.69),Vector3(x,.26,.32),WHITE)
	box(root,Vector3(.55,.5,.48),Vector3(-.45,.42,.55),TEAL)

static func _nuclear(root: Node3D) -> void:
	box(root,Vector3(.95,.76,1.2),Vector3(-.3,.5,0),CREAM)
	cylinder(root,.46,.65,Vector3(.26,.47,-.1),WHITE,20)
	var dome := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = .46
	mesh.height = .92
	dome.mesh = mesh
	dome.material_override = material(WHITE)
	dome.position = Vector3(.26,.79,-.1)
	root.add_child(dome)
	box(root,Vector3(.53,.13,.7),Vector3(-.42,.96,0),TEAL)
	for z in [-.43,.06,.5]:
		cylinder(root,.065,.24,Vector3(.64,.23,z),ORANGE,8)
	box(root,Vector3(.85,.05,.14),Vector3(.1,.18,.69),METAL)

static func _cooling(root: Node3D) -> void:
	for x in [-.43,.43]:
		cylinder(root,.34,.65,Vector3(x,.45,0),CREAM,16,.23)
		cylinder(root,.23,.49,Vector3(x,1.02,0),WHITE,16,.34)
		cylinder(root,.29,.035,Vector3(x,1.28,0),DARK,16)
	box(root,Vector3(1.5,.08,.35),Vector3(0,.18,.56),Color("5ba7b5"))
	for x in [-.43,.43]:
		beam(root,Vector3(x,.25,.08),Vector3(x,.25,.66),.065,TEAL)

static func _academy(root: Node3D) -> void:
	box(root,Vector3(1.35,.8,1.15),Vector3(0,.52,0),CREAM)
	box(root,Vector3(1.45,.13,1.25),Vector3(0,.98,0),TEAL)
	for x in [-.45,0,.45]:
		for y in [.42,.72]:
			box(root,Vector3(.24,.18,.03),Vector3(x,y,.59),BLUE)
	box(root,Vector3(.28,.4,.05),Vector3(0,.34,.65),ORANGE)
	box(root,Vector3(.7,.06,.26),Vector3(0,.18,.71),WHITE)
	cylinder(root,.02,.8,Vector3(.64,1.42,-.44),METAL,6)
	box(root,Vector3(.35,.18,.025),Vector3(.47,1.68,-.44),ORANGE)

static func _pumped_storage(root: Node3D) -> void:
	box(root,Vector3(1.45,.6,.65),Vector3(0,.42,-.43),CONCRETE)
	box(root,Vector3(1.27,.04,.5),Vector3(0,.75,-.43),Color("5ba7b5"))
	box(root,Vector3(1.4,.12,.57),Vector3(0,.18,.45),CREAM)
	box(root,Vector3(1.24,.025,.42),Vector3(0,.26,.45),BLUE)
	for x in [-.43,.43]:
		beam(root,Vector3(x,.68,-.2),Vector3(x,.27,.47),.085,TEAL)
	box(root,Vector3(.38,.37,.4),Vector3(0,.4,.12),WHITE)

static func _flow_battery(root: Node3D) -> void:
	for x in [-.46,.46]:
		cylinder(root,.31,.95,Vector3(x,.6,-.18),WHITE,12)
		cylinder(root,.315,.12,Vector3(x,.65,-.18),MINT,12)
		cylinder(root,.315,.06,Vector3(x,1.1,-.18),TEAL,12)
	box(root,Vector3(.65,.52,.45),Vector3(0,.39,.5),TEAL)
	for x in [-.46,.46]:
		beam(root,Vector3(x,.32,-.1),Vector3(x,.32,.5),.05,ORANGE)
		beam(root,Vector3(x,.32,.5),Vector3(0,.32,.5),.05,ORANGE)

static func _hydrogen(root: Node3D) -> void:
	for x in [-.5,0,.5]:
		cylinder(root,.18,.92,Vector3(x,.58,-.3),MINT,12)
		cylinder(root,.065,.13,Vector3(x,1.1,-.3),TEAL,8)
		beam(root,Vector3(x,.2,-.3),Vector3(x,.2,.5),.035,METAL)
	box(root,Vector3(1.4,.5,.5),Vector3(0,.37,.42),WHITE)
	for x in [-.47,0,.47]:
		box(root,Vector3(.28,.27,.03),Vector3(x,.4,.69),TEAL)
	box(root,Vector3(.45,.08,.55),Vector3(.46,.68,.4),ORANGE)

static func _hvdc(root: Node3D) -> void:
	box(root,Vector3(.9,.75,1.2),Vector3(-.36,.5,0),WHITE)
	box(root,Vector3(.97,.09,1.28),Vector3(-.36,.94,0),BLUE)
	for z in [-.48,0,.48]:
		for y in [.35,.61,.87,1.13]:
			cylinder(root,.09,.12,Vector3(.48,y,z),CREAM,8)
		beam(root,Vector3(.48,.2,z),Vector3(.48,1.35,z),.035,METAL)
	beam(root,Vector3(.48,1.35,-.48),Vector3(.48,1.35,.48),.05,ORANGE)
	box(root,Vector3(.08,.14,.6),Vector3(-.36,1.05,0),TEAL)

static func _condenser(root: Node3D) -> void:
	box(root,Vector3(1.3,.18,.8),Vector3(0,.22,0),DARK)
	var machine := cylinder(root,.35,1.2,Vector3(0,.65,0),TEAL,16)
	machine.rotation.z = PI*.5
	for x in [-.61,.61]:
		var end := cylinder(root,.39,.08,Vector3(x,.65,0),METAL,16)
		end.rotation.z = PI*.5
	for x in [-.45,0,.45]:
		cylinder(root,.055,.36,Vector3(x,1.16,0),CREAM,8)
	box(root,Vector3(.45,.35,.3),Vector3(.45,.35,.56),WHITE)

static func _fusion(root: Node3D) -> void:
	cylinder(root,.71,.25,Vector3(0,.26,0),DARK,20)
	var torus := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = .3
	mesh.outer_radius = .68
	mesh.rings = 20
	mesh.ring_segments = 12
	torus.mesh = mesh
	torus.material_override = material(TEAL,.5)
	torus.position.y = .68
	root.add_child(torus)
	for i in range(8):
		var theta := float(i)*TAU/8
		var ring := box(root,Vector3(.16,.7,.28),Vector3(sin(theta)*.48,.67,cos(theta)*.48),ORANGE)
		ring.rotation.y = theta
	cylinder(root,.17,1.15,Vector3(0,.75,0),METAL,12)
	box(root,Vector3(.6,.45,.35),Vector3(0,.35,.63),WHITE)

static func _home(root: Node3D) -> void:
	box(root, Vector3(1.1, 0.8, 1.05), Vector3(-0.1, 0.5, -0.08), CREAM)
	box(root, Vector3(1.16, 0.10, 1.11), Vector3(-0.1, 0.95, -0.08), WHITE)
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
		var surface = cylinder(blade, .12, 1.03, Vector3(.03,.56,0), WHITE, 8, .022)
		surface.scale.z=.28
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
	var mat: StandardMaterial3D = material(color).duplicate()
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
	var variation: float = 0.88 + (seed % 7) * 0.055
	cylinder(root, 0.085, 0.47, Vector3(0, 0.23, 0), Color("8c7760"), 6)
	var greens = [Color("4d8c73"), Color("629a78"), Color("82ab85")]
	if seed%3==0:
		for i in range(3):
			cylinder(root, (0.43 - i * 0.095) * variation, 0.66 * variation, Vector3(0, (0.65 + i * 0.36) * variation, 0), greens[(i + seed) % 3], 8, 0.025)
	else:
		for i in range(5):
			var theta:=float(i)*2.4
			var at:=Vector3(cos(theta)*.23,.83+float(i%3)*.19,sin(theta)*.23)*variation
			var leaf:=MeshInstance3D.new()
			var mesh:=SphereMesh.new()
			mesh.radius=.37*variation
			mesh.height=.65*variation
			mesh.radial_segments=7
			mesh.rings=3
			leaf.mesh=mesh
			leaf.position=at
			leaf.material_override=material(greens[(i+seed)%3])
			root.add_child(leaf)
			beam(root,Vector3(0,.32,0),at,.035,Color("8c7760"))
	root.rotation.y = seed * 1.27
	return root

static func rock(seed: int = 0) -> Node3D:
	var root = Node3D.new()
	root.name = "CoastalRock"
	var mesh = SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	mesh.radial_segments = 7
	mesh.rings = 3
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material(Color("99afa1") if seed % 2 == 0 else Color("b8c4af"))
	instance.scale = Vector3(1.1 + (seed % 3) * 0.2, 0.8 + float(seed%3)*.2, 0.9)
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
		for y in [1.1,1.15,1.2]:
			cylinder(root,.065,.025,Vector3(x,y,0),CREAM,8)
	beam(root,Vector3(0,.65,0),Vector3(-.24,1.04,0),.018,METAL)
	beam(root,Vector3(0,.65,0),Vector3(.24,1.04,0),.018,METAL)
	return root

static func vehicle() -> Node3D:
	var root = Node3D.new()
	root.name = "UtilityVan"
	box(root, Vector3(0.4, 0.28, 0.77), Vector3(0, 0.26, 0), ORANGE)
	box(root, Vector3(0.37, 0.21, 0.4), Vector3(0, 0.48, 0.1), WHITE)
	box(root, Vector3(0.30, 0.13, 0.015), Vector3(0, 0.49, 0.31), BLUE)
	box(root, Vector3(0.24, 0.04, 0.04), Vector3(0, 0.63, 0.10), ORANGE)
	for x in [-.15,.15]:
		box(root,Vector3(.025,.025,.55),Vector3(x,.625,-.1),METAL)
	for z in [-.3,-.15,0,.15]:
		box(root,Vector3(.3,.02,.02),Vector3(0,.638,z),CREAM)
	for x in [-.13,.13]:
		box(root,Vector3(.065,.06,.025),Vector3(x,.26,.395),WHITE)
	for x in [-0.21, 0.21]:
		for z in [-0.24, 0.24]:
			var wheel = cylinder(root, 0.095, 0.065, Vector3(x, 0.15, z), DARK, 10)
			wheel.rotation.z = PI * 0.5
	return root
