extends SceneTree

const Sim = preload("res://scripts/sim/grid_sim.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_test_initial_and_commands()
	_test_dc_loop_and_conservation()
	_test_storage_energy()
	_test_protection_and_repairs()
	_test_determinism_and_save()
	_test_research_and_objectives()
	_test_priority_and_auto_restore()
	_test_scheduled_storms_and_compensation()
	print("SIM TESTS: %d checks; %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func near(a: float, b: float, tolerance: float = 0.00001) -> bool:
	return absf(a - b) <= tolerance

func blank() -> RefCounted:
	var sim = Sim.new()
	sim.buildings.clear()
	sim.lines.clear()
	sim.objectives.clear()
	sim.digital.reset(sim)
	sim.digital.next_attack_at = 10000.0
	sim.next_building_id = 1
	sim.next_line_id = 1
	sim.cash = 1000000.0
	return sim

func _test_initial_and_commands() -> void:
	var sim = Sim.new()
	check(sim.buildings.size() == 10, "scenario has all ten facilities")
	check(not sim.get_building(6).powered, "industrial park starts disconnected")
	check(float(sim.totals.reliability) < 0.98, "initial outage is visible")
	check(not sim.connect_buildings(1, 1).ok, "self link is rejected")
	check(not sim.connect_buildings(1, 2).ok, "duplicate line is rejected")
	check(not sim.connect_buildings(1, 999).ok, "missing endpoint is rejected")
	check(not sim.build("unknown", Vector2i(2, 2)).ok, "unknown construction rejected")
	check(not sim.build("solar", Vector2i(0, 0)).ok, "shore construction rejected")
	check(not sim.build("solar", Vector2i(3, 7)).ok, "occupied construction rejected")
	var cash_before: float = sim.cash
	sim.cash = 0.0
	check(not sim.build("solar", Vector2i(2, 2)).ok, "insufficient funds rejected")
	sim.cash = cash_before
	check(sim.connect_buildings(2, 6).ok, "industrial feeder can be built")
	check(sim.get_building(6).powered, "industrial park receives power immediately")
	check(near(sim.totals.reliability, 1.0), "all initial demand served after connecting")
	check(sim.objectives[0].done, "first mission completes")
	var result: Dictionary = sim.build("solar", Vector2i(2, 3))
	check(result.ok and result.id > 10, "new facility has a stable unique identifier")
	check(not sim.get_building(result.id).powered, "new facility needs a connection")
	check(sim.connect_buildings(result.id, 2).ok, "new renewable can join the grid")
	check(float(sim.get_building(result.id).output) > 0, "connected solar produces actual power")
	var count_before: int = sim.lines.size()
	check(sim.demolish(result.id).ok, "demolition succeeds")
	check(sim.lines.size() == count_before - 1, "demolition removes incident electrical edges")

func _test_dc_loop_and_conservation() -> void:
	var sim = blank()
	sim._add_building("gas", Vector2i(2, 6))
	sim._add_building("substation", Vector2i(5, 3))
	sim._add_building("substation", Vector2i(5, 9))
	sim._add_building("factory", Vector2i(8, 6))
	sim._add_line(1, 2)
	sim._add_line(2, 4)
	sim._add_line(1, 3)
	sim._add_line(3, 4)
	sim._refresh()
	check(near(sim.get_line(1).flow, 5.5), "DC loop shares power equally across symmetric routes")
	check(near(sim.get_line(3).flow, 5.5), "second route carries its share")
	_assert_kcl(sim)
	check(sim.toggle_line(1).ok, "switch opens a network edge")
	check(near(sim.get_line(3).flow, 11.0), "open line redistributes power to the alternate route")
	check(near(sim.totals.reliability, 1.0), "ring maintains supply after one branch opens")
	_assert_kcl(sim)
	sim.get_building(4).online = false
	sim._refresh()
	check(near(sim.totals.generation, 0.0), "maintenance load is not falsely dispatched")
	_assert_kcl(sim)

func _assert_kcl(sim: RefCounted) -> void:
	for building in sim.buildings:
		var outgoing := 0.0
		for line in sim.lines:
			if int(line.a) == int(building.id):
				outgoing += float(line.flow)
			if int(line.b) == int(building.id):
				outgoing -= float(line.flow)
		var injection := float(building.output) - float(building.served) - float(building.charging)
		check(near(outgoing, injection, 0.0001), "Kirchhoff conservation at node %s" % building.id)

func _test_storage_energy() -> void:
	var sim = blank()
	sim._add_building("battery", Vector2i(3, 3))
	sim._add_building("hospital", Vector2i(4, 3))
	sim._add_line(1, 2)
	var battery: Dictionary = sim.get_building(1)
	battery.energy = 10.0
	sim._solve(0.0)
	check(near(battery.energy, 10.0), "a UI-only solve does not consume stored energy")
	sim._solve(0.5)
	check(near(battery.energy, 10.0 - 3.0 / 0.94), "discharge respects MW-to-MWh and efficiency")
	check(near(sim.totals.served, 6.0), "battery supplies real hospital load")
	battery.energy = 0.01
	sim._solve(0.5)
	check(near(battery.energy, 0.0), "storage never becomes negative")
	check(near(sim.totals.served, 0.01 * 0.94 / 0.5), "energy-limited discharge caps delivered power")
	var solar = blank()
	solar._add_building("solar", Vector2i(3, 3))
	solar._add_building("battery", Vector2i(4, 3))
	solar._add_line(1, 2)
	solar.time_hours = 12.0
	solar.weather = "晴朗"
	solar.get_building(2).energy = 0.0
	solar._solve(1.0)
	check(near(solar.get_building(2).energy, 9.4), "surplus solar charges at battery power limit and efficiency")
	check(near(solar.get_building(1).output, 10.0), "unused renewable output is curtailed")
	solar.get_building(2).energy = 29.9
	solar._solve(1.0)
	check(near(solar.get_building(2).energy, 30.0), "charge never exceeds energy capacity")
	_assert_kcl(solar)
	solar.time_hours = 0.0
	solar._solve(0.1)
	check(near(solar.get_building(1).output, 0.0), "solar does not generate at night")

func _test_protection_and_repairs() -> void:
	var sim = blank()
	sim._add_building("gas", Vector2i(3, 3))
	sim._add_building("factory", Vector2i(4, 3))
	sim._add_line(1, 2)
	sim.get_line(1).capacity = 4.0
	sim._refresh()
	check(float(sim.totals.max_loading) > 2.0, "overload is measured from actual flow")
	sim.step(0.2)
	check(not sim.get_line(1).closed, "sustained overload opens protection breaker")
	check(near(sim.totals.served, 0.0), "tripped radial line causes an outage")
	check(sim.upgrade_line(1).ok, "line can be reinforced")
	check(sim.upgrade_line(1).ok, "line can receive a second capacity upgrade")
	sim.get_line(1).capacity = 20.0
	check(sim.toggle_line(1).ok, "healthy tripped line can be reclosed")
	check(sim.get_building(2).powered, "reclosing restored line serves load")
	check(sim.trigger_storm().ok, "storm damages a real network branch")
	check(sim.get_line(1).fault, "storm records a physical fault")
	check(not sim.toggle_line(1).ok, "fault cannot be manually re-energized")
	check(sim.repair_line(1).ok, "repair command schedules a crew")
	check(sim.active_repairs() == 1, "crew occupancy is represented")
	sim.step(1.2)
	check(not sim.get_line(1).fault and sim.get_line(1).closed, "repair finishes after simulated duration")
	check(sim.get_building(2).powered, "repair restores customers")
	check(sim.restored_storms == 1, "storm recovery is tracked")

func _test_determinism_and_save() -> void:
	var first = Sim.new()
	var second = Sim.new()
	first.reset(12345)
	second.reset(12345)
	first.connect_buildings(2, 6)
	second.connect_buildings(2, 6)
	first.step(1.25)
	second.step(1.25)
	first.trigger_storm()
	second.trigger_storm()
	check(JSON.stringify(first.snapshot()) == JSON.stringify(second.snapshot()), "same seed and commands produce identical state")
	var path := "/tmp/tidal-grid-sim-test.json"
	check(first.save_game(path).ok, "snapshot saves to JSON")
	var loaded = Sim.new()
	check(loaded.load_game(path).ok, "snapshot loads successfully")
	check(near(loaded.cash, first.cash), "cash round-trips")
	check(near(loaded.time_hours, first.time_hours), "simulation clock round-trips")
	check(loaded.get_building(1).cell is Vector2i, "grid coordinates restore as Vector2i")
	var visual_keys := {}
	for building in first.buildings:
		visual_keys[building.id] = "existing visual"
	for building in loaded.buildings:
		check(typeof(building.id) == TYPE_INT, "loaded building identifier remains an integer")
		check(typeof(building.level) == TYPE_INT, "loaded building level remains an integer")
		check(visual_keys.has(building.id), "loaded building id matches original renderer dictionary key")
	for line in loaded.lines:
		check(typeof(line.id) == TYPE_INT and typeof(line.a) == TYPE_INT and typeof(line.b) == TYPE_INT and typeof(line.level) == TYPE_INT, "loaded line ids, endpoints and level remain integers")
		check(visual_keys.has(line.a) and visual_keys.has(line.b), "loaded line endpoints resolve renderer dictionary keys")
	first.step(0.7)
	loaded.step(0.7)
	check(near(first.totals.served, loaded.totals.served), "loaded simulation continues identically")
	check(near(first.get_building(9).energy, loaded.get_building(9).energy), "battery state continues identically")
	check(first.rng.state == loaded.rng.state, "random generator state persists")
	var bad_file := FileAccess.open("/tmp/tidal-grid-bad-save.json", FileAccess.WRITE)
	bad_file.store_string('{"schema_version":1,"buildings":[]}')
	bad_file.close()
	var cash_before: float = loaded.cash
	check(not loaded.load_game("/tmp/tidal-grid-bad-save.json").ok, "malformed save is rejected")
	check(near(loaded.cash, cash_before), "invalid load does not mutate current game")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("/tmp/tidal-grid-bad-save.json")

func _test_research_and_objectives() -> void:
	var sim = Sim.new()
	sim.step(0.01)
	check(not sim.has_telemetry(1), "basic network lacks global telemetry")
	check(sim.has_telemetry(8), "smart terminal provides local telemetry")
	check(not sim.demand_response().ok, "demand response requires research")
	check(sim.research().ok and sim.research_level == 1, "first technology researched")
	sim.step(0.01)
	check(sim.has_telemetry(1), "telemetry changes available information")
	check(sim.research().ok and sim.research_level == 2, "second technology researched")
	check(not sim.research().ok, "research is bounded")
	check(sim.objectives[2].done, "smart city objective is reachable")
	sim.connect_buildings(2, 6)
	var demand_before: float = sim.totals.demand
	check(sim.demand_response().ok, "researched demand response executes")
	check(float(sim.totals.demand) < demand_before, "demand response changes physical load")
	check(near(sim.get_building(5).demand, 6.0), "critical medical load is not curtailed")
	var objectives_before: int = sim.objectives.size()
	sim.step(24.0)
	check(sim.day == 2 and sim.objectives.size() == objectives_before, "full day advances without corrupting objectives")
	check(is_finite(sim.cash) and is_finite(sim.totals.generation), "extended deterministic simulation remains finite")

func _test_priority_and_auto_restore() -> void:
	var sim = blank()
	sim._add_building("gas", Vector2i(3, 3))
	sim._add_building("home", Vector2i(5, 3))
	sim._add_building("hospital", Vector2i(5, 5))
	sim._add_line(1, 2)
	sim._add_line(2, 3)
	sim._add_line(1, 3)
	sim.get_building(1).capacity = 5.0
	sim.get_line(3).closed = false
	sim._refresh()
	check(near(sim.get_building(3).served, 5.0), "hospital receives priority during a shortage")
	check(near(sim.get_building(2).served, 0.0), "ordinary load is shed before hospital")
	_assert_kcl(sim)
	sim.get_building(1).capacity = 24.0
	sim.get_line(1).fault = true
	sim.get_line(1).closed = false
	sim._refresh()
	check(near(sim.totals.served, 0.0), "faulted radial supply isolates both loads")
	sim._add_building("control", Vector2i(3, 5))
	sim._add_line(1, 4)
	sim.connect_communication(4, 1)
	sim.connect_communication(1, 2)
	sim.connect_communication(2, 3)
	sim.research_level = 2
	sim.step(0.35)
	check(sim.get_line(3).closed, "self healing closes a healthy standby tie")
	check(near(sim.totals.reliability, 1.0), "self healing restores full supply through alternate path")
	check(sim.get_line(1).fault, "self healing does not erase the physical fault")
	_assert_kcl(sim)
	sim.get_building(1).health = 50.0
	sim.get_building(2).health = 50.0
	sim.get_building(3).health = 50.0
	check(sim.repair(1).ok, "first maintenance crew can dispatch")
	check(sim.repair(2).ok, "second maintenance crew can dispatch")
	check(not sim.repair(3).ok, "crew capacity prevents unlimited concurrent repairs")
	sim.step(0.7)
	check(sim.active_repairs() == 0, "crews return after their jobs finish")

func warning_count(sim: RefCounted) -> int:
	var count := 0
	for entry in sim.log_entries:
		if str(entry.text).begins_with("气象预警"):
			count += 1
	return count

func _test_scheduled_storms_and_compensation() -> void:
	var sim = Sim.new()
	check(near(sim.cash, 180000.0), "forecast system preserves starting funds")
	check(near(sim.totals.storm_in, 6.0), "first natural storm is forecast six hours ahead")
	sim.step(4.9)
	check(sim.storm_count == 0 and warning_count(sim) == 0, "forecast does not warn or damage early")
	sim.step(0.2)
	check(warning_count(sim) == 1 and sim.storm_warning_sent, "one-hour warning is emitted once")
	check(near(sim.totals.storm_in, 0.9), "forecast countdown follows simulated time")
	var path := "/tmp/tidal-grid-forecast-test.json"
	check(sim.save_game(path).ok, "pre-storm forecast can be saved")
	var loaded = Sim.new()
	check(loaded.load_game(path).ok, "pre-storm forecast can be loaded")
	check(loaded.storm_warning_sent and near(loaded.next_storm_at, 6.0), "save retains warning and planned arrival")
	sim.step(0.9)
	loaded.step(0.9)
	check(sim.storm_count == 1 and sim.storm_active, "storm naturally arrives at elapsed hour six")
	check(near(sim.time_hours, 14.0), "first scheduled storm occurs at 14:00 on day one")
	check(int(sim.totals.faults) > 0, "natural storm damages network equipment")
	check(near(sim.next_storm_at, 36.0) and near(sim.totals.storm_in, 30.0), "next natural storm is scheduled thirty hours later")
	check(warning_count(loaded) == 1, "loading a forecast does not repeat its warning")
	check(JSON.stringify(sim.lines) == JSON.stringify(loaded.lines), "saved forecast continues with identical deterministic storm damage")
	check(near(sim.cash, loaded.cash), "saved forecast continues identical economics")
	# Advance to just before the second forecast, repairing first-storm faults
	# so the second event has healthy branches available to damage.
	for line in sim.lines:
		if line.fault:
			sim.repair_line(line.id)
	sim.step(28.0)
	check(sim.storm_count == 1, "second storm does not arrive before its scheduled time")
	sim.step(1.1)
	check(warning_count(sim) == 2, "second storm receives its own advance warning")
	sim.step(0.9)
	check(sim.storm_count == 2 and near(sim.next_storm_at, 66.0), "natural storms recur on the thirty-hour schedule")
	# Older schema 1 snapshots have no forecast fields. They should resume at
	# a future event, without immediately replaying storms from the past.
	var old_data: Dictionary = sim.snapshot()
	old_data.erase("next_storm_at")
	old_data.erase("storm_warning_sent")
	var old_file := FileAccess.open(path, FileAccess.WRITE)
	old_file.store_string(JSON.stringify(old_data))
	old_file.close()
	var legacy = Sim.new()
	check(legacy.load_game(path).ok, "legacy schema 1 saves remain compatible")
	check(legacy.next_storm_at > legacy.elapsed_hours and near(legacy.next_storm_at, 66.0), "legacy save defaults to a safe future storm")
	check(not legacy.storm_warning_sent, "legacy save defaults to an unsent future warning")
	DirAccess.remove_absolute(path)
	var economy = blank()
	economy._add_building("factory", Vector2i(5, 5))
	economy._refresh()
	check(near(economy.totals.outage_cost, 660.0), "unserved MW generates hourly customer compensation")
	check(near(economy.totals.expenses, 669.0), "operating expenses include compensation and maintenance")
	var before: float = economy.cash
	economy.step(0.1)
	check(near(economy.cash, before - 66.9), "outage compensation is actually deducted over time")
	check(near(economy.totals.reliability_lifetime, 0.0), "unserved energy reduces lifetime reliability")
	economy._add_building("gas", Vector2i(6, 5))
	economy._add_line(1, 2)
	economy._refresh()
	check(near(economy.totals.reliability, 1.0), "restoration immediately restores instantaneous reliability")
	check(near(economy.totals.reliability_lifetime, 0.0), "instant restoration does not erase historic interruptions")
	economy.step(0.1)
	check(near(economy.totals.outage_cost, 0.0), "restored supply stops customer compensation")
	check(near(economy.totals.reliability_lifetime, 0.5), "lifetime reliability weights delivered and demanded MWh")
