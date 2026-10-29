extends SceneTree
## Full-scene operator workflow matrix; all output stays in the ignored QA folder.
var game: Node
var destination := ""
var captures := 0
var failures := 0
var geometry: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func settle() -> void:
	for frame in range(7): await process_frame

func capture(caption: String) -> void:
	game.notice_label.hide()
	game.tooltip_label.hide()
	await settle()
	await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	var result: Error = rendered.save_png(destination.path_join(caption+".png"))
	if result != OK:
		failures += 1
		push_error("Could not save "+caption)
	var row: Dictionary = {"layout":destination.get_file(),"state":caption,"viewport":str(root.size),"ui_size":str(game.root_ui.size)}
	for pair in [["dock",game.hud.dock_panel],["rail",game.hud.status_panel],["workspace",game.hud.inspector],["tray",game.hud.tray]]:
		var control: Control = pair[1]
		if control.is_visible_in_tree(): row[str(pair[0])] = str(control.get_global_rect())
	geometry.append(row)
	captures += 1

func clean() -> void:
	for panel in [game.welcome,game.help_modal,game.end_modal,game.confirmation,game.settings_panel,game.market_panel,game.digital_panel,game.planning_panel,game.campaign_panel]:
		panel.hide()
	game.hud.close_popups()
	game.hud.close_tray()
	game.hud.operator_dock.close()
	game.selected_id = -1
	game.selected_line = -1
	game.selected_comm_line = -1
	game._set_tool("select")
	game._update_inspector()
	game._update_hud()

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game.onboarding = false
	game.onboarding_skipped = true
	game.speed = 0
	game.hud.onboarding_panel.hide()
	game.preferences.storage_path = "res://.godot/operator-workflow-qa/preferences.cfg"
	var layouts := [
		[Vector2i(1280,720),1.0], [Vector2i(1280,720),1.25],
		[Vector2i(1280,720),1.5], [Vector2i(1440,900),1.0]
	]
	for layout in layouts:
		var resolution: Vector2i = layout[0]
		var ratio: float = layout[1]
		DisplayServer.window_set_size(resolution)
		root.size = resolution
		game.preferences.ui_scale = ratio
		game.preferences.high_contrast = false
		game._apply_preferences()
		destination = "res://.godot/operator-workflow-qa/%dx%d_%d" % [resolution.x,resolution.y,int(ratio*100)]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
		game.sim.reset(42)
		game._rebuild_session(true)
		game.speed = 0
		clean()
		game._focus_working_area()
		game._update_hud()
		for index in range(25):
			game.sim.step(0.1)
			game.chart.sample(float(game.sim.totals.demand),float(game.sim.totals.generation)+float(game.sim.totals.get("import_mw",0)),float(game.sim.elapsed_hours),float(game.sim.totals.served))
		game._sync_world(true)
		game._update_hud()
		game.hud.operator_dock.close()
		game._hud_action("clear_selection")
		await capture("hud")
		game.hud.toggle_popup("stats")
		await capture("statistics")
		clean()
		game.hud.operator_dock.show_page("diagnosis")
		await capture("diagnosis")
		clean()
		game.hud.operator_dock.open_search()
		game.hud.operator_dock.search.text=""
		game.hud.operator_dock.refresh()
		await capture("search")
		clean()
		game.sim.set_dispatch(1,0.75,"field")
		game.hud.operator_dock.show_page("jobs")
		await capture("queue")
		clean()
		game.hud.toggle_category("power")
		game.hud.build_buttons.solar.pressed.emit()
		await capture("construction")
		clean()
		game.focus_target("building",1)
		await capture("inspector")
		clean()
		game.market_panel.open()
		game.market_panel.tabs.current_tab=0
		await capture("market")
		clean()
		game.digital_panel.open()
		game.digital_panel.tabs.current_tab=0
		await capture("digital")
		clean()
		game.planning_panel.open()
		game.planning_panel.tabs.current_tab=0
		await capture("technology")
		game.planning_panel.tabs.current_tab=1
		game.planning_panel.facility_modes.current_tab=1
		for kind in ["battery","pumped_storage","hydrogen"]:
			if not game.planning_panel.comparison_kinds.has(kind): game.planning_panel._toggle_comparison(kind)
		await capture("facility_comparison")
		clean()
		game.help_modal.show()
		await capture("help")
		clean()
		game._request_demolition(1)
		await capture("demolition_confirm")
		clean()
		game.settings_panel.open()
		await capture("settings")
		clean()
		game.preferences.high_contrast=true
		game._apply_preferences()
		game.sim.time_hours=22.0
		game.sim.trigger_storm()
		game.sim._update_weather()
		game._sync_world(true)
		game._update_hud()
		await capture("night_storm_contrast")
		game.preferences.high_contrast=false
		game._apply_preferences()
		game.sim.start_campaign(5)
		game._rebuild_session(true)
		game.speed=0
		clean()
		game.zoom=130
		game.cam_target=game._cell_position(Vector2i(23,23))
		game._update_camera()
		await capture("chapter05_far")
	var report := FileAccess.open("res://.godot/operator-workflow-qa/geometry.json",FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify(geometry,"\t"))
	game.queue_free()
	await settle()
	print("OPERATOR WORKFLOW MATRIX: %d captures, %d save failures" % [captures,failures])
	quit(1 if failures>0 else 0)
