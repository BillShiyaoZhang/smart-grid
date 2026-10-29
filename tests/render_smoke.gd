extends SceneTree
## Render actual scenes through the game renderer for visual QA.
var capture_failures := 0
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await _capture("welcome")
	game.welcome.hide()
	game.speed = 0
	game.sim.connect_buildings(2,6)
	var solar: Dictionary = game.sim.build("solar",Vector2i(8,3))
	game.sim.connect_buildings(2,solar.id)
	game.sim.research()
	game._sync_world(true)
	game._update_hud()
	game._update_inspector()
	for i in range(40):
		game.sim.step(0.025)
		game.chart.sample(game.sim.totals.demand,game.sim.totals.generation)
	game._sync_world(true)
	game._update_hud()
	game._update_inspector()
	await _capture("gameplay")
	game.help_modal.show()
	await _capture("guide")
	game.help_modal.hide()
	game._storm()
	game.sim.step(.05)
	game._sync_world(true)
	for line in game.sim.lines:
		if line.fault:
			game.selected_line = int(line.id)
			break
	game._update_inspector()
	await _capture("storm")
	for line in game.sim.lines:
		if line.fault:
			game.sim.repair_line(int(line.id))
	game.sim.step(0.8)
	game.sim.research()
	game._sync_world(true)
	game._update_hud()
	game._update_inspector()
	await _capture("victory")
	game.end_modal.hide()
	game.selected_line = -1
	game.sim.time_hours = 22.0
	game.sim.storm_active = false
	game.sim._update_weather()
	game.sim._solve(0.0)
	game._sync_world(true)
	game._update_hud()
	game._update_inspector()
	await _capture("night")
	print("RENDER SMOKE: six real game states captured")
	quit(1 if capture_failures>0 else 0)

func _capture(title: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://docs/screenshots")
	var result: Error = img.save_png("res://docs/screenshots/"+title+".png")
	if result != OK:
		capture_failures += 1
		push_error("Screenshot save failed: "+title)
