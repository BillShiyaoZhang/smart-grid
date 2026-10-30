extends SceneTree
## Isolated design reference: actual models, no interface or player save writes.
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Background capture requires GPU rendering.")
		quit(1)
		return
	DisplayServer.window_set_size(Vector2i(1920,1080))
	root.size = Vector2i(1920,1080)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for frame in range(8): await process_frame
	game.set_process(false)
	game.speed = 0
	game.onboarding = false
	game.onboarding_skipped = true
	game.sim.reset(42)
	game.sim.next_storm_at = 100.0
	game.sim.digital.next_attack_at = 100.0
	game._rebuild_session(true)
	game.speed = 0
	game._activate_session()
	game._focus_working_area()
	game._sync_world(true)
	game.root_ui.hide()
	game.marker_root.hide()
	game.rain_root.hide()
	DisplayServer.window_set_size(Vector2i(1920,1080))
	root.size = Vector2i(1920,1080)
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result := image.save_png("res://docs/design/interface-review-2026-10-30/day-background.png")
	print("DESIGN BACKGROUND: ", result, " ", image.get_size())
	quit(int(result))
