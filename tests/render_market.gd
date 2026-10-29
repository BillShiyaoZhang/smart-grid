extends SceneTree
var capture_failures := 0
var game: Node
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.welcome.hide()
	game.speed = 0
	game.sim.connect_buildings(2,6)
	var terminal: Dictionary = game.sim.build("intertie",Vector2i(4,5))
	game.sim.connect_buildings(2,terminal.id)
	game.sim.set_market_policy("trade",125,30)
	game.sim.set_tariff("custom",85,145,235)
	game.sim.set_storage_policy("arbitrage",60,150,.25)
	game.sim.time_hours = 23.0
	game.sim.elapsed_hours = 15.0
	game.sim.next_storm_at = 100.0
	game.sim.digital.next_attack_at = 100.0
	game.sim._update_weather()
	game.sim.step(.5)
	game._sync_world(true)
	game._update_hud()
	game.market_panel.open()
	await _capture("market_trading")
	game.market_panel.tabs.current_tab = 1
	await _capture("market_tariffs")
	game.market_panel.tabs.current_tab = 2
	await _capture("market_storage")
	game.market_panel._sign_contract()
	game.market_panel._advance()
	game.market_panel.tabs.current_tab = 3
	await _capture("market_ledger")
	game.market_panel.close()
	game.selected_id = terminal.id
	game._update_inspector()
	await _capture("market_grid")
	print("MARKET RENDER: five trading states captured")
	quit(1 if capture_failures>0 else 0)
func _capture(title: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png("res://docs/screenshots/"+title+".png")
	if result != OK:
		capture_failures += 1
		push_error("Screenshot save failed: "+title)
