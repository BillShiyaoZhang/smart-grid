extends SceneTree
## Exercise actual planning callbacks and preserve drafts across display refreshes.
var checks := 0
var failures := 0
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: "+message)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.welcome.hide()
	var panel: Control = game.planning_panel
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_T
	game._unhandled_input(key)
	_check(panel.visible and game._modal_open(),"T opens the new planning center through the real keyboard handler")
	key.keycode = KEY_ESCAPE
	game._unhandled_input(key)
	_check(not panel.visible and not game._modal_open(),"Escape closes planning without leaving a blocking modal")
	panel.open()
	_check(panel.visible and game._modal_open(),"planning opens as a paused modal")
	_check(panel.technology_buttons.size()>=20,"broad era tree has at least twenty actionable research cards")
	_check(panel.construction_buttons.size()==game.sim.catalog.size(),"every facility is available through the planning catalog")
	_check(panel.era_buttons.size()==6 and not panel.scenario_actions.visible,"six eras are directly accessible while scenario replacement stays secondary")
	var browse_cash: float = game.sim.cash
	var browse_hours: float = game.sim.elapsed_hours
	panel._select_era(4)
	var era_filter_correct := true
	for id in panel.technology_cards:
		era_filter_correct = era_filter_correct and panel.technology_cards[id].visible==(int(game.sim.evolution.TECHNOLOGIES[id].era)==4)
	_check(era_filter_correct,"era navigation shows only technologies from the selected era")
	panel._select_era(5)
	panel.technology_buttons.fusion_engineering.pressed.emit()
	_check(panel.selected_technology=="fusion_engineering" and "聚变示范工程" in panel.technology_title.text and panel.technology_action.disabled,"locked technologies remain inspectable with research correctly disabled")
	_check(is_equal_approx(float(game.sim.cash),browse_cash) and is_equal_approx(float(game.sim.elapsed_hours),browse_hours),"browsing eras and locked details neither spends funds nor advances time")
	panel._select_era(0)
	panel.technology_buttons.ac_systems.pressed.emit()
	_check(not panel.technology_action.disabled,"available research exposes an enabled detail action")
	panel.technology_action.pressed.emit()
	_check(game.sim.evolution.project=="ac_systems" and is_equal_approx(float(game.sim.cash),browse_cash-8500),"research detail starts the authoritative project and pays its displayed cost")
	panel._advance()
	_check(game.sim.evolution.has_technology("ac_systems") and is_equal_approx(float(game.sim.elapsed_hours),browse_hours+1),"explicit planning advance completes the timed research")
	panel.tabs.current_tab=1
	panel.facility_modes.current_tab=1
	panel.catalog_category.select(2)
	panel.catalog_category.item_selected.emit(2)
	var storage_filter_correct := true
	for kind in panel.catalog_cards:
		storage_filter_correct = storage_filter_correct and panel.catalog_cards[kind].visible==game.sim.evolution.is_storage(kind)
	_check(storage_filter_correct,"catalog category isolates storage while retaining the complete catalog")
	panel.select_facility(9)
	_check(panel.tabs.current_tab==1 and panel.facility_modes.current_tab==0 and panel.selected_facility==9,"inspector handoff returns from catalog to selected storage controls")
	var before_energy: float = game.sim.get_building(9).energy
	var before_cash: float = game.sim.cash
	var before_time: float = game.sim.elapsed_hours
	panel.reserve_input.value = 55
	panel.storage_input.select(2)
	panel.peak_input.value = 18
	panel.refresh()
	_check(panel.reserve_input.value==55 and panel.storage_input.selected==2,"routine refresh preserves draft storage settings")
	_check(is_equal_approx(float(game.sim.elapsed_hours),before_time) and is_equal_approx(float(game.sim.cash),before_cash) and is_equal_approx(float(game.sim.get_building(9).energy),before_energy),"planning refresh neither advances time nor spends money or stored energy")
	panel._apply_facility()
	_check(game.sim.get_building(9).storage_mode=="auto","advanced strategy is rejected before the required research")
	# This UI fixture represents a later-game operator with the full research tree.
	game.sim.evolution.unlocked.assign(game.sim.evolution.TECHNOLOGIES.keys())
	panel.refresh(true)
	panel.reserve_input.value = 55
	panel.storage_input.select(2)
	panel.peak_input.value = 18
	panel._apply_facility()
	var battery: Dictionary = game.sim.get_building(9)
	_check(is_equal_approx(float(battery.reserve_soc),.55) and battery.storage_mode=="peak" and is_equal_approx(float(battery.peak_hour),18),"explicit Apply commits local storage strategy")
	panel.close()
	_check(not panel.visible and not game._modal_open(),"close returns to the live grid")
	panel.open()
	panel._choose_build("dc_dynamo")
	_check(not panel.visible and game.tool=="build" and game.build_kind=="dc_dynamo","catalog selection enters the real map construction tool")
	game._handle_map_click(Vector2i(2,2))
	var dynamo: Dictionary = game.sim.building_at(Vector2i(2,2))
	_check(not dynamo.is_empty() and dynamo.kind=="dc_dynamo","new era facility is built by map input and synchronized into the world")
	if not dynamo.is_empty():
		_check(game.visuals.has(dynamo.id),"new facility has a rendered model")
	panel.open()
	panel.tabs.current_tab=2
	panel.expand_button.pressed.emit()
	_check(game.sim.region.active and game.sim.region.cities.size()==8,"regional planning action activates eight real cities")
	_check(panel.city_labels.size()==8,"city feedback cards follow activated simulation state")
	panel.city_picker.select(1)
	panel.city_picker.item_selected.emit(1)
	_check(panel.selected_city==panel.city_picker.get_selected_id() and panel.city_cards[panel.selected_city].visible and not panel.city_cards[0].visible,"city picker shows the selected city detail without filling the page with all cities")
	panel.region_map.city_selected.emit(1)
	_check(not panel.visible,"regional map selection returns to the focused world")
	panel.open()
	var goal: Dictionary = game.sim.sandbox_goals()[0]
	panel._commit(game.sim.set_sandbox_goal(goal.id))
	_check(game.sim.sandbox_goal==goal.id and str(goal.name) in panel.current_goal.text,"selected sandbox goal is reflected in the persistent region summary")
	var models = load("res://scripts/art/model_factory.gd")
	for kind in game.sim.evolution.EXTRA_CATALOG:
		var model: Node3D = models.building(kind)
		_check(model.get_child_count()>5,"distinct procedural model exists for "+kind)
		model.free()
	# Exercise the real scenario switch with an isolated backup file.
	var backup_path := "user://test_tidal-planning-heritage.json"
	var original_cash: float = game.sim.cash
	game.start_heritage_game(backup_path)
	_check(game.sim.evolution.heritage and game.sim.buildings.size()==4 and game.visuals.size()==4,"historical scenario switch rebuilds its real facilities and models")
	_check(not game.planning_panel.visible and game.terrain_size==16,"historical switch closes planning and returns to the teaching map")
	_check(game.build_buttons.gas.disabled and game.build_buttons.solar.disabled,"historical construction palette respects research gates")
	game._load(backup_path)
	_check(game.sim.region.active and game.terrain_size==48 and is_equal_approx(float(game.sim.cash),original_cash),"switch backup restores prior regional progress finances and terrain")
	DirAccess.remove_absolute(backup_path)
	game.queue_free()
	await process_frame
	print("PLANNING GAME: %d checks; %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
