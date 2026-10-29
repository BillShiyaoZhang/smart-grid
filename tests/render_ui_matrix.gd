extends SceneTree
## Capture the complete UI at supported window sizes, outside imported assets.
var game: Node
var destination := ""
var captures := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func capture(title: String) -> void:
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var result := img.save_png(destination.path_join(title+".png"))
	if result != OK:
		failures += 1
		push_error("Could not save "+title+": "+str(result))
	captures += 1

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.welcome.hide()
	game.speed = 0
	game.sim.connect_buildings(2,6)
	game._sync_world(true)
	game._update_hud()
	for resolution in [Vector2i(1280,720),Vector2i(1440,900),Vector2i(1600,1000),Vector2i(1920,1080)]:
		DisplayServer.window_set_size(resolution)
		root.size = resolution
		destination = "res://.godot/ui-qa/%dx%d" % [resolution.x,resolution.y]
		DirAccess.make_dir_recursive_absolute(destination)
		game.selected_id = -1
		game.selected_line = -1
		game.selected_comm_line = -1
		game._set_tool("select")
		game.hud.operator_dock.close()
		game.hud.close_popups()
		game._update_inspector()
		await capture("hud")
		game.hud.toggle_category("power")
		game.hud.build_buttons.solar.pressed.emit()
		await capture("construction")
		game._set_tool("select")
		game.selected_id = 1
		game._update_inspector()
		await capture("inspector")
		game._hud_action("clear_selection")
		game.hud.toggle_popup("stats")
		await capture("statistics")
		game.hud.toggle_popup("alerts")
		await capture("alerts")
		game.hud.close_popups()
		game.hud.operator_dock.close()
		for entry in [["market",game.market_panel,4],["digital",game.digital_panel,4],["planning",game.planning_panel,3]]:
			var panel: Control = entry[1]
			panel.open()
			for tab in int(entry[2]):
				panel.tabs.current_tab = tab
				await capture("%s_%d" % [entry[0],tab])
			panel.close()
		game.welcome.show()
		await capture("welcome")
		game.welcome.hide()
		game.help_modal.show()
		await capture("help")
		game.help_modal.hide()
		game._show_result(true)
		await capture("result")
		game.end_modal.hide()
	game.queue_free()
	await process_frame
	print("UI MATRIX: %d captures, %d save failures" % [captures,failures])
	quit(1 if failures else 0)
