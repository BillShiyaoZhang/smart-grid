extends SceneTree
## Public construction/demolition must remain in the city/economy feedback loop.
const Sim = preload("res://scripts/sim/grid_sim.gd")
const Region = preload("res://scripts/sim/region_world.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_test_manual_customers()
	_test_municipal_assets()
	_test_expansion_and_registration()
	_test_municipal_upgrade_investment()
	_test_persistence_and_migration()
	_test_legacy_save_migration()
	_test_legacy_metadata_is_not_trusted()
	print("CITY ASSETS TESTS: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: "+message)

func prepared() -> RefCounted:
	var sim = Sim.new()
	sim.cash = 1000000.0
	sim.next_storm_at = 100000.0
	sim.digital.next_attack_at = 100000.0
	sim.evolution.unlocked.assign(sim.evolution.TECHNOLOGIES.keys())
	sim.expand_region()
	return sim

func _test_manual_customers() -> void:
	var sim = prepared()
	var city: Dictionary = sim.region.cities[1]
	var result: Dictionary = sim.build("home",Vector2i(25,7))
	check(result.ok,"player can build a residential block beside a regional town")
	if not result.ok: return
	var home: Dictionary = sim.get_building(int(result.id))
	check(home.get("city_id",-1)==1 and int(home.id) in city.building_ids,"manual construction registers city and reciprocal membership")
	var baseline: float = sim.region.demand_multiplier(home)
	city.population = float(city.base_population)*2.0
	check(is_equal_approx(sim.region.demand_multiplier(home),baseline*2.0),"manual residential demand follows its city's population")
	city.population = city.base_population
	var generator: Dictionary = sim.build("gas",Vector2i(26,7))
	check(generator.ok,"regional service fixture has a real local generator")
	if not generator.ok: return
	sim.connect_buildings(int(generator.id),int(city.building_ids[0]))
	var feeder: Dictionary = sim.connect_buildings(int(generator.id),int(home.id))
	check(feeder.ok and home.powered,"manual residential block is supplied through its real branch")
	city.service = 1.0
	sim.toggle_line(int(feeder.id))
	sim.step(1.0)
	check(not home.powered and float(sim.get_building(int(city.building_ids[0])).served)>0.0,"only the new residential feeder is interrupted")
	check(float(city.service)<0.99,"manual customer's blackout reduces the town's service quality")
	var auxiliary: Dictionary = sim.build("cooling",Vector2i(27,7))
	check(auxiliary.ok and not sim.get_building(int(auxiliary.id)).has("city_id"),"industrial auxiliaries do not become population-scaled city customers")
	var before_size: int = city.building_ids.size()
	sim.region.register_building(sim,home)
	sim.region.register_building(sim,home)
	check(city.building_ids.size()==before_size,"repeated registration never duplicates customer demand")

func _test_municipal_assets() -> void:
	var sim = prepared()
	var initial_cash: float = sim.cash
	var ids: Array[int] = []
	for building in sim.buildings:
		if int(building.id)>10: ids.append(int(building.id))
	check(ids.size()==14,"region provides fourteen inherited customer assets")
	for id in ids:
		var building: Dictionary = sim.get_building(id)
		check(building.get("ownership","")=="municipal" and is_zero_approx(float(building.get("refund_basis",-1))),"inherited asset has no player-funded refund basis")
	var city: Dictionary = sim.region.cities[1]
	city.service = 1.0
	city.prosperity = 0.9
	var people: float = city.population
	for id in ids: sim.demolish(id)
	check(is_equal_approx(sim.cash,initial_cash),"demolishing inherited regional assets cannot mint player cash")
	check(float(city.population)<people and float(city.prosperity)<0.9,"urban demolition has a bounded population and prosperity consequence")
	check(float(city.get("displaced_demand",0.0))>0.0,"demolition leaves displaced demand awaiting replacement")
	sim.region.advance(sim,3.0)
	check(float(city.service)<0.5,"removing every town building cannot erase its unmet service obligation")
	var debt: float = city.displaced_demand
	var replacement: Dictionary = sim.build("home",Vector2i(24,6))
	check(replacement.ok and float(city.displaced_demand)<debt,"new customer construction rehousing residents repays displaced demand")
	var player_cash: float = sim.cash
	var player_basis: float = sim.get_building(int(replacement.id)).refund_basis
	sim.demolish(int(replacement.id))
	check(is_equal_approx(sim.cash,player_cash+player_basis*0.35),"player-funded construction retains its documented partial refund")

func _test_expansion_and_registration() -> void:
	var sim = prepared()
	var city: Dictionary = sim.region.cities[1]
	var count: int = city.building_ids.size()
	sim.region._expand(sim,city)
	check(city.building_ids.size()==count+1,"automatic expansion shares the single registration path")
	var expanded: Dictionary = sim.get_building(int(city.building_ids[-1]))
	check(expanded.get("ownership","")=="municipal" and is_zero_approx(float(expanded.refund_basis)),"automatically generated buildings have no refundable investment")
	var linked := false
	for line in sim.lines:
		check(int(line.a)!=int(line.b),"registration before feeder construction never creates self-loops")
		if int(line.a)==int(expanded.id) or int(line.b)==int(expanded.id): linked=true
	check(linked,"automatic expansion connects the new block to an existing city node")
	var cash: float = sim.cash
	sim.demolish(int(expanded.id))
	check(is_equal_approx(sim.cash,cash),"demolishing automatic expansion grants no free refund")

func _test_municipal_upgrade_investment() -> void:
	var sim = prepared()
	var building: Dictionary = sim.get_building(int(sim.region.cities[1].building_ids[0]))
	var initial: float = sim.cash
	var price: float = sim.catalog[building.kind].price*0.65
	check(sim.upgrade(int(building.id)).ok,"player may invest in upgrading a municipal customer asset")
	check(is_equal_approx(float(building.refund_basis),price) and is_equal_approx(float(building.invested_capital),price),"municipal upgrade records only the actual additional player investment")
	var path := "user://test_city_upgrade_asset.json"
	check(sim.save_game(path).ok,"municipal upgrade investment saves")
	var restored = Sim.new()
	check(restored.load_game(path).ok,"municipal upgrade investment restores")
	var cash: float = restored.cash
	check(restored.demolish(int(building.id)).ok and is_equal_approx(restored.cash,cash+price*0.35),"only player-funded upgrade capital is refundable after load")
	check(restored.cash<initial,"upgrading then demolishing inherited assets always loses money")
	DirAccess.remove_absolute(path)

func _test_legacy_save_migration() -> void:
	var sim = prepared()
	var inherited_id: int = sim.region.cities[1].building_ids[0]
	check(sim.upgrade(inherited_id).ok,"legacy migration fixture includes a paid municipal upgrade")
	var manual: Dictionary = sim.build("home",Vector2i(25,7))
	check(manual.ok,"legacy migration fixture includes an unregistered manual customer")
	if not manual.ok: return
	var data: Dictionary = sim.snapshot()
	data.schema_version = 4
	for building in data.buildings:
		for field in ["ownership","invested_capital","refund_basis","renewable_energy_mwh"]: building.erase(field)
		if int(building.id)==int(manual.id): building.erase("city_id")
	for city in data.region.cities:
		city.erase("displaced_demand")
		city.building_ids.erase(int(manual.id))
	var path := "user://test_city_legacy_assets.json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var restored = Sim.new()
	check(restored.load_game(path).ok,"schema4 regional assets migrate through the real loader")
	var inherited: Dictionary = restored.get_building(inherited_id)
	var cost: float = sim.catalog[inherited.kind].price*0.65
	check(inherited.get("ownership","")=="municipal" and is_equal_approx(float(inherited.get("refund_basis",-1)),cost),"loader preserves municipal paid upgrades without refunding inherited base")
	check(restored.get_building(int(manual.id)).get("city_id",-1)==1 and int(manual.id) in restored.region.cities[1].building_ids,"loader attaches previously unregistered construction to its nearest city")
	check(is_equal_approx(restored.cash,sim.cash),"legacy registration and ownership migration never changes cash")
	check(restored.save_game(path).ok and Sim.new().load_game(path).ok,"migrated registration round-trips as a strict new save")
	DirAccess.remove_absolute(path)

func _test_legacy_metadata_is_not_trusted() -> void:
	var sim = Sim.new()
	var legacy: Dictionary = sim.snapshot()
	legacy.schema_version = 4
	legacy.buildings[0].ownership = "untrusted_future_role"
	legacy.buildings[0].invested_capital = 1.0
	legacy.buildings[0].refund_basis = 1000000.0
	legacy.buildings[0].renewable_energy_mwh = 1000000.0
	var path := "user://test_city_legacy_untrusted_metadata.json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	var restored = Sim.new()
	check(restored.load_game(path).ok,"legacy files may carry unknown future fields without corrupting migration")
	var generator: Dictionary = restored.get_building(1)
	var base: float = sim.catalog.gas.price
	check(generator.get("ownership","")=="player","legacy ownership is derived rather than trusting unvalidated future metadata")
	check(is_equal_approx(float(generator.get("invested_capital",-1)),base) and is_equal_approx(float(generator.get("refund_basis",-1)),base),"legacy future refund fields cannot inflate invested capital or demolition proceeds")
	check(is_zero_approx(float(generator.get("renewable_energy_mwh",-1))),"legacy future energy provenance is initialized conservatively")
	check(restored._valid_save(restored.snapshot()),"canonical migration produces a valid strict schema5 state")
	check(restored.save_game(path).ok and Sim.new().load_game(path).ok,"canonical migrated assets can be saved and loaded again")
	var cash: float = restored.cash
	restored.demolish(1)
	check(is_equal_approx(restored.cash-cash,base*0.35),"forged legacy metadata cannot produce an inflated refund")
	DirAccess.remove_absolute(path)

func _test_persistence_and_migration() -> void:
	var sim = prepared()
	var result: Dictionary = sim.build("factory",Vector2i(25,7))
	check(result.ok,"manual industrial asset exists for round-trip validation")
	if not result.ok: return
	var id: int = result.id
	sim.demolish(int(sim.region.cities[1].building_ids[0]))
	var debt: float = sim.region.cities[1].displaced_demand
	var path := "user://test_city_assets.json"
	check(sim.save_game(path).ok,"city registration and displacement save")
	var restored = Sim.new()
	check(restored.load_game(path).ok,"city registration and displacement restore")
	check(restored.get_building(id).get("city_id",-1)==1 and id in restored.region.cities[1].building_ids,"manual customer membership persists reciprocally")
	check(is_equal_approx(float(restored.region.cities[1].get("displaced_demand",0.0)),debt),"displaced service obligation cannot be reset by loading")
	var asset: Dictionary = restored.get_building(id)
	check(asset.get("ownership","")=="player" and float(asset.refund_basis)>0.0,"actual investment basis survives round trip")
	# Restore legacy state that predates registration and asset provenance.
	asset.erase("city_id")
	restored.region.cities[1].building_ids.erase(id)
	var municipal: Dictionary = restored.get_building(int(restored.region.cities[1].building_ids[0]))
	municipal.ownership = "player"
	municipal.invested_capital = 8000.0
	municipal.refund_basis = 8000.0
	restored.region.reconcile_buildings(restored,true)
	check(asset.get("city_id",-1)==1 and id in restored.region.cities[1].building_ids,"legacy unregistered player construction joins the nearest town")
	check(municipal.ownership=="municipal" and is_zero_approx(float(municipal.refund_basis)),"legacy generated blocks migrate without refundable player capital")
	municipal.level = 2
	municipal.ownership = "player"
	restored.region.reconcile_buildings(restored,true)
	var upgrade_cost: float = restored.catalog[municipal.kind].price*0.65
	check(municipal.ownership=="municipal" and is_equal_approx(float(municipal.refund_basis),upgrade_cost),"legacy municipal upgrade costs survive while the free inherited base remains nonrefundable")
	var invalid: Dictionary = restored.region.snapshot()
	invalid.cities[0].displaced_demand = -1.0
	check(not Region.valid_snapshot(invalid),"invalid displacement is rejected without changing city state")
	var ids: Dictionary = {}
	for building in restored.buildings: ids[int(building.id)] = building
	invalid = restored.region.snapshot()
	invalid.cities[1].building_ids.erase(id)
	check(not Region.valid_snapshot(invalid,ids,true),"new saves reject a customer missing reciprocal city membership")
	check(Region.valid_snapshot(invalid,ids),"legacy validation accepts missing registration for explicit migration")
	DirAccess.remove_absolute(path)
