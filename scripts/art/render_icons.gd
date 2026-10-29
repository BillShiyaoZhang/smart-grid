extends SceneTree

## Render the source models with Godot into transparent toolbar illustrations.
## godot --path . --script scripts/art/render_icons.gd
const Models = preload("res://scripts/art/model_factory.gd")
const KINDS = ["gas", "solar", "wind", "battery", "substation", "home", "factory", "hospital", "sensor", "intertie", "control", "relay", "soc", "dc_dynamo", "steam", "coal", "hydro", "cooling", "academy", "nuclear", "pumped_storage", "condenser", "hvdc", "ccgt", "flow_battery", "community_battery", "hydrogen", "thermal_storage", "fusion"]
var kinds: Array = KINDS.duplicate()
var viewport: SubViewport
var stage: Node3D
var current_model: Node3D
var current_index := 0
var settle_frames := 0
var started := false

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var args = OS.get_cmdline_user_args()
	var filter_at = args.find("--kind")
	if filter_at >= 0 and filter_at + 1 < args.size():
		var kind = args[filter_at + 1]
		assert(kind in KINDS, "Unknown icon kind")
		kinds = [kind]
	viewport = SubViewport.new()
	viewport.size = Vector2i(192, 192)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("e8f0e1")
	env.environment.ambient_light_energy = 0.25
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	stage.add_child(env)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color("fff1d1")
	sun.light_energy = 0.45
	sun.shadow_enabled = true
	stage.add_child(sun)
	var camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.3
	camera.current = true
	stage.add_child(camera)
	camera.position = Vector3(7, 7.2, 9)
	camera.look_at(Vector3(0, 1, 0))
	_show_model()
	started = true

func _show_model() -> void:
	if is_instance_valid(current_model):
		current_model.free()
	current_model = Models.building(kinds[current_index])
	stage.add_child(current_model)
	settle_frames = 0

func _process(_delta: float) -> bool:
	if not started: return false
	settle_frames += 1
	if settle_frames < 8: return false
	var image = viewport.get_texture().get_image()
	var path = "res://assets/icons/" + kinds[current_index] + ".png"
	assert(image.save_png(path) == OK, "Could not write " + path)
	print("ICON_OK ", path, " alpha=", image.get_format() == Image.FORMAT_RGBA8)
	current_index += 1
	if current_index == kinds.size():
		quit()
	else:
		_show_model()
	return false
