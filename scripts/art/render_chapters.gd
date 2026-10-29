extends SceneTree
## Chapter cards show real scenario terrain and facilities, never illustrative placeholders.
const Models=preload("res://scripts/art/model_factory.gd")
const Island=preload("res://scripts/art/island_factory.gd")
const Sim=preload("res://scripts/sim/grid_sim.gd")
var sim: RefCounted
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var chapter:=1
var frames:=0
var started:=false

func _initialize() -> void:
	_build.call_deferred()

func _build() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Chapter previews require GPU rendering.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/art/chapters"))
	viewport=SubViewport.new()
	viewport.size=Vector2i(640,360)
	viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_4X
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	sim=Sim.new()
	_show_chapter()
	started=true

func _show_chapter() -> void:
	if is_instance_valid(stage): stage.free()
	stage=Node3D.new()
	viewport.add_child(stage)
	sim.start_campaign(chapter)
	var terrain: Node3D=Island.create_for_map(sim.map_spec())
	if sim.map_size()>16: terrain.position=Vector3(32,0,32)
	stage.add_child(terrain)
	var minimum:=Vector3(1000,0,1000)
	var maximum:=Vector3(-1000,0,-1000)
	for building in sim.buildings:
		var model: Node3D=Models.building(str(building.kind))
		model.position=Vector3((building.cell.x-7.5)*2,0,(building.cell.y-7.5)*2)
		stage.add_child(model)
		minimum.x=minf(minimum.x,model.position.x)
		minimum.z=minf(minimum.z,model.position.z)
		maximum.x=maxf(maximum.x,model.position.x)
		maximum.z=maxf(maximum.z,model.position.z)
	for line in sim.lines:
		var a: Dictionary=sim.get_building(int(line.a))
		var b: Dictionary=sim.get_building(int(line.b))
		if a.is_empty() or b.is_empty(): continue
		var start:=Vector3((a.cell.x-7.5)*2,.36,(a.cell.y-7.5)*2)
		var finish:=Vector3((b.cell.x-7.5)*2,.36,(b.cell.y-7.5)*2)
		Models.beam(stage,start,finish,.028,Models.TEAL)
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("224c57")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("d9e2cf")
	env.environment.ambient_light_energy=.32
	stage.add_child(env)
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-48,-35,0)
	sun.light_color=Color("fff0d3")
	sun.light_energy=.62
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=160
	stage.add_child(sun)
	camera=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.current=true
	stage.add_child(camera)
	var center: Vector3=(minimum+maximum)*.5
	var source: Dictionary=sim.get_building(int(sim.campaign.roles.get("source",-1)))
	if not source.is_empty():
		var hero:=Vector3((source.cell.x-7.5)*2,0,(source.cell.y-7.5)*2)
		center=center.lerp(hero,.35)
	center.y=.4
	var span: float=maxf(maximum.x-minimum.x,maximum.z-minimum.z)
	camera.size=clampf(span*.52+5,10,44)
	camera.position=center+Vector3(28,31,36)
	camera.look_at(center)
	frames=0

func _process(_delta: float) -> bool:
	if not started: return false
	frames+=1
	if frames<10: return false
	var result: Error=viewport.get_texture().get_image().save_png("res://assets/art/chapters/%02d.png" % chapter)
	if result!=OK:
		quit(int(result))
		return false
	print("CHAPTER_ART_OK: ",chapter)
	chapter+=1
	if chapter>15: quit()
	else: _show_chapter()
	return false
