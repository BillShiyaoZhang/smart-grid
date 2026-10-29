extends SceneTree
## Real-scene design review; outputs and user data stay outside player saves.
var game: Node
var captures := 0
var failures := 0
var destination := ""

func _initialize() -> void:
	_run.call_deferred()

func settle() -> void:
	for frame in range(6): await process_frame

func capture(caption: String) -> void:
	game.notice_label.hide()
	game.tooltip_label.hide()
	await settle()
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(destination.path_join(caption+".png")) != OK:
		failures += 1
	captures += 1

func clean() -> void:
	for panel in [game.welcome,game.help_modal,game.end_modal,game.confirmation,game.settings_panel,game.market_panel,game.digital_panel,game.planning_panel,game.campaign_panel]: panel.hide()
	game.hud.close_popups()
	game.hud.close_tray()
	game.hud.operator_dock.close()
	game.selected_id=-1
	game.selected_line=-1
	game.selected_comm_line=-1
	game._set_tool("select")
	game._update_inspector()
	game._update_hud()

func _run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game.speed=0
	game.onboarding=false
	game.onboarding_skipped=true
	for layout in [[Vector2i(1440,900),1.0],[Vector2i(1920,1080),1.0],[Vector2i(1280,720),1.5]]:
		DisplayServer.window_set_size(layout[0])
		root.size=layout[0]
		game.preferences.ui_scale=layout[1]
		game.preferences.high_contrast=false
		game._apply_preferences()
		destination="res://.godot/redesign-qa/%dx%d_%d" % [layout[0].x,layout[0].y,int(float(layout[1])*100)]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
		game.sim.reset(42)
		game._rebuild_session(true)
		game.speed=0
		game.sim.next_storm_at=100.0
		game.sim.digital.next_attack_at=100.0
		clean()
		game._focus_working_area()
		game._sync_world(true)
		game._update_hud()
		await capture("overview")
		game.hud.operator_dock.show_page("diagnosis")
		await capture("diagnosis")
		clean()
		game.sim.connect_buildings(2,6)
		game.sim.research()
		game.sim.research()
		game.sim.step(0.1)
		game._sync_world(true)
		game._update_hud()
		game.focus_target("building",9)
		await capture("storage_object")
		clean()
		game.planning_panel.open()
		game.planning_panel.tabs.current_tab=1
		game.planning_panel.facility_modes.current_tab=1
		for kind in ["battery","pumped_storage","hydrogen"]:
			if kind not in game.planning_panel.comparison_kinds: game.planning_panel._toggle_comparison(kind)
		await capture("storage_comparison")
		game.planning_panel.tabs.current_tab=0
		await capture("development")
		clean()
		game.digital_panel.open()
		await capture("digital_readiness")
		clean()
		game.advance_management(1.0)
		game.market_panel.open()
		game.market_panel.tabs.current_tab=3
		await capture("ledger")
		clean()
		game.sim.time_hours=22.0
		game.sim.trigger_storm()
		var damaged := -1
		for line in game.sim.lines:
			if line.fault:
				damaged=int(line.id)
				break
		if damaged>=0:
			game.sim.patrol_line(damaged)
			game.sim.step(0.5)
			game.sim.repair_line(damaged)
		game._sync_world(true)
		game._update_hud()
		game.hud.operator_dock.show_page("jobs")
		game._focus_working_area()
		await capture("storm_response")
		clean()
		game.preferences.high_contrast=true
		game.preferences.reduced_motion=true
		game._apply_preferences()
		await capture("storm_accessible")
		game.preferences.reduced_motion=false
		game.preferences.high_contrast=false
		game._apply_preferences()
		game.sim.reset(42)
		game._rebuild_session(true)
		game.speed=0
		clean()
		game.sim.explore_region()
		game.planning_panel.open()
		game.planning_panel.tabs.current_tab=2
		await capture("regional_markets")
		clean()
		game.sim.start_management_game(42)
		game._rebuild_session(true)
		game.speed=0
		clean()
		game._focus_working_area()
		game.hud.toggle_popup("missions")
		await capture("management_goals")
		game.hud.close_popups()
		game._update_hud()
		await capture("management_overview")
	game.queue_free()
	await settle()
	print("REDESIGN RENDER: %d captures, %d failures" % [captures,failures])
	quit(1 if failures else 0)
