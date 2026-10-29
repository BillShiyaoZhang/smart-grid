extends SceneTree
## Cross-system commissioning, command execution, observation and persistence.
const Sim = preload("res://scripts/sim/grid_sim.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: "+message)

func fixture() -> RefCounted:
	var sim = Sim.new()
	sim.next_storm_at=10000.0
	sim.digital.next_attack_at=10000.0
	sim.research()
	sim.research()
	sim.step(.05)
	return sim

func _run() -> void:
	_test_commands()
	_test_commissioning_and_exposure()
	_test_persistence()
	await _test_planning_observation()
	print("DIGITAL BOUNDARIES: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _test_commands() -> void:
	var sim: RefCounted=fixture()
	var gas: Dictionary=sim.get_building(1)
	check(sim.facility_observation(1).trusted,"positive simulation time produces trusted facility samples")
	var before: float=gas.dispatch
	var elapsed: float=sim.elapsed_hours
	check(sim.configure_facility(1,{"dispatch":.5},"remote").ok,"trusted facility dispatch enters remote queue")
	check(gas.dispatch==before and sim.elapsed_hours==elapsed,"submission neither applies settings nor advances time")
	check(not sim.configure_facility(1,{"dispatch":.25},"field").ok,"a second operation cannot race the pending facility command")
	sim.step(.2)
	check(is_equal_approx(float(gas.dispatch),.5) and sim.digital.pending_commands.is_empty(),"verified remote dispatch applies after arrival")
	check(sim.configure_facility(1,{"dispatch":.75},"remote").ok,"another valid command can be queued")
	sim.isolate_device(1,true)
	sim.step(.2)
	check(is_equal_approx(float(gas.dispatch),.5),"loss of trusted path before arrival rejects facility command")
	check(not sim.facility_observation(1).trusted and sim.facility_observation(1).output==null,"isolated facility cannot expose current output through observation API")
	check(not sim.set_dispatch(1,.25).ok,"legacy dispatch entry cannot bypass communication boundary")
	var cash: float=sim.cash
	check(sim.configure_facility(1,{"dispatch":.25},"field").ok,"offline operator can dispatch a field setting crew")
	check(is_equal_approx(float(sim.cash),cash-350.0) and gas.dispatch==.5 and sim.active_repairs()==1,"field setting reserves a real crew and charges once before execution")
	sim.step(.4)
	check(is_equal_approx(float(gas.dispatch),.25) and sim.active_repairs()==0,"field setting executes without a communication path and releases the crew")
	var after_field: Dictionary=sim.facility_observation(1)
	check(after_field.trusted and after_field.visibility=="field","field crew leaves an explicitly identified local observation")
	sim.step(1.1)
	check(not sim.facility_observation(1).trusted,"field observation expires instead of showing live measurements forever")
	var observation_snapshot: Dictionary=sim.digital.snapshot()
	for i in range(4): sim.facility_observation(1)
	check(sim.digital.snapshot()==observation_snapshot,"facility observation queries do not sample or advance state")
	check(sim.configure_facility(1,{"enabled":false},"field").ok,"offline field crew can request a physical generator shutdown")
	sim.step(.35)
	check(sim.get_building(1).output==0.0 and sim.facility_observation(1).output==0.0,"field acknowledgement samples the final solved operating state")

func _test_commissioning_and_exposure() -> void:
	var historical = Sim.new()
	historical.start_heritage()
	historical.next_storm_at=10000.0
	historical.digital.next_attack_at=.01
	check(historical.digital.links.is_empty(),"historical opening has no modern initial fiber links")
	var all_off := true
	for device in historical.digital.devices.values(): all_off=all_off and not device.commissioned and device.ups_remaining==0.0
	check(all_off,"historical facilities have no commissioned gateways or free UPS before SCADA")
	historical.step(.1)
	check(historical.digital.incidents.is_empty() and historical.totals.communication_cost==0.0,"undigitized historical grid has no natural cyber incident or fiber upkeep")
	check(not historical.commission_device(2,"device").ok,"historical commissioning cannot bypass SCADA research")
	check(not historical.trigger_cyberattack("intrusion",1).ok,"even a deliberate drill requires a real digital device")
	var sim: RefCounted=fixture()
	sim.digital.links.clear()
	sim._refresh()
	var physical_before: bool=sim.get_line(1).closed
	check(not sim.digital.trigger_attack(sim,"intrusion",1,false).ok,"natural intrusion cannot target an unexposed air-gapped asset")
	check(sim.get_line(1).closed==physical_before,"rejected natural intrusion preserves electrical switching state")
	check(sim.digital.trigger_attack(sim,"intrusion",1,true).ok,"explicit local injection drill can bypass external access topology")
	check(not sim.get_line(1).closed,"local drill is clearly separated but has actual physical consequences")
	var replacement: RefCounted=fixture()
	replacement.demolish(10)
	var built: Dictionary=replacement.build("sensor",Vector2i(7,7))
	check(built.ok and int(built.id)!=10,"replacement sensor has a fresh stable identity")
	replacement.connect_buildings(2,built.id)
	replacement.connect_communication(2,built.id)
	check(not replacement.communication_status(built.id).root,"ordinary replacement role does not depend on accidental numeric ID")
	check(replacement.commission_device(built.id,"root").ok and replacement.communication_status(built.id).root,"operator can explicitly restore replacement sensor as a dispatch root")
	check(replacement.communication_status(1).reachable,"replacement dispatch root restores the connected digital network")

func _test_persistence() -> void:
	var sim: RefCounted=fixture()
	check(sim.configure_facility(1,{"dispatch":.5},"remote").ok,"save fixture contains a real in-flight facility command")
	var path := "user://test_digital_boundaries.json"
	check(sim.save_game(path).ok,"facility queue and commissioned roles save")
	var restored = Sim.new()
	check(restored.load_game(path).ok,"facility queue and commissioned roles restore atomically")
	check(restored.communication_status(10).root and restored.digital.pending_commands.size()==1,"restored role and pending command retain their semantic identities")
	restored.step(.2)
	check(is_equal_approx(float(restored.get_building(1).dispatch),.5),"restored command executes exactly once")
	var data: Dictionary=sim.snapshot()
	data.digital.pending_commands[0].settings={"dispatch":2.0}
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var cash_before: float=restored.cash
	check(not restored.load_game(path).ok and restored.cash==cash_before,"malformed queued facility settings are rejected before live state replacement")
	var legacy: Dictionary=sim.snapshot()
	legacy.schema_version=4
	legacy.digital.erase("facility_observations")
	for device in legacy.digital.devices:
		device.erase("role")
		device.erase("commissioned")
	file=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	check(restored.load_game(path).ok and restored.communication_status(10).root,"legacy schema four infers initial gateway role once during migration")
	restored.step(.2)
	check(restored.facility_observation(1).trusted,"migrated legacy role supports fresh facility telemetry on positive time")
	legacy=sim.snapshot()
	legacy.schema_version=2
	legacy.erase("digital")
	file=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	check(restored.load_game(path).ok and restored.communication_status(10).root,"pre-digital saves migrate to a functional explicit dispatch root")
	DirAccess.remove_absolute(path)

func find_button(parent: Node, caption: String) -> Button:
	if parent is Button and parent.text==caption: return parent
	for child in parent.get_children():
		var found := find_button(child,caption)
		if found!=null: return found
	return null

func _test_planning_observation() -> void:
	var game: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._activate_session()
	game.sim.research()
	game.sim.research()
	game.sim.step(.05)
	game.sim.isolate_device(1,true)
	game.planning_panel.open()
	game.planning_panel.select_facility(1)
	check("遥测未确认" in game.planning_panel.facility_info.text,"planning center uses the same masked facility observation boundary as map inspector")
	check(not "每小时燃料" in game.planning_panel.facility_info.text,"planning no longer leaks instantaneous fuel expenditure during isolation")
	check(game.planning_panel.facility_method.selected==1,"unreachable device defaults to explicit field execution")
	game.planning_panel.close()
	game.selected_id=1
	game._update_inspector()
	var remote := find_button(game.inspector_box,"远程0%")
	var field := find_button(game.inspector_box,"现场0%")
	check(remote!=null and remote.disabled and field!=null and not field.disabled,"main inspector offers disabled remote control and explicit field fallback while isolated")
	if field!=null:
		field.pressed.emit()
		check(game.sim.get_building(1).dispatch==1.0 and game.sim.digital.field_jobs.size()==1,"main inspector callback queues field work without a live dispatch change")
		game.sim.step(.4)
		check(game.sim.get_building(1).dispatch==0.0,"main inspector field action takes effect only after simulated work")
	var sensor: Dictionary=game.sim.build("sensor",Vector2i(7,6))
	game.digital_panel.open()
	game.digital_panel._select_device(sensor.id)
	check(game.digital_panel.commission_button.visible and not game.digital_panel.commission_button.disabled,"replacement-capable sensor exposes an explicit dispatch-root commissioning action")
	game.digital_panel.commission_button.pressed.emit()
	check(game.sim.communication_status(sensor.id).root,"digital center commissioning callback assigns a persistent semantic root role")
	game.queue_free()
	await process_frame
