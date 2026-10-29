extends SceneTree
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1600,1000)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.welcome.hide()
	game.speed = 0
	game.sim.connect_buildings(2,6)
	game.sim.cash = 1000000
	game.planning_panel.open()
	await _capture("planning_technology")
	game.sim.evolution.unlocked.assign(game.sim.evolution.TECHNOLOGIES.keys())
	game.planning_panel.select_facility(9)
	game.planning_panel.refresh(true)
	game.planning_panel.reserve_input.value = 30
	game.planning_panel.storage_input.select(2)
	game.planning_panel._apply_facility()
	await _capture("planning_storage")
	game.sim.expand_region()
	game.sim.connect_buildings(2,11)
	game.sim.connect_buildings(12,13)
	game.sim.connect_buildings(14,23)
	game.sim.connect_buildings(24,21)
	game.sim.set_sandbox_goal("regional")
	game.planning_panel.tabs.current_tab = 2
	game.planning_panel.refresh(true)
	await _capture("planning_region")
	game.planning_panel.close()
	game.focus_city(7)
	game.zoom = 110
	game.cam_target = game._cell_position(Vector2i(24,24))
	game._update_camera()
	game._sync_world(true)
	game._update_hud()
	await _capture("planning_world")
	game.queue_free()
	await process_frame
	print("PLANNING RENDER: four actual gameplay states captured")
	quit()

func _capture(title: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/screenshots/"+title+".png")
