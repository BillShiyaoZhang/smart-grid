extends SceneTree
## Full solver integration: operating constraints must change actual energy and bills.
const Sim = preload("res://scripts/sim/grid_sim.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_test_committed_generation()
	_test_nuclear_auxiliaries()
	_test_reserve_and_shutdown()
	_test_disabled_facilities()
	_test_real_storage_coordination()
	_test_heritage()
	_test_regional_save()
	_test_continuing_goals()
	print("SANDBOX TESTS: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func near(a: float, b: float) -> bool:
	return absf(a-b) < 0.00001

func blank() -> RefCounted:
	var sim = Sim.new()
	sim.buildings.clear()
	sim.lines.clear()
	sim.objectives.clear()
	sim.next_building_id = 1
	sim.next_line_id = 1
	sim.cash = 1000000.0
	sim.next_storm_at = 100000.0
	sim.digital.reset(sim)
	sim.digital.next_attack_at = 100000.0
	sim.evolution.unlocked.assign(sim.evolution.TECHNOLOGIES.keys())
	return sim

func conservation(sim: RefCounted) -> void:
	check(absf(float(sim.totals.energy_balance_error)) < .000001,"component dispatch conserves total physical power")
	for b in sim.buildings:
		var outgoing := 0.0
		for line in sim.lines:
			outgoing += float(line.flow) if int(line.a)==int(b.id) else (-float(line.flow) if int(line.b)==int(b.id) else 0.0)
		check(absf(outgoing-float(b.output)+float(b.served)+float(b.charging)) < .0001,"new facility obeys nodal Kirchhoff balance")

func _test_committed_generation() -> void:
	var sim = blank()
	var coal: Dictionary = sim._add_building("coal",Vector2i(3,3))
	var storage: Dictionary = sim._add_building("pumped_storage",Vector2i(4,3))
	coal.ramp_mw = 48.0
	coal.startup_remaining = 0.0
	storage.energy = 0.0
	sim._add_line(1,2)
	sim._solve(1.0)
	check(near(float(coal.output),21.6) and near(float(storage.charging),21.6),"minimum thermal commitment can charge storage without customer load")
	check(near(float(storage.energy),21.6*.86),"pumped storage uses its own efficiency in the actual solver")
	check(near(float(sim.totals.fuel_cost),21.6*43.0),"thermal fuel is billed once per actual committed MWh")
	check(near(float(sim.totals.carbon),21.6*.88),"new thermal emissions include minimum running commitment")
	conservation(sim)
	storage.energy = storage.energy_capacity
	sim._solve(0.0)
	check(near(float(coal.output),0.0) and float(sim.totals.committed_spill_mw)>21.5,"unabsorbable baseload is explicit committed spill")
	check(near(float(sim.totals.fuel_cost),21.6*43.0),"curtailment cannot erase a hot unit's fuel bill")
	conservation(sim)
	var cash_before: float = sim.cash
	var energy_before: float = storage.energy
	var ramp_before: float = coal.ramp_mw
	for i in 20:
		sim._refresh()
		sim.facility_status(1)
	check(near(sim.cash,cash_before) and near(storage.energy,energy_before) and near(coal.ramp_mw,ramp_before),"display refresh neither settles costs nor moves thermal state or stored energy")

func _test_nuclear_auxiliaries() -> void:
	var sim = blank()
	var reactor: Dictionary = sim._add_building("nuclear",Vector2i(3,3))
	sim._add_building("cooling",Vector2i(4,3))
	sim._add_building("academy",Vector2i(3,4))
	sim._add_line(1,2)
	sim._add_line(1,3)
	sim._refresh()
	sim.step(1.0)
	check(near(reactor.ramp_mw,0.0) and near(reactor.startup_remaining,8.0),"a cold nuclear island cannot black-start without auxiliary electricity")
	sim._add_building("gas",Vector2i(4,4))
	sim._add_line(4,2)
	sim._refresh()
	sim.step(9.0)
	check(float(reactor.ramp_mw)>4.9 and float(reactor.output)>0.0,"energized cooling and training facilities allow a slow real startup")
	check(float(sim.get_building(2).served)>0.9 and float(sim.get_building(3).served)>.5,"supporting infrastructure consumes actual electricity")
	conservation(sim)
	var second: Dictionary = sim._add_building("nuclear",Vector2i(5,4))
	sim._add_line(5,1)
	sim._refresh()
	sim.step(.1)
	check(near(second.ramp_mw,0.0),"a second reactor cannot duplicate cooling and specialist capacity")
	sim.configure_facility(2,{"enabled":false})
	check(near(reactor.available,0.0),"losing cooling immediately removes deliverable reactor capacity")

func _test_reserve_and_shutdown() -> void:
	var sim = blank()
	var storage: Dictionary = sim._add_building("hydrogen",Vector2i(3,3))
	sim._add_building("hospital",Vector2i(4,3))
	sim._add_line(1,2)
	storage.energy = 20.0
	check(sim.configure_facility(1,{"reserve_soc":.05}).ok,"per-facility reserve is an explicit researched control")
	sim._solve(1.0)
	check(near(storage.energy,18.0) and near(storage.output,1.3),"hydrogen energy and reserve constrain delivered power at 65 percent efficiency")
	conservation(sim)
	check(not sim.configure_facility(2,{"enabled":false}).ok,"disabling customers cannot erase shortage or operating goals")
	var generator: Dictionary = sim._add_building("coal",Vector2i(5,3))
	generator.ramp_mw = 40.0
	generator.startup_remaining = 0.0
	sim._add_line(3,2)
	sim._refresh()
	check(sim.configure_facility(3,{"enabled":false}).ok and float(generator.available)>39.9,"requesting shutdown preserves the existing hot operating state")
	sim.step(.5)
	check(float(generator.ramp_mw)>37.4 and float(generator.ramp_mw)<37.6,"time advancement obeys the thermal down-ramp")

func _test_heritage() -> void:
	var sim = Sim.new()
	sim.start_heritage()
	check(sim.evolution.heritage and sim.buildings.size()==4,"historical scenario starts with local DC generation and customers")
	check(sim.evolution.can_build("dc_dynamo").ok and not sim.evolution.can_build("gas").ok and not sim.evolution.can_build("solar").ok,"historical scenario gates later generations rather than inheriting modern technology")
	check(not sim.research().ok,"historical telemetry cannot bypass the SCADA research chain")
	check(sim.research_technology("ac_systems").ok and not sim.evolution.can_build("steam").ok,"historical progression requires funded research time")
	sim.next_storm_at = 100000.0
	sim.digital.next_attack_at = 100000.0
	sim.step(1.0)
	check(sim.evolution.can_build("steam").ok,"first era transition unlocks a real new generator")

func _test_disabled_facilities() -> void:
	var sim = Sim.new()
	sim.connect_buildings(2,6)
	check(float(sim.get_building(7).output)>0.0,"renewable operating fixture has real dispatch")
	check(sim.configure_facility(7,{"enabled":false}).ok and near(float(sim.get_building(7).output),0.0),"turning off renewable equipment removes actual generation")
	check(sim.communication_status(10).reachable,"digital root begins reachable")
	check(sim.configure_facility(10,{"enabled":false}).ok and not sim.communication_status(10).reachable,"disabled digital equipment invalidates cached communication paths")
	check(sim.configure_facility(10,{"enabled":true}).ok and sim.communication_status(10).reachable,"re-enabling digital equipment restores its real path")

func _test_real_storage_coordination() -> void:
	var sim = Sim.new()
	sim.connect_buildings(2,6)
	sim.set_dispatch(1,0.0)
	sim.evolution.unlocked.assign(sim.evolution.TECHNOLOGIES.keys())
	sim.research_level = 1
	check(sim.configure_facility(9,{"storage_mode":"peak","peak_hour":17.0}).ok,"software config reaches the real storage device")
	check(sim.digital.control_reachable(sim,9) and near(float(sim.get_building(9).output),0.0),"trusted coordination reserves physical battery energy outside the peak window")
	var communication_broken := false
	for link in sim.digital.links:
		if (int(link.a)==9 and int(link.b)==2) or (int(link.a)==2 and int(link.b)==9):
			link.online = false
			communication_broken = true
	sim._refresh()
	check(communication_broken and not sim.digital.control_reachable(sim,9) and float(sim.get_building(9).output)>0.0,"cutting the actual independent communication path falls back to local emergency discharge")
	conservation(sim)

func _test_regional_save() -> void:
	var sim = Sim.new()
	sim.next_storm_at = 100000.0
	sim.digital.next_attack_at = 100000.0
	check(not sim.build("home",Vector2i(30,30)).ok,"guided opening keeps a compact playable boundary")
	check(sim.expand_region().ok and sim.map_size()==48 and sim.buildings.size()==24,"opt-in region adds seven real urban electrical islands")
	check(sim.build("home",Vector2i(30,30)).ok,"regional land becomes buildable after expansion")
	check(sim.set_sandbox_goal("regional").ok,"continuing regional goals are player selected")
	check(sim.research_technology("ac_systems").ok,"a live regional research project can be persisted")
	sim.step(.4)
	var path := "user://test_tidal-sandbox-roundtrip.json"
	check(sim.save_game(path).ok,"complete regional state saves")
	var restored = Sim.new()
	check(restored.load_game(path).ok,"complete regional state restores atomically")
	var region_matches: bool = sim.region.cities.size()==restored.region.cities.size()
	for i in sim.region.cities.size():
		region_matches = region_matches and near(float(sim.region.cities[i].population),float(restored.region.cities[i].population)) and sim.region.cities[i].specialization==restored.region.cities[i].specialization
	check(region_matches and restored.evolution.project==sim.evolution.project and near(restored.evolution.remaining_hours,sim.evolution.remaining_hours),"population, specialization and in-progress technology survive a full-grid round trip")
	check(restored.sandbox_goal=="regional" and restored.map_size()==48,"map extent and selected long-term goal survive loading")
	var original: Dictionary = restored.snapshot()
	var malformed: Dictionary = original.duplicate(true)
	malformed.region.cities[1].building_ids = [999999]
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(malformed)); file.close()
	check(not restored.load_game(path).ok and near(restored.cash,float(original.cash)),"invalid city reference is rejected without replacing current finances")
	malformed = original.duplicate(true)
	malformed.evolution.remaining_hours = -1
	file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(malformed)); file.close()
	check(not restored.load_game(path).ok and restored.evolution.snapshot()==sim.evolution.snapshot(),"invalid research progress is rejected without replacing current research")
	DirAccess.remove_absolute(path)

func _test_continuing_goals() -> void:
	var sim = Sim.new()
	sim.connect_buildings(2,6)
	sim.set_sandbox_goal("profitable")
	sim._advance_sandbox_goal(2.0)
	check(near(sim.sandbox_goal_hours,2.0),"goals accrue simulated operating duration")
	sim.set_sandbox_goal("profitable")
	check(near(sim.sandbox_goal_hours,2.0),"selecting the same goal preserves duration")
	sim.totals.reliability = .5
	sim._advance_sandbox_goal(.1)
	check(near(sim.sandbox_goal_hours,0.0),"a failed reliability condition resets continuous achievement")
	sim.totals.reliability = 1.0
	sim._advance_sandbox_goal(24.0)
	check("profitable" in sim.completed_sandbox_goals,"sustained satisfactory operation completes the selected goal")
