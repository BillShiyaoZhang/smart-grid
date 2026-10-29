extends SceneTree
## Integration coverage for the real scene: UI callbacks, map tools, sim and visuals.

var checks := 0
var failures := 0
var game: Node
var event_count := 0
var change_count := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else:
		print("PASS: " + message)

func _find_button(root: Node, caption: String) -> Button:
	if root is Button and caption in root.text:
		return root
	for child in root.get_children():
		var found := _find_button(child, caption)
		if found != null:
			return found
	return null

func _contains_label(root: Node, text: String) -> bool:
	if root is Label and text in root.text:
		return true
	for child in root.get_children():
		if _contains_label(child, text):
			return true
	return false

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	_check(game.is_ready, "main scene creates world and UI")
	_check(game.welcome.visible and game._modal_open(), "welcome modal initially blocks gameplay")
	_check(game.sim.buildings.size() == 10 and game.visuals.size() == 10, "ten initial assets have matching visuals")
	_check(game.hud_values.size() == 6, "six readings are available across status rail and statistics")
	_check(game.build_buttons.size() >= 8, "construction palette exists")
	game.sim.event_logged.connect(func(_entry: Dictionary): event_count += 1)
	game.sim.changed.connect(func(): change_count += 1)
	_check(_find_button(game.welcome,"开始运营") != null, "welcome has a primary guided management entry")
	var begin := _find_button(game.welcome,"自由沙盘")
	_check(begin != null, "welcome preserves the free sandbox entry for the full simulation workflow")
	if begin != null:
		begin.pressed.emit()
	_check(not game.welcome.visible and not game._modal_open(), "start button enters game")
	var initial_time: float = game.sim.time_hours
	game.sim.time_hours = 12.0
	game._update_lighting()
	var daytime_energy: float = game.sun_light.light_energy
	game.sim.time_hours = 0.0
	game._update_lighting()
	_check(float(game.sun_light.light_energy) < daytime_energy, "night lighting is dimmer than midday sunlight")
	game.sim.time_hours = initial_time
	game._update_lighting()
	# Screen-space clicks on elevated geometry must select its footprint, not
	# the neighboring cell behind it where a ground-plane ray would intersect.
	await physics_frame
	await process_frame
	var home_cell: Vector2i = game.sim.get_building(3).cell
	var home_roof: Vector3 = game._cell_position(home_cell) + Vector3.UP * 0.9
	_check(game._cell_at_screen(game.camera.unproject_position(home_roof)) == home_cell, "roof-height screen picking selects residential footprint")
	var wind_cell: Vector2i = game.sim.get_building(8).cell
	var wind_tower: Vector3 = game._cell_position(wind_cell) + Vector3.UP * 1.5
	_check(game._cell_at_screen(game.camera.unproject_position(wind_tower)) == wind_cell, "tower-height screen picking selects wind footprint")
	var empty_cell := Vector2i(13,3)
	var empty_ground: Vector3 = game._cell_position(empty_cell)
	_check(game._cell_at_screen(game.camera.unproject_position(empty_ground)) == empty_cell, "empty ground screen picking preserves map-cell mapping")

	# The opening mission requires a real missing connection to the industrial load.
	var old_lines: int = game.sim.lines.size()
	game._set_tool("line")
	game._handle_map_click(game.sim.get_building(2).cell)
	_check(game.connection_start == 2, "line tool remembers first endpoint")
	game._handle_map_click(game.sim.get_building(6).cell)
	_check(game.connection_start == -1 and game.sim.lines.size() == old_lines + 1, "second map click creates a line and clears endpoint")
	_check(game.sim.get_building(6).powered, "new line energises industrial district")
	_check(game.sim.objectives[0].done, "opening electrification objective completes")
	_check(game.cable_visuals.size() == game.sim.lines.size(), "new cable is represented in scene")

	# Construction through actual UI callback, not just the simulation interface.
	var old_cash: float = game.sim.cash
	var old_reward := 0.0
	for objective in game.sim.objectives:
		if objective.done:
			old_reward += float(objective.reward)
	game.build_buttons.solar.pressed.emit()
	_check(game.tool == "build" and game.build_kind == "solar", "solar palette button changes map tool")
	var new_cell := Vector2i(5,4)
	game._handle_map_click(new_cell)
	var new_id: int = game._building_at(new_cell)
	_check(new_id > 0 and game.sim.buildings.size() == 11, "build click places solar on free land")
	var new_reward := 0.0
	for objective in game.sim.objectives:
		if objective.done:
			new_reward += float(objective.reward)
	var solar_price: float = game.Sim.CATALOG.solar.price
	_check(is_equal_approx(float(game.sim.cash), old_cash - solar_price + new_reward - old_reward) and game.visuals.has(new_id), "construction accounts for capex and mission rewards and creates model")
	_check(is_zero_approx(float(game.sim.get_building(new_id).output)), "unconnected solar is curtailed")
	game._set_tool("line")
	game._handle_map_click(new_cell)
	game._handle_map_click(game.sim.get_building(2).cell)
	_check(float(game.sim.get_building(new_id).output) > 0.0, "connecting new solar gives it a dispatch role")
	_check(game.sim.objectives[1].done, "renewable transition objective is achievable")

	# Rejected map commands must preserve authoritative state and show feedback.
	game.build_buttons.solar.pressed.emit()
	game._handle_map_click(new_cell)
	_check(game.sim.buildings.size() == 11 and game.notice_label.visible, "occupied tile is rejected without duplicate model")
	game._set_tool("select")
	game._handle_map_click(new_cell)
	_check(game.selected_id == new_id and game.selection_ring.visible, "select tool focuses building and selection marker")
	_check(_contains_label(game.inspector_box,"光伏电站"), "building inspector displays selected facility")
	_check(_find_button(game.inspector_box,"升级") != null, "building inspector has upgrade action")

	# Selecting a line after the topology view used to leave a freed chart reference.
	game.selected_id = -1
	game.selected_line = -1
	game._update_inspector()
	_check(game.topology != null, "statistics retains topology while empty inspector stays hidden")
	game.selected_line = 1
	game._update_inspector()
	await process_frame
	game._sync_world()
	_check(_contains_label(game.inspector_box,"配电线路"), "line inspector survives topology view disposal")
	var switch_button := _find_button(game.inspector_box,"现场开关")
	_check(switch_button != null, "line inspector exposes an offline field-switch action")
	if switch_button != null:
		var before: bool = game.sim.get_line(1).closed
		switch_button.pressed.emit()
		_check(game.sim.get_line(1).closed == before and not game.sim.digital.field_jobs.is_empty(), "field-switch action queues work without an instant physical change")
		game.sim.step(0.4)
		_check(game.sim.get_line(1).closed != before, "field crew changes graph connectivity after travel and work")
		game.sim.field_switch(1)
		game.sim.step(0.4)

	# Scripted storm produces real fault isolation; repair jobs take simulated time.
	game._storm()
	_check(game.sim.storm_active and int(game.sim.totals.faults) >= 1, "storm action damages and isolates lines")
	_check(game.rain_root.visible, "storm state activates visible rain effect")
	var fault_ids: Array[int] = []
	for line in game.sim.lines:
		if line.fault:
			fault_ids.append(int(line.id))
	for line_id in fault_ids:
		game.selected_line = line_id
		game._update_inspector()
		var patrol_button := _find_button(game.inspector_box,"巡检定位")
		_check(patrol_button != null, "unknown fault can be located by a field patrol")
		if patrol_button != null:
			patrol_button.pressed.emit()
	game.sim.step(0.55)
	for line_id in fault_ids:
		game.selected_line = line_id
		game._update_inspector()
		var repair_button := _find_button(game.inspector_box,"派遣线路抢修队")
		_check(repair_button != null, "fault inspector offers repair crew")
		if repair_button != null:
			repair_button.pressed.emit()
	_check(game.sim.active_repairs() == fault_ids.size(), "repair callbacks dispatch finite repair jobs")
	game.sim.step(0.7)
	game._sync_world(true)
	game._update_hud()
	_check(int(game.sim.totals.faults) == 0 and game.sim.active_repairs() == 0, "repair completion clears faults and frees crews")
	_check(float(game.sim.totals.reliability) >= 0.98, "repairs restore city supply")
	_check(game.sim.objectives[3].done, "storm recovery objective completes")

	# Building repair tool dispatches to the clicked asset.
	var asset: Dictionary = game.sim.get_building(new_id)
	asset.health = 75.0
	game._set_tool("repair")
	game._handle_map_click(new_cell)
	_check(float(asset.repair_remaining) > 0.0 and not asset.online, "repair map tool schedules facility maintenance")
	game.sim.step(0.7)
	_check(asset.online and float(asset.health) > 99.0, "facility maintenance returns asset to service")

	game._research()
	game._research()
	# Research grants capability, while a real path and a timed sample grant data.
	game.sim.connect_communication(10,1,"fiber")
	game.sim.step(0.05)
	_check(game.sim.research_level == 2 and game.sim.objectives[2].done, "research UI reaches self-healing tier and completes objective")
	_check(game.sim.communication_status(1).trusted and game.sim.has_telemetry(1), "research plus connected trusted gateways and a sample provide telemetry")
	_check(game.end_modal.visible and game._modal_open(), "four completed objectives display victory modal")
	var continue_button := _find_button(game.end_modal,"继续运营")
	var restart_button := _find_button(game.end_modal,"重新开始")
	_check(continue_button != null and restart_button != null, "victory offers continued operation and a fresh game")
	if continue_button != null:
		continue_button.pressed.emit()
	_check(not game.end_modal.visible and not game._modal_open(), "continue operation dismisses victory modal")
	var response_button := _find_button(game.root_ui,"需求响应")
	_check(response_button != null, "operation panel exposes demand response action")
	var demand_before_response: float = game.sim.totals.demand
	if response_button != null:
		response_button.pressed.emit()
	_check(float(game.sim.demand_response_remaining) > 0.0 and float(game.sim.totals.demand) < demand_before_response, "research tier two enables real demand response through UI")
	_check(event_count > 10 and change_count > 10, "UI mutations emit model events and state changes")

	# Saving and loading must restore both data and derived scene representations.
	var save_path := "user://test_tidal_grid_integration_save.json"
	var saved_cash: float = game.sim.cash
	var saved_count: int = game.sim.buildings.size()
	_check(game.sim.save_game(save_path).ok, "isolated portable integration snapshot saves")
	game.sim.demolish(new_id)
	game._sync_world(true)
	_check(not game.visuals.has(new_id), "demolition removes visual model")
	_check(game.sim.load_game(save_path).ok, "integration snapshot reloads")
	game._sync_world(true)
	game._update_hud()
	_check(game.sim.buildings.size() == saved_count and game.visuals.has(new_id), "reload recreates missing visual asset")
	_check(is_equal_approx(float(game.sim.cash),saved_cash), "reload restores cash without duplicate rewards")
	DirAccess.remove_absolute(save_path)

	game.speed = 3
	game._toggle_pause()
	_check(game.speed == 0 and game.hud.pause_button.button_pressed, "pause updates simulation speed and HUD")
	game._toggle_pause()
	_check(game.speed == 3, "resume restores chosen speed")
	game.help_modal.show()
	_check(game._modal_open(), "help modal suspends map interactions")
	game.help_modal.hide()
	game._set_tool("select")
	_check(game.connection_start == -1 and game.tool_buttons.select.button_pressed, "cancel resets tool state and button selection")
	if restart_button != null:
		restart_button.pressed.emit()
	_check(game.sim.buildings.size() == 10 and game.visuals.size() == 10 and game.sim.day == 1, "restart creates the original ten-asset day-one scenario")
	_check(is_equal_approx(float(game.sim.cash),180000.0) and game.sim.research_level == 0, "restart resets finances and research")
	var unfinished := false
	for objective in game.sim.objectives:
		if not objective.done:
			unfinished = true
	_check(unfinished and not game.end_modal.visible and not game.last_finished, "restart clears victory state and returns to active play")
	await process_frame
	print("GAME INTEGRATION: %d checks, %d failures" % [checks,failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
