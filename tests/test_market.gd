extends SceneTree

const Sim = preload("res://scripts/sim/grid_sim.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_test_topology_and_policy()
	_test_merit_order_and_exports()
	_test_storage_and_queries()
	_test_tariffs_and_customers()
	_test_settlement_contracts_and_boundaries()
	_test_save_and_validation()
	print("MARKET TESTS: %d checks; %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func near(a: float, b: float, tolerance: float = 0.00001) -> bool:
	return absf(a - b) <= tolerance

func blank(hour: float = 8.0) -> RefCounted:
	var sim = Sim.new()
	sim.buildings.clear()
	sim.lines.clear()
	sim.objectives.clear()
	sim.digital.reset(sim)
	sim.digital.next_attack_at = 10000.0
	sim.next_building_id = 1
	sim.next_line_id = 1
	sim.cash = 1000000.0
	sim.time_hours = hour
	sim.next_storm_at = 10000.0
	sim.weather = "晴朗"
	return sim

func conservation(sim: RefCounted) -> void:
	check(absf(float(sim.totals.energy_balance_error)) < 0.00001, "global electrical power balances")
	for building in sim.buildings:
		var outgoing := 0.0
		for line in sim.lines:
			if int(line.a) == int(building.id):
				outgoing += float(line.flow)
			if int(line.b) == int(building.id):
				outgoing -= float(line.flow)
		var injection := float(building.output) - float(building.served) - float(building.charging)
		check(near(injection, outgoing), "DC nodal conservation includes signed intertie injections")
		if building.kind == "intertie":
			check(float(building.import_mw) <= 0.00001 or float(building.export_mw) <= 0.00001, "one intertie never buys and sells simultaneously")
			check(absf(float(building.output)) <= float(building.grid_capacity) + 0.00001, "terminal power respects physical connection capacity")
		if building.kind == "battery":
			check(float(building.output) <= 0.00001 or float(building.charging) <= 0.00001, "battery never charges and discharges simultaneously")

func _test_topology_and_policy() -> void:
	var sim = blank()
	sim._add_building("factory", Vector2i(4, 4))
	sim._refresh()
	check(near(sim.totals.import_mw, 0.0) and near(sim.totals.served, 0.0), "a market policy cannot create power without a physical station")
	sim._add_building("intertie", Vector2i(6, 4))
	sim._refresh()
	check(near(sim.totals.import_mw, 0.0) and not sim.get_building(1).powered, "disconnected terminal does not serve another island")
	sim._add_line(1, 2)
	sim._refresh()
	check(near(sim.totals.import_mw, 11.0) and sim.get_building(1).powered, "connected terminal supplies actual demand")
	check(near(sim.get_building(2).output, 11.0), "import is a positive DC injection")
	check(near(sim.totals.generation, 0.0), "wholesale imports are separate from local generation")
	conservation(sim)
	sim.set_market_policy("off")
	check(near(sim.totals.import_mw, 0.0) and near(sim.totals.served, 0.0), "market shutdown stops physical imports")
	sim.set_market_policy("balanced", 1.0)
	check(near(sim.totals.import_mw, 0.0), "buy ceiling blocks expensive emergency power")
	sim.set_market_policy("balanced", 500.0)
	sim._add_building("factory", Vector2i(8, 4))
	sim._add_line(2, 3)
	sim._refresh()
	check(near(sim.totals.import_mw, 14.0), "multiple loads share the terminal rating")
	check(near(sim.totals.served, 14.0), "capacity shortage is represented as real load shedding")
	sim.storm_active = true
	sim._solve(0.0)
	check(near(sim.totals.grid_capacity, 7.7) and near(sim.totals.import_mw, 7.7), "storm derating limits the physical market connection")
	sim.storm_active = false
	sim.get_building(2).online = false
	sim._refresh()
	check(near(sim.totals.import_mw, 0.0), "offline intertie cannot import")
	sim.get_building(2).online = true
	sim.get_line(1).closed = false
	sim._refresh()
	check(not sim.get_building(1).powered and sim.get_building(3).powered, "breaker topology determines which loads receive traded energy")
	sim.get_line(2).capacity = 3.0
	sim.step(0.2)
	check(not sim.get_line(2).closed and near(sim.totals.import_mw, 0.0), "overloaded market feeder trips and prevents virtual delivery")
	conservation(sim)

func _test_merit_order_and_exports() -> void:
	var sim = blank(2.0)
	sim._add_building("gas", Vector2i(3, 4))
	sim._add_building("factory", Vector2i(5, 4))
	sim._add_building("intertie", Vector2i(7, 4))
	sim._add_line(1, 2)
	sim._add_line(2, 3)
	sim._refresh()
	check(float(sim.totals.gas_output) > 0.0 and near(sim.totals.import_mw, 0.0), "balanced strategy uses local dispatch before spot imports")
	sim.set_market_policy("trade", 500.0, 500.0)
	check(near(sim.totals.gas_output, 0.0) and float(sim.totals.import_mw) > 0.0, "trading substitutes cheap imports for fuel")
	check(float(sim.totals.market_price) < 68.0, "off-peak market price is cheaper than gas")
	conservation(sim)
	sim.time_hours = 18.0
	sim.set_market_policy("trade", 500.0, 0.0)
	check(near(sim.totals.gas_output, 24.0), "peak exports use only gas capacity left after serving local load")
	check(near(sim.totals.export_mw, 13.0) and near(sim.totals.import_mw, 0.0), "gas spare capacity is sold without simultaneous purchases")
	check(near(sim.totals.fuel_cost, 24.0 * 68.0) and near(sim.totals.carbon, 24.0 * 0.38), "merchant gas incurs real fuel and emissions")
	check(near(sim.get_building(2).served, 11.0), "local customers have priority over lucrative exports")
	sim._configure_facility_now(1, {"dispatch":0.5})
	check(near(sim.totals.gas_output, 12.0) and near(sim.totals.export_mw, 1.0), "merchant dispatch respects the player output limit")
	sim._configure_facility_now(1, {"dispatch":0.25})
	check(near(sim.totals.export_mw, 0.0) and near(sim.totals.import_mw, 5.0), "insufficient local generation is not simultaneously exported")
	conservation(sim)
	sim.time_hours = 12.0
	sim._configure_facility_now(1, {"dispatch":1.0})
	check(float(sim.market.state.export_price) < 68.0 and near(sim.totals.export_mw, 0.0), "gas is not sold below its fuel cost")
	var solar = blank(12.0)
	solar._add_building("solar", Vector2i(3, 4))
	solar._add_building("intertie", Vector2i(5, 4))
	solar._add_building("hospital", Vector2i(7, 4))
	solar._add_line(1, 2)
	solar._add_line(2, 3)
	solar.set_market_policy("trade", 500.0, 0.0)
	check(near(solar.totals.export_mw, 6.0), "renewable surplus can be exported")
	check(near(solar.get_building(2).output, -6.0), "exports are negative terminal injections")
	check(near(solar.totals.curtailment_mw, 0.0), "sold renewable production is not curtailed")
	conservation(solar)
	solar.set_market_policy("trade", 500.0, 500.0)
	check(near(solar.totals.export_mw, 0.0) and near(solar.totals.curtailment_mw, 6.0), "sell floor rejects low offers and curtails the remaining renewable power")
	solar.set_market_policy("balanced", 500.0, 0.0)
	check(near(solar.totals.export_mw, 0.0), "balanced policy keeps surplus rather than making merchant offers")

func _test_storage_and_queries() -> void:
	var sim = blank(2.0)
	sim._add_building("battery", Vector2i(3, 3))
	sim._add_building("intertie", Vector2i(5, 3))
	sim._add_line(1, 2)
	sim.get_building(1).energy = 6.0
	sim.set_market_policy("trade", 120.0, 90.0)
	sim.set_storage_policy("arbitrage", 60.0, 150.0, 0.2)
	check(near(sim.get_building(1).charging, 10.0) and near(sim.totals.import_mw, 10.0), "arbitrage charges from real cheap imports")
	var initial_energy: float = sim.get_building(1).energy
	var initial_cash: float = sim.cash
	var initial_satisfaction: float = sim.market.state.satisfaction
	for _index in 30:
		sim._solve(0.0)
		sim.market_forecast()
	check(near(sim.get_building(1).energy, initial_energy), "zero-time dispatch queries cannot create or consume MWh")
	check(near(sim.cash, initial_cash) and sim.market.ledger.is_empty(), "UI queries never settle cash or daily bills")
	check(near(sim.market.state.satisfaction, initial_satisfaction), "UI queries never change customer sentiment")
	sim.step(1.0)
	check(near(sim.get_building(1).energy, 15.4), "one hour of 10 MW charging stores exactly 9.4 MWh")
	check(near(sim.market.ledger[0].import_mwh, 10.0), "charging imports appear in the MWh ledger")
	check(float(sim.market.ledger[0].import_cost) > 0.0, "arbitrage energy is purchased rather than created for free")
	sim.time_hours = 18.0
	sim._refresh()
	check(float(sim.totals.export_mw) > 0.0, "stored power can be sold when the spot threshold is exceeded")
	var bought_cost: float = sim.market.ledger[0].import_cost
	sim.step(1.0)
	check(near(sim.get_building(1).energy, 6.0), "arbitrage preserves the configured reserve SOC")
	check(near(sim.market.ledger[0].export_mwh, 9.4 * 0.94), "sold energy includes charge and discharge efficiency losses")
	check(float(sim.market.ledger[0].export_revenue) > bought_cost, "cross-time spread can produce a positive gross storage margin")
	conservation(sim)
	sim.get_line(1).closed = false
	sim.time_hours = 2.0
	sim._refresh()
	check(near(sim.totals.import_mw, 0.0) and near(sim.get_building(1).charging, 0.0), "detached storage cannot buy virtual charging energy")
	check(not sim.set_storage_policy("arbitrage", 200.0, 150.0, 0.2).ok, "inverted storage thresholds are rejected")
	check(not sim.set_storage_policy("arbitrage", 60.0, 150.0, 1.2).ok, "invalid reserve fraction is rejected")
	var rows: Array = sim.market_forecast()
	check(rows.size() == 24, "market forecast returns 24 hourly entries")
	sim.time_hours = 23.0
	rows = sim.market_forecast()
	check(rows[1].day == sim.day + 1 and near(rows[1].hour, 0.0), "price forecast rolls over midnight")

func _test_tariffs_and_customers() -> void:
	var sim = blank(8.0)
	sim._add_building("home", Vector2i(3, 3))
	sim._add_building("factory", Vector2i(5, 3))
	sim._add_building("hospital", Vector2i(7, 3))
	sim._add_building("gas", Vector2i(5, 5))
	for id in [1, 2, 3]:
		sim._add_line(4, id)
	sim._refresh()
	var normal: float = sim.totals.demand
	var normal_revenue: float = sim.totals.retail_income
	var normal_net: float = sim.totals.income - sim.totals.expenses
	sim.set_tariff("flat", 85.0, 500.0, 220.0)
	check(float(sim.totals.demand) < normal, "high tariff reduces flexible residential and industrial demand")
	check(near(sim.get_building(3).demand, 6.0), "hospital demand is protected from price elasticity")
	check(float(sim.totals.retail_income) > normal_revenue, "high tariff initially increases revenue as a tempting tradeoff")
	var expected := (float(sim.get_building(1).served) + float(sim.get_building(2).served)) * 500.0 + 6.0 * 145.0
	check(near(sim.totals.retail_income, expected), "medical power is billed at the regulated 145 ceiling")
	sim.step(24.0)
	check(float(sim.market.state.satisfaction) < 5.0, "sustained excessive bills sharply reduce satisfaction")
	# Compare at the same day and demand profile, isolating the tariff choice.
	sim.time_hours = 8.0
	sim._refresh()
	var high_net: float = sim.totals.income - sim.totals.expenses
	var fair = blank(8.0)
	fair.day = sim.day
	fair._add_building("home", Vector2i(3, 3))
	fair._add_building("factory", Vector2i(5, 3))
	fair._add_building("hospital", Vector2i(7, 3))
	fair._add_building("gas", Vector2i(5, 5))
	for id in [1, 2, 3]:
		fair._add_line(4, id)
	fair._refresh()
	check(high_net < float(fair.totals.income - fair.totals.expenses) * 0.90, "maximum tariff has significantly worse long-run operating profit than a fair tariff")
	check(normal_net > 0.0, "default tariff remains commercially viable")
	check(near(sim.market.demand_multiplier("home"), 0.1375, 0.02), "dissatisfied ordinary users can leave the service area")
	sim.set_tariff("tou")
	for pair in [[2.0, 85.0], [8.0, 145.0], [18.0, 220.0], [23.0, 85.0]]:
		sim.time_hours = pair[0]
		sim._refresh()
		check(near(sim.market.state.retail_price, pair[1]), "time-of-use price follows valley/flat/peak bands")
	check(not sim.set_tariff("flat", 85.0, NAN, 220.0).ok, "NaN tariffs are rejected")
	check(not sim.set_market_policy("trade", INF, 0.0).ok, "infinite market thresholds are rejected")

func _test_settlement_contracts_and_boundaries() -> void:
	var sim = blank(8.0)
	sim._add_building("intertie", Vector2i(3, 3))
	sim._add_building("factory", Vector2i(5, 3))
	sim._add_line(1, 2)
	sim.set_market_policy("balanced", 500.0)
	check(not sim.sign_supply_contract(15.0).ok and not sim.sign_supply_contract(0.0).ok, "contract volume must be positive and within physical capacity")
	check(sim.sign_supply_contract(5.0, 1.0).ok, "valid supply agreement can be signed")
	var locked: float = sim.market.state.contract_price
	check(not sim.sign_supply_contract(1.0, 1.0).ok, "active contracts cannot be replaced or cancelled")
	check(near(sim.totals.contract_import_mw, 5.0), "contract delivery is allocated to actual demand")
	check(near(sim.totals.import_mw, 11.0), "spot market covers demand above the contract")
	check(near(sim.totals.import_cost, 6.0 * float(sim.market.state.spot_price)), "only volume above the contract pays spot settlement")
	var cash_before: float = sim.cash
	sim.step(1.0)
	check(near(sim.market.ledger[0].contract_cost, 5.0 * locked), "take-or-pay commitment is settled exactly once over its actual duration")
	check(near(sim.market.state.contract_remaining, 0.0) and near(sim.market.state.contract_mw, 0.0), "contract expires after its duration")
	check(near(sim.cash - cash_before, sim.market.ledger[0].net), "daily net ledger reconciles with real cash movements")
	check(near(sim.market.ledger[0].import_mwh, 11.0), "physical imported MWh reconcile with one hour of served load")
	var isolated = blank(18.0)
	isolated._add_building("intertie", Vector2i(3, 3))
	isolated._add_building("factory", Vector2i(5, 3))
	isolated._add_line(1, 2)
	isolated.set_market_policy("trade", 500.0, 0.0)
	check(isolated.sign_supply_contract(5.0, 1.0).ok, "peak-period one-hour contract can be signed")
	var peak_quote: float = isolated.market.state.contract_price
	check(peak_quote > 180.0, "short peak contract uses its actual term rather than a cheap twelve-hour average")
	isolated.get_line(1).closed = false
	isolated._refresh()
	check(near(isolated.totals.import_mw, 0.0) and near(isolated.totals.export_mw, 0.0), "disconnected contract delivery cannot create or resell energy")
	isolated.step(1.0)
	check(near(isolated.market.ledger[0].contract_cost, 5.0 * peak_quote), "disconnected and unused commitment is still paid")
	var no_station = blank()
	check(not no_station.sign_supply_contract(1.0).ok, "contract requires an installed physical terminal")
	var boundary = blank(16.9)
	boundary._add_building("factory", Vector2i(3, 3))
	boundary._add_building("gas", Vector2i(5, 3))
	boundary._add_line(1, 2)
	boundary.set_tariff("tou")
	boundary.step(0.2)
	var peak_demand := 11.0 * (1.0 - (220.0 / 145.0 - 1.0) * 0.30)
	var expected_revenue := 11.0 * 145.0 * 0.1 + peak_demand * 220.0 * 0.1
	check(near(boundary.market.ledger[0].retail_revenue, expected_revenue), "crossing 17:00 settles each side at its own exact tariff")
	var midnight = blank(23.9)
	midnight._add_building("hospital", Vector2i(3, 3))
	midnight._add_building("gas", Vector2i(5, 3))
	midnight._add_line(1, 2)
	midnight._refresh()
	midnight.step(0.2)
	check(midnight.market.ledger.size() == 2, "daily settlement opens a new ledger at midnight")
	check(midnight.market.ledger[0].day == 1 and midnight.market.ledger[1].day == 2, "bill dates are consecutive")
	check(near(midnight.market.ledger[0].served_mwh, 0.6) and near(midnight.market.ledger[1].served_mwh, 0.615), "midnight interval is split without losing or double-counting MWh")

func _test_save_and_validation() -> void:
	var sim = blank(2.0)
	sim._add_building("intertie", Vector2i(3, 3))
	sim._add_building("battery", Vector2i(5, 3))
	sim._add_building("factory", Vector2i(7, 3))
	sim._add_line(1, 2)
	sim._add_line(2, 3)
	sim.set_market_policy("trade", 120.0, 90.0)
	sim.set_storage_policy("arbitrage")
	sim.set_tariff("custom", 70.0, 150.0, 240.0)
	sim.sign_supply_contract(8.0, 12.0)
	sim.step(0.25)
	var path := "user://test_tidal-grid-market-test.json"
	check(sim.save_game(path).ok and Sim.SCHEMA_VERSION == 5, "market snapshot uses current schema")
	var restored = Sim.new()
	check(restored.load_game(path).ok, "market snapshot loads")
	check(JSON.stringify(sim.market.state) == JSON.stringify(restored.market.state), "all pricing, sentiment, contract and storage policies round-trip")
	check(JSON.stringify(sim.market.ledger) == JSON.stringify(restored.market.ledger), "daily market ledger round-trips")
	sim.step(0.6)
	restored.step(0.6)
	check(near(sim.cash, restored.cash) and near(sim.get_building(2).energy, restored.get_building(2).energy), "loaded market continues deterministic cash and storage dispatch")
	check(JSON.stringify(sim.market.ledger) == JSON.stringify(restored.market.ledger), "continued market bills remain deterministic")
	var old: Dictionary = sim.snapshot()
	old.schema_version = 1
	old.erase("market")
	write_json(path, old)
	check(restored.load_game(path).ok, "schema-one saves without market data remain supported")
	check(restored.market.state.tariff_mode == "flat" and near(restored.market.state.flat_rate, 145.0) and restored.market.ledger.is_empty(), "legacy saves receive safe default market policies")
	var before := JSON.stringify(restored.snapshot(), "", true, true)
	var valid: Dictionary = restored.snapshot()
	var attacks: Array[Dictionary] = []
	var attack: Dictionary = valid.duplicate(true)
	attack.market.state.flat_rate = "500"
	attacks.append(attack)
	attack = valid.duplicate(true)
	attack.market.state.reserve_soc = 1.2
	attacks.append(attack)
	attack = valid.duplicate(true)
	attack.market.state.market_mode = "unlimited"
	attacks.append(attack)
	attack = valid.duplicate(true)
	attack.market.state.contract_remaining = 12.0
	attack.market.state.contract_mw = -4.0
	attacks.append(attack)
	attack = valid.duplicate(true)
	attack.buildings[0].capacity = -14.0
	attacks.append(attack)
	attack = valid.duplicate(true)
	attack.buildings[1].id = attack.buildings[0].id
	attacks.append(attack)
	attack = valid.duplicate(true)
	attack.buildings[1].energy = 300.0
	attacks.append(attack)
	attack = valid.duplicate(true)
	attack.lines[0].a = 99999
	attacks.append(attack)
	attack = valid.duplicate(true)
	attack.cash = null
	attacks.append(attack)
	attack = valid.duplicate(true)
	attack.market.ledger = [{"day": 1}]
	attacks.append(attack)
	for invalid in attacks:
		write_json(path, invalid)
		check(not restored.load_game(path).ok, "malformed world or market save is rejected")
		check(JSON.stringify(restored.snapshot(), "", true, true) == before, "invalid load leaves the entire live simulation unchanged")
	DirAccess.remove_absolute(path)

func write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "", true, true))
	file.close()
