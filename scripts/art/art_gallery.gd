extends SceneTree

## Optional source asset contact sheet: godot --path . --script scripts/art/art_gallery.gd
const Models = preload("res://scripts/art/model_factory.gd")
const Island = preload("res://scripts/art/island_factory.gd")
var frames := 0
var island_mode := false

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	island_mode = "--island" in OS.get_cmdline_user_args()
	var stage = Node3D.new()
	root.add_child(stage)
	var env = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("d8e7dc")
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
	if island_mode:
		stage.add_child(Island.create())
	else:
		Models.box(stage, Vector3(50, 0.2, 50), Vector3(0, -0.24, 0), Color("c3d4bc"))
	var kinds = ["home", "hospital", "factory", "gas", "substation", "battery", "solar", "wind", "sensor"]
	if island_mode: kinds.clear()
	for i in range(kinds.size()):
		var at = Vector3((i % 3 - 1) * 3.0, 0, (i / 3 - 1) * 3.0)
		var model = Models.building(kinds[i])
		stage.add_child(model)
		model.position = at
		var label = Label3D.new()
		label.text = kinds[i].to_upper()
		label.position = at + Vector3(0, 0.02, 1.15)
		label.rotation_degrees.x = -90
		label.font_size = 32
		label.pixel_size = 0.006
		label.modulate = Color("375d5c")
		label.outline_size = 0
		stage.add_child(label)
	var camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 51.0 if island_mode else 14.3
	camera.current = true
	stage.add_child(camera)
	camera.position = Vector3(40, 40, 40) if island_mode else Vector3(13, 14, 17)
	camera.look_at(Vector3(0, 0.2, 0))
	root.size = Vector2i(1600, 1000)
	root.transparent_bg = false

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 20:
		var image = root.get_texture().get_image()
		var result = image.save_png("res://assets/models/island_catalogue.png" if island_mode else "res://assets/models/art_catalogue.png")
		print("ART_PREVIEW_CAPTURE: ", result)
		quit()
	return false
