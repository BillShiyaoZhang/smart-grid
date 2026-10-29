extends SceneTree
## Diagnostic only: uncapped GPU samples and cold/cached factory construction.
## Launch with APPDATA isolated to .godot/art-qa/perf-user.
const Models=preload("res://scripts/art/model_factory.gd")
var game: Node
var report: Dictionary={"models":{},"scenarios":[]}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Presentation performance needs the GL Compatibility renderer.")
		quit(1)
		return
	AudioServer.set_bus_mute(0,true)
	var clock_start:=Time.get_ticks_usec()
	var maximum_groups:=0
	for kind in Models.KINDS:
		var model: Node3D=Models.building(kind)
		maximum_groups=maxi(maximum_groups,int(model.get_meta("static_material_count",0)))
		model.free()
	report.models.cold_29_ms=float(Time.get_ticks_usec()-clock_start)/1000.0
	clock_start=Time.get_ticks_usec()
	for i in range(290):
		var model: Node3D=Models.building(Models.KINDS[i%Models.KINDS.size()])
		model.free()
	report.models.cached_290_ms=float(Time.get_ticks_usec()-clock_start)/1000.0
	report.models.max_static_material_groups=maximum_groups
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in range(6): await process_frame
	game.preferences.storage_path="res://.godot/art-qa/perf-preferences.cfg"
	game.preferences.max_fps=0
	game.preferences.vsync=false
	game.preferences.master_volume=0.0
	game.preferences.pause_unfocused=false
	game._apply_preferences()
	game._begin_free_sandbox(true)
	game.speed=0
	game._focus_working_area()
	await _sample("sandbox_working_area")
	game.sim.expand_region()
	game._rebuild_session(true)
	game.speed=0
	game._focus_working_area()
	await _sample("region_working_area")
	game.cam_target=Vector3(32,0,32)
	game.zoom=130
	game._update_camera()
	await _sample("region_full_map")
	var directory:=ProjectSettings.globalize_path("res://.godot/art-qa")
	DirAccess.make_dir_recursive_absolute(directory)
	var output:=FileAccess.open(directory.path_join("presentation-performance.json"),FileAccess.WRITE)
	if output==null:
		quit(1)
		return
	output.store_string(JSON.stringify(report,"\t"))
	print("PRESENTATION PERFORMANCE: ",JSON.stringify(report))
	game.queue_free()
	for i in range(3): await process_frame
	quit()

func _sample(caption: String) -> void:
	for i in range(30): await process_frame
	var times: Array[float]=[]
	var calls:=0.0
	var objects:=0.0
	var primitives:=0.0
	var previous:=Time.get_ticks_usec()
	for i in range(90):
		await process_frame
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec()
		times.append(float(now-previous)/1000.0)
		previous=now
		calls+=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objects+=Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		primitives+=Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var sum:=0.0
	for value in times: sum+=value
	times.sort()
	report.scenarios.append({"name":caption,"map_size":game.sim.map_size(),"facility_count":game.sim.buildings.size(),"frame_mean_ms":sum/float(times.size()),"frame_p95_ms":times[int(times.size()*.95)],"draw_calls":calls/90.0,"rendered_objects":objects/90.0,"primitives":primitives/90.0})
