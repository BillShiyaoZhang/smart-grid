extends SceneTree
var captures:=0
var failures:=0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var game: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for _frame in 5: await process_frame
	game.set_process(false)
	game._activate_session()
	game.speed=0
	game.sim.evolution.unlocked.append("regional_planning")
	game.sim.evolution.unlocked.append("scada")
	game.sim.research_level=2
	game.sim.cash=1000000
	for system in ["lifecycle","engineering","customers"]: game.sim.commission_expansion(system)
	game.sim.expansion_action("customer",{"id":3,"settings":{"metered":true,"consent":true,"pv_mw":2.0,"battery_mwh":5.0,"battery_mw":2.0,"ev_mw":2.0,"ev_target_mwh":4.0,"smart":true}})
	game.sim.step(.05)
	game._sync_world(true)
	game._update_hud()
	game.digital_panel.open()
	game.digital_panel.tabs.current_tab=4
	for layout in [[Vector2i(1440,900),1.0],[Vector2i(1280,720),1.0],[Vector2i(1280,720),1.5]]:
		var resolution: Vector2i=layout[0]
		DisplayServer.window_set_size(resolution)
		root.size=resolution
		game.preferences.ui_scale=float(layout[1])
		game._apply_preferences()
		var destination: String="res://.godot/operations-ui-qa/%dx%d_%d" % [resolution.x,resolution.y,int(float(layout[1])*100)]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
		for index in 4:
			var panel: Node=game.digital_panel.grid_operations
			panel.section.select(index)
			panel.section.item_selected.emit(index)
			game.digital_panel._scroll_page_top(4)
			game.notice_label.hide()
			game.tooltip_label.hide()
			for _frame in 7: await process_frame
			await RenderingServer.frame_post_draw
			if root.get_texture().get_image().save_png(destination.path_join("operations_%d.png" % index))!=OK: failures+=1
			captures+=1
	game.queue_free()
	await process_frame
	print("GRID OPERATIONS RENDER: %d images, %d failures" % [captures,failures])
	quit(1 if failures>0 else 0)
