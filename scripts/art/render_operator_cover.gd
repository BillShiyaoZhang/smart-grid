extends SceneTree
## Reproducible key art built from the same miniature models as the live game.
const Models = preload("res://scripts/art/model_factory.gd")
const Island = preload("res://scripts/art/island_factory.gd")
var frames := 0

func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	root.size = Vector2i(1600,700)
	var stage := Node3D.new()
	root.add_child(stage)
	stage.add_child(Island.create())
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("72b8ba")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("dceee5")
	env.environment.ambient_light_energy = 0.25
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-35,0)
	sun.light_color = Color("fff1d1")
	sun.light_energy = 0.45
	sun.shadow_enabled = true
	stage.add_child(sun)
	var placements := [
		["substation",Vector3(0,0,0)], ["gas",Vector3(-5,0,-4)],
		["solar",Vector3(3,0,-7)], ["solar",Vector3(6,0,-7)],
		["wind",Vector3(-8,0,-6)], ["wind",Vector3(-8,0,1)],
		["battery",Vector3(-4,0,3)], ["control",Vector3(0,0,-4)],
		["home",Vector3(4,0,1)], ["home",Vector3(7,0,1)],
		["home",Vector3(4,0,4)], ["home",Vector3(7,0,4)],
		["hospital",Vector3(1,0,5)], ["factory",Vector3(7,0,-3)],
		["intertie",Vector3(-5,0,7)], ["sensor",Vector3(0,0,2)]
	]
	for placement in placements:
		var model: Node3D = Models.building(str(placement[0]))
		model.position = placement[1]
		stage.add_child(model)
		if placement[0] != "substation":
			var start: Vector3 = placement[1]+Vector3.UP*0.4
			Models.beam(stage,start,Vector3(0,0.4,0),0.025,Color("327c7c"))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 28
	camera.current = true
	stage.add_child(camera)
	camera.position = Vector3(32,30,39)
	camera.look_at(Vector3(0,0,0))

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 24:
		var rendered: Image = root.get_texture().get_image()
		var result: Error = rendered.save_png("res://assets/art/operator_cover.png")
		print("OPERATOR_COVER: ",result)
		quit(int(result))
	return false
