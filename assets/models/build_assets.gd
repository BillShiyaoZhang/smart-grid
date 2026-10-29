extends SceneTree

## Rebuild the editable .tscn asset library from the original mesh recipes.
const Models = preload("res://scripts/art/model_factory.gd")
const Island = preload("res://scripts/art/island_factory.gd")

func _initialize() -> void:
	var kinds = ["gas", "solar", "wind", "battery", "substation", "home", "factory", "hospital", "sensor", "intertie", "control", "relay", "soc"]
	var args = OS.get_cmdline_user_args()
	var filter_at = args.find("--kind")
	if filter_at >= 0 and filter_at + 1 < args.size():
		var kind = args[filter_at + 1]
		assert(kind in kinds, "Unknown asset kind")
		_save(Models.building(kind), "res://assets/models/" + kind + ".tscn")
		print("ART_ASSET_OK: ", kind)
		quit()
		return
	for kind in kinds:
		_save(Models.building(kind), "res://assets/models/" + kind + ".tscn")
	_save(Models.tree(), "res://assets/models/pine.tscn")
	_save(Models.rock(), "res://assets/models/rock.tscn")
	_save(Models.pylon(), "res://assets/models/pylon.tscn")
	_save(Models.vehicle(), "res://assets/models/utility_van.tscn")
	_save(Island.create(), "res://assets/models/bay_island.tscn")
	print("ART_ASSETS_OK: 13 buildings, 4 props, island saved")
	quit()

func _save(node: Node3D, path: String) -> void:
	_own(node, node)
	var scene = PackedScene.new()
	var result = scene.pack(node)
	assert(result == OK, "Could not pack " + path)
	assert(ResourceSaver.save(scene, path) == OK, "Could not save " + path)
	node.free()

func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
