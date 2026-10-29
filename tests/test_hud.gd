extends SceneTree
## UI hierarchy and cross-window integration; tests use the actual scene.
var game: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+message)

func settle() -> void:
	for i in range(4): await process_frame

func escape() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	game._unhandled_input(key)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game._activate_session()
	var hud: Control = game.hud
	check(not hud.inspector.visible and not hud.tray.visible,"default map has no inspector or building tray")
	check(hud.build_buttons.size()==game.sim.catalog.size(),"every one of the 29 facilities has a catalog entry")
	var shown: Array[String] = []
	for category in ["power","grid","storage","city","digital"]:
		hud.toggle_category(category)
		check(hud.tray.visible and hud.category_buttons[category].button_pressed,"category selects and opens a tray: "+category)
		for kind in hud.build_buttons:
			if hud.build_buttons[kind].visible: shown.append(kind)
	check(shown.size()==game.sim.catalog.size(),"five categories partition all facilities without omissions or duplicates")
	hud.close_tray()
	hud.toggle_category("power")
	hud.build_buttons.solar.pressed.emit()
	check(game.tool=="build" and "18,000" in game.hint_label.text,"construction identifies active facility and price")
	hud.toggle_popup("stats")
	check(not game._modal_open(),"lightweight statistics does not pause the simulation")
	escape()
	check(not hud.popups.stats.visible and hud.tray.visible and game.tool=="build","Escape closes top popup before construction tray or tool")
	escape()
	check(not hud.tray.visible and game.tool=="build","second Escape closes tray while retaining tool")
	escape()
	check(game.tool=="select","third Escape cancels current map tool")
	var paused_before: int = game.speed
	hud.tool_buttons.line.grab_focus()
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	root.push_input(space)
	space = space.duplicate()
	space.pressed = false
	root.push_input(space)
	await settle()
	check(game.speed!=paused_before and game.tool=="select","Space pauses without activating the focused HUD command")
	hud.tool_buttons.line.release_focus()
	game._set_tool("datalink")
	check(game.overlay=="comm" and game.communication_root.visible,"communication dock tool also activates communication layer")
	game._set_tool("select")
	root.size = Vector2i(1280,720)
	await settle()
	game.selected_id = 1
	game._update_inspector()
	await settle()
	check(hud.inspector.visible,"selection opens contextual inspector")
	hud.toggle_category("grid")
	check(not hud.inspector.visible,"building tray temporarily hides selected-object inspector")
	hud.close_tray()
	check(hud.inspector.visible and game.selected_id==1,"closing tray restores selection and inspector")
	for row in game.inspector_box.get_children():
		if row.visible: check(row.size.x <= hud.inspector_scroll.size.x,"inspector rows fit the scroll viewport")
	var live_label: Node = game.inspector_box.get_child(0)
	game._update_inspector()
	check(game.inspector_box.get_child(0)==live_label,"routine inspector refresh preserves existing controls")
	hud.advanced_open = true
	game._set_advanced_visible()
	game._update_inspector()
	check(game.inspector_box.get_node("AdvancedControls").visible,"advanced fold state survives refresh")
	game._hud_action("clear_selection")
	check(not hud.inspector.visible,"closing inspector clears selection")
	var chosen_speed: int = game.speed
	var before_time: float = game.sim.elapsed_hours
	hud.toggle_popup("missions")
	game.market_panel.open()
	check(not hud.popups.missions.visible and game.market_panel.visible,"opening center closes lightweight popovers")
	game.digital_panel.open()
	check(game.digital_panel.visible and not game.market_panel.visible,"centers are mutually exclusive")
	game.planning_panel.open()
	check(game.planning_panel.visible and not game.digital_panel.visible,"planning replaces digital center")
	escape()
	check(not game._modal_open() and game.speed==chosen_speed and game.sim.elapsed_hours==before_time,"return from planning retains speed and never advances time")
	# Unknown physical faults must not create precise HUD alerts.
	for line in game.sim.lines:
		var observation: Dictionary = game.sim.line_observation(int(line.id))
		if observation.get("visibility","")=="unknown":
			line.fault = true
			hud.refresh_context()
			check(not ("线路 %02d" % line.id) in str(hud.alerts_box.get_meta("signature","")),"unknown fault does not leak a precise alert")
			line.fault = false
			break
	for resolution in [Vector2i(1280,720),Vector2i(1440,900),Vector2i(1600,1000),Vector2i(1920,1080)]:
		root.size = resolution
		await settle()
		var rect := Rect2(Vector2.ZERO,root.get_visible_rect().size)
		check(rect.encloses(hud.alert_button.get_global_rect()),"top-right navigation stays onscreen at "+str(resolution))
		var area := 0.0
		for child in hud.get_children():
			if child is PanelContainer and child.is_visible_in_tree():
				check(rect.encloses(child.get_global_rect()),"default HUD panel fits "+str(resolution)+" "+str(child.name)+" "+str(child.get_global_rect())+" within "+str(rect))
				area += child.get_global_rect().get_area()
		check(area / rect.get_area() < .35,"visual operating HUD preserves at least 65 percent of the map at "+str(resolution))
		var map_center := Vector2(rect.size.x*.5,rect.size.y*.50)
		var center_clear := true
		for child in hud.get_children():
			if child is PanelContainer and child.is_visible_in_tree() and child.get_global_rect().has_point(map_center): center_clear=false
		check(center_clear,"the central map remains directly operable at "+str(resolution))
		hud.toggle_category("storage")
		await settle()
		check(rect.encloses(hud.tray.get_global_rect()),"construction tray fits "+str(resolution))
		hud.close_tray()
	game.queue_free()
	await process_frame
	print("HUD INTEGRATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
