extends SceneTree
var game: Node
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.welcome.hide()
	game.speed=0
	game.sim.connect_buildings(2,6)
	game.sim.connect_communication(2,6,"fiber")
	var center: Dictionary=game.sim.build("control",Vector2i(5,5))
	game.sim.connect_buildings(2,center.id)
	game.sim.connect_communication(2,center.id,"fiber")
	var relay: Dictionary=game.sim.build("relay",Vector2i(10,10))
	game.sim.connect_buildings(5,relay.id)
	game.sim.connect_communication(5,relay.id,"wireless")
	var soc: Dictionary=game.sim.build("soc",Vector2i(7,4))
	game.sim.connect_buildings(2,soc.id)
	game.sim.connect_communication(center.id,soc.id,"fiber")
	game.sim.next_storm_at=100
	game.sim.digital.next_attack_at=100
	game.sim.research()
	game.sim.step(.1)
	game._sync_world(true)
	game._update_hud()
	game.digital_panel.open()
	await _capture("digital_network")
	game.digital_panel.tabs.current_tab=1
	await _capture("digital_operations")
	game.digital_panel.tabs.current_tab=2
	await _capture("digital_security")
	game.sim.trigger_cyberattack("spoof",3)
	game.sim.step(.8)
	game.digital_panel.refresh(true)
	game.digital_panel.tabs.current_tab=3
	await _capture("digital_incident")
	game.digital_panel.close()
	game.overlay="comm"
	game._set_build_category("digital")
	game._sync_world(true)
	await _capture("digital_map")
	game.overlay="normal"
	game.selected_id=-1
	game.selected_line=1
	game._sync_world(true)
	game._update_inspector()
	await _capture("digital_observation")
	print("DIGITAL RENDER: six actual game states captured")
	quit()
func _capture(title: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/screenshots/"+title+".png")
