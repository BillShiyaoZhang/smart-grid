extends SceneTree
const Region = preload("res://scripts/sim/region_world.gd")
const Sim = preload("res://scripts/sim/grid_sim.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_test_activation_and_feedback()
	_test_growth_decline_and_expansion()
	_test_roles_and_limits()
	_test_persistence_and_pure_queries()
	print("REGION TESTS: %d checks; %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func prepared() -> RefCounted:
	var sim = Sim.new()
	sim.next_storm_at = 100000.0
	sim.digital.next_attack_at = 100000.0
	return sim

func _set_delivery(sim: RefCounted, city: Dictionary, ratio: float) -> void:
	for id in city.building_ids:
		var building: Dictionary = sim.get_building(int(id))
		building.demand = 4.0
		building.served = 4.0 * ratio

func _test_activation_and_feedback() -> void:
	var sim = prepared()
	var region = Region.new()
	var before_cash: float = sim.cash
	check(not region.active and region.cities.is_empty(), "region starts opt-in without altering the guided opening")
	# A player's footprint at a town anchor must be preserved.
	var obstacle: Dictionary = sim._add_building("solar", Vector2i(24, 6))
	check(region.activate(sim).ok, "region activates with a player facility near a future town")
	check(region.cities.size() == 8 and sim.buildings.size() == 25, "seven two-node satellites extend the original city")
	check(sim.building_at(Vector2i(24, 6)).id == obstacle.id, "city placement never overwrites existing player construction")
	check(is_equal_approx(sim.cash, before_cash), "town creation does not give the player free cash")
	check(not region.activate(sim).ok and sim.buildings.size() == 25, "region activation is idempotent and cannot duplicate towns")
	sim._solve(0.0)
	var satellite: Dictionary = region.cities[1]
	var first: Dictionary = sim.get_building(int(satellite.building_ids[0]))
	check(not first.powered and first.demand > 0.0, "satellite residents have real unserved electrical demand")
	var internal_links := 0
	for line in sim.lines:
		if int(line.a) in satellite.building_ids and int(line.b) in satellite.building_ids:
			internal_links += 1
	check(internal_links == 1, "each new town has an internal feeder but no free generating connection")
	check(region.summary().population > 15000.0, "regional summary includes all town populations")
	region.advance(sim, 1.0)
	check(region.cities[1].service == 0.0, "unconnected towns do not report invented service")

func _test_growth_decline_and_expansion() -> void:
	var sim = prepared()
	var region = Region.new()
	region.activate(sim)
	sim.market.state.retail_price = 90.0
	var growing: Dictionary = region.cities[1]
	var declining: Dictionary = region.cities[2]
	growing.service = 1.0
	growing.prosperity = 0.9
	var population_before: float = growing.population
	var declined_before: float = declining.population
	for _hour in 24:
		_set_delivery(sim, growing, 1.0)
		_set_delivery(sim, declining, 0.0)
		region.advance(sim, 1.0)
	check(float(growing.population) > population_before and growing.growth > 0.0, "affordable reliable electricity attracts residents")
	check(float(declining.population) < declined_before and declining.growth < 0.0, "sustained electricity shortage leads to population decline")
	check("外流" in str(declining.trend), "decline explains its cause in city feedback")
	var multiplier_before: float = region.demand_multiplier(sim.get_building(growing.building_ids[0]))
	growing.population = float(growing.base_population) * 1.20
	var buildings_before: int = sim.buildings.size()
	for _hour in 6:
		_set_delivery(sim, growing, 1.0)
		region.advance(sim, 1.0)
	check(int(growing.expansions) == 1 and sim.buildings.size() > buildings_before, "a thriving larger population expands the town spatially")
	check(region.demand_multiplier(sim.get_building(growing.building_ids[0])) > multiplier_before, "population growth feeds back into real per-building electricity demand")
	var expanded: Dictionary = sim.get_building(int(growing.building_ids[-1]))
	check(int(expanded.city_id) == int(growing.id) and expanded.cell != growing.anchor, "new urban blocks retain their city membership and occupy distinct cells")
	var linked := false
	for line in sim.lines:
		if int(line.a) == expanded.id or int(line.b) == expanded.id:
			linked = true
	check(linked, "urban expansion grows a local feeder without granting regional power")

func _test_roles_and_limits() -> void:
	var sim = prepared()
	var region = Region.new()
	region.activate(sim)
	var farm: Dictionary = region.cities[1]
	var factory: Dictionary = sim.get_building(int(farm.building_ids[1]))
	region.current_hour = 7.0
	var irrigation: float = region.demand_multiplier(factory)
	region.current_hour = 15.0
	check(irrigation > region.demand_multiplier(factory), "agricultural towns concentrate productive demand in the morning")
	var port: Dictionary = region.cities[2]
	var dock: Dictionary = sim.get_building(int(port.building_ids[1]))
	region.current_hour = 22.0
	var night_port: float = region.demand_multiplier(dock)
	region.current_hour = 12.0
	check(night_port > region.demand_multiplier(dock), "port specialization has a different demand curve from agriculture")
	var candidate: Dictionary = region.cities[4]
	candidate.service = 1.0
	candidate.prosperity = 0.95
	sim.market.state.retail_price = 85.0
	for _hour in 50:
		_set_delivery(sim, candidate, 1.0)
		region.advance(sim, 1.0)
	check(candidate.specialization == "工业", "sustained cheap reliable energy can attract industry to a residential town")
	candidate.population = float(candidate.base_population) * 2.0
	candidate.expansions = Region.MAX_EXPANSIONS
	var before: int = sim.buildings.size()
	for _hour in 12:
		_set_delivery(sim, candidate, 1.0)
		region.advance(sim, 1.0)
	check(sim.buildings.size() == before, "mature towns respect the spatial expansion cap")
	var id := int(farm.building_ids[0])
	sim.buildings.erase(sim.get_building(id))
	region.prune(sim)
	check(id not in farm.building_ids, "demolished urban blocks are pruned before saving")

func _test_persistence_and_pure_queries() -> void:
	var sim = prepared()
	var region = Region.new()
	region.activate(sim)
	var before := JSON.stringify(region.snapshot(), "", true, true)
	var cash: float = sim.cash
	for _index in 50:
		region.summary()
		region.city_status(1)
		region.demand_multiplier(sim.get_building(11))
	check(JSON.stringify(region.snapshot(), "", true, true) == before, "status and demand queries do not grow cities or advance demographic time")
	check(is_equal_approx(sim.cash, cash), "regional reads cannot settle money")
	var data: Variant = JSON.parse_string(before)
	var restored = Region.new()
	check(restored.load_snapshot(data), "regional state survives JSON round trip")
	check(JSON.stringify(restored.snapshot(), "", true, true) == before, "round trip preserves all demographic and specialization state")
	region.advance(sim, 0.25)
	restored.advance(sim, 0.25)
	check(JSON.stringify(restored.snapshot(), "", true, true) == JSON.stringify(region.snapshot(), "", true, true), "loaded city evolution remains deterministic")
	var malformed: Dictionary = data.duplicate(true)
	malformed.cities[0].population = NAN
	check(not restored.load_snapshot(malformed), "nonfinite demographic saves are rejected")
	malformed = data.duplicate(true)
	malformed.cities[1].building_ids.append(malformed.cities[0].building_ids[0])
	check(not Region.valid_snapshot(malformed), "a building cannot belong to two saved towns")
	malformed = data.duplicate(true)
	malformed.cities[0].id = 0.5
	check(not Region.valid_snapshot(malformed), "fractional city identities are rejected")
	var stable := JSON.stringify(restored.snapshot(), "", true, true)
	malformed.cities[0].specialization = "invalid"
	check(not restored.load_snapshot(malformed) and JSON.stringify(restored.snapshot(), "", true, true) == stable, "invalid city loads leave the current region unchanged")
	var inactive = Region.new()
	check(Region.valid_snapshot(inactive.snapshot()), "an inactive region is also a valid persistent state")
