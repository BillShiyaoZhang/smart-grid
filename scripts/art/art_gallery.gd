extends SceneTree
## GPU contact sheet of all 29 factory-rendered icons. Run render_icons.gd first.
## --island renders the refreshed playable landscape instead.
const Models = preload("res://scripts/art/model_factory.gd")
const Island = preload("res://scripts/art/island_factory.gd")
const Sim = preload("res://scripts/sim/grid_sim.gd")
var island_mode:=false
var frames:=0

func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Contact sheet requires GPU rendering.")
		quit(1)
		return
	island_mode="--island" in OS.get_cmdline_user_args()
	root.size=Vector2i(1920,1200) if island_mode else Vector2i(2400,1680)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	if island_mode:
		_build_island()
		return
	var background:=ColorRect.new()
	background.color=Color("102c35")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var title:=Label.new()
	title.position=Vector2(72,32)
	title.text="潮汐电网  ·  微缩设施图鉴"
	title.add_theme_font_override("font",load("res://assets/fonts/NotoSansCJKsc-Regular.otf"))
	title.add_theme_font_size_override("font_size",42)
	title.add_theme_color_override("font_color",Models.WHITE)
	root.add_child(title)
	var sim:=Sim.new()
	sim.reset(42)
	for i in range(Models.KINDS.size()):
		var kind: String=Models.KINDS[i]
		var origin:=Vector2(54+float(i%6)*382,112+float(i/6)*307)
		var card:=Panel.new()
		card.position=origin
		card.size=Vector2(366,291)
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("173741")
		style.border_color=Color("3b5a5d")
		style.set_border_width_all(1)
		style.set_corner_radius_all(14)
		card.add_theme_stylebox_override("panel",style)
		root.add_child(card)
		var texture:=TextureRect.new()
		texture.position=Vector2(63,0)
		texture.size=Vector2(240,240)
		texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture.texture=ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path("res://assets/icons/"+kind+".png")))
		card.add_child(texture)
		var label:=Label.new()
		label.position=Vector2(12,244)
		label.size=Vector2(342,36)
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.text=str(sim.catalog[kind].name)
		label.add_theme_font_override("font",title.get_theme_font("font"))
		label.add_theme_font_size_override("font_size",23)
		label.add_theme_color_override("font_color",Models.WHITE)
		card.add_child(label)

func _build_island() -> void:
	var stage:=Node3D.new()
	root.add_child(stage)
	stage.add_child(Island.create())
	for placement in [["home",Vector3(2,0,2)],["substation",Vector3(-2,0,0)],["solar",Vector3(3,0,-3)],["wind",Vector3(-5,0,-4)],["battery",Vector3(-4,0,3)],["gas",Vector3(3,0,5)]]:
		var model: Node3D=Models.building(placement[0])
		model.position=placement[1]
		stage.add_child(model)
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("204954")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("d9e2cf")
	env.environment.ambient_light_energy=.32
	stage.add_child(env)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-35,0)
	sun.light_color=Color("fff0d3")
	sun.light_energy=.62
	sun.shadow_enabled=true
	stage.add_child(sun)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=45
	camera.position=Vector3(35,33,42)
	stage.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current=true

func _process(_delta: float) -> bool:
	frames+=1
	if frames==20:
		var path: String="res://assets/models/"+("island_catalogue.png" if island_mode else "art_catalogue.png")
		var result: Error=root.get_texture().get_image().save_png(path)
		print("ART_PREVIEW_CAPTURE: ",result," ",path)
		quit(int(result))
	return false
