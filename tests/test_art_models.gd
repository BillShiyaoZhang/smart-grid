extends SceneTree
## Source geometry, editable scene and landscape contracts, without GPU rendering.
const Models = preload("res://scripts/art/model_factory.gd")
const Island = preload("res://scripts/art/island_factory.gd")
const Sim = preload("res://scripts/sim/grid_sim.gd")
const Maps = preload("res://scripts/sim/scenario_map.gd")
var checks:=0
var failures:=0

func check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+message)

func _initialize() -> void:
	var sim:=Sim.new()
	sim.reset(42)
	check(Models.KINDS.size()==29,"all 29 gameplay facility kinds share one art manifest")
	var signatures: Dictionary={}
	for kind in Models.KINDS:
		check(sim.catalog.has(kind),"art manifest matches the actual catalog: "+kind)
		var model: Node3D=Models.building(kind)
		var bounds: AABB=model.get_meta("bounds",AABB())
		check(model.position==Vector3.ZERO and model.scale==Vector3.ONE,"model root preserves cell transform: "+kind)
		check(bounds.size.x>0 and bounds.size.y>0 and bounds.size.z>0,"rendered geometry has nonempty local bounds: "+kind)
		check(bounds.position.y>=-.001,"model rests above the unchanged ground plane: "+kind)
		check(float(model.get_meta("pick_height",0))>=bounds.end.y,"hit target reaches the actual silhouette: "+kind)
		check(model.get_meta("label_anchor",Vector3.ZERO).y>bounds.end.y,"status label clears the roof: "+kind)
		check(not model.has_node("Status") and not model.has_node("EveningLight"),"source does not shadow runtime status nodes: "+kind)
		check(int(model.get_meta("asset_revision",0))==2,"refreshed asset version is explicit: "+kind)
		check(int(model.get_meta("static_material_count",100))<25,"detailed geometry is batched by shared paint: "+kind)
		var signature:=_geometry_signature(model)
		check(not signatures.has(signature),"facility geometry is distinct: "+kind)
		signatures[signature]=kind
		if kind=="wind":
			var rotor:=model.find_child("Rotor",true,false) as Node3D
			check(rotor!=null and rotor.get_child_count()==4,"wind preserves its independent animated three-blade rotor")
		var path: String="res://assets/models/"+kind+".tscn"
		check(ResourceLoader.exists(path),"editable scene exists for every catalog kind: "+kind)
		if ResourceLoader.exists(path):
			var packed:=load(path) as PackedScene
			var instance:=packed.instantiate() as Node3D
			check(instance.get_meta("asset_kind","")==kind and instance.get_meta("bounds",AABB())==bounds,"scene metadata matches the live factory: "+kind)
			instance.free()
		var icon: Image=Image.load_from_file(ProjectSettings.globalize_path("res://assets/icons/"+kind+".png"))
		check(icon!=null and icon.get_width()==256 and icon.get_height()==256,"full-size icon is rendered for "+kind)
		if icon!=null:
			var used:=icon.get_used_rect()
			check(icon.detect_alpha()!=Image.ALPHA_NONE and used.position.x>3 and used.position.y>3 and used.end.x<253 and used.end.y<253,"transparent icon has safe uncropped margins: "+kind)
		model.free()
	for chapter in range(1,16):
		var spec: Dictionary=Maps.for_chapter(chapter)
		var landscape: Node3D=Island.create_for_map(spec)
		check(landscape.get_meta("map_id")==spec.id and landscape.get_meta("playable_size")==spec.size,"refreshed landscape retains chapter identity and extent")
		check(landscape.has_node("RiverTerrain") and landscape.has_node("HillTerrain"),"real river and hill siting cells remain visible")
		check(landscape.has_node("ModernRoadMarkings")==bool(spec.modern) and landscape.has_node("UtilityVan")==bool(spec.modern),"period scenery respects chapter date")
		check(landscape.has_node("CraftedCoast"),"every landscape family receives the refreshed coastline")
		var sea:=landscape.get_node("WaterSurround") as MeshInstance3D
		check(sea.material_override is ShaderMaterial and sea.material_override.get_shader_parameter("island_half")==float(spec.size),"water keeps its runtime day/night and reduced-motion shader")
		landscape.free()
		var preview:=Image.load_from_file(ProjectSettings.globalize_path("res://assets/art/chapters/%02d.png" % chapter))
		check(preview!=null and preview.get_width()==640 and preview.get_height()==360,"chapter card has a real 16:9 scenario render")
	var sandbox: Node3D=Island.create()
	check(sandbox.has_node("Sea") and sandbox.has_node("UtilityVan") and sandbox.get_meta("playable_size")==16,"sandbox keeps water and transport contracts")
	sandbox.free()
	print("ART MODELS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _geometry_signature(node: Node3D) -> String:
	var result:=str(node.transform)
	if node is MeshInstance3D:
		result+=str(node.get_aabb())
	for child in node.get_children():
		if child is Node3D: result+=_geometry_signature(child)
	return result.sha256_text()
