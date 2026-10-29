extends SceneTree
## Cross-system boundaries use the public simulation entrypoints and isolated files.
const Sim = preload("res://scripts/sim/grid_sim.gd")
const Campaign = preload("res://scripts/sim/campaign.gd")
const QA_DIR := "res://.godot/campaign-qa"
var checks := 0
var failures := 0

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(QA_DIR)
	_test_era_boundaries()
	_test_fixed_external_supply()
	_test_remote_without_auto_restore()
	_test_unknown_observations()
	_test_natural_events_disabled()
	_test_all_chapter_persistence()
	_test_legacy_and_invalid_saves()
	print("CAMPAIGN BOUNDARY TESTS: %d checks; %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _chapter(id: int) -> RefCounted:
	var sim = Sim.new()
	check(sim.start_campaign(id).ok, "chapter %d starts through the real public API" % id)
	return sim

func _canonical(data: Variant) -> String:
	return JSON.stringify(data, "", true, true)

func _same_progress(expected: Dictionary, actual: Dictionary) -> bool:
	if expected.size() != actual.size():
		return false
	for key in expected:
		if not actual.has(key):
			return false
		if expected[key] is float:
			if not is_equal_approx(float(expected[key]), float(actual[key])):
				return false
		elif _canonical(expected[key]) != _canonical(actual[key]):
			return false
	return true

func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "isolated fixture is writable")
	if file == null:
		return
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.close()

func _test_era_boundaries() -> void:
	var early = _chapter(1)
	var before := _canonical(early.snapshot())
	for kind in ["gas", "wind", "solar", "battery", "sensor", "control", "intertie", "nuclear", "hvdc"]:
		check(not early.build(kind, Vector2i(1, 1)).ok, "1882 cannot build later-era %s" % kind)
	check(not early.set_tariff("tou").ok and not early.set_market_policy("trade").ok, "1882 cannot configure modern electricity markets")
	check(not early.sign_supply_contract(1.0).ok and not early.set_storage_policy("arbitrage").ok, "1882 cannot sign market contracts or enable battery arbitrage")
	check(not early.connect_communication(int(early.campaign.roles.source), int(early.campaign.roles.node)).ok, "1882 cannot establish digital links")
	check(not early.commission_device(int(early.campaign.roles.source)).ok and not early.research().ok, "1882 cannot commission digital gateways or digital research")
	check(not early.remote_switch(int(early.campaign.roles.source_feeder)).ok and not early.set_dispatch(int(early.campaign.roles.source), 0.5, "remote").ok, "1882 cannot issue remote switching or facility controls")
	check(not early.demand_response().ok and not early.set_security_policy("segmented").ok, "1882 cannot invoke later demand response or security controls")
	check(_canonical(early.snapshot()) == before, "rejected era-inappropriate actions do not change money, equipment, clocks or progress")
	for chapter in range(1, 16):
		var sim = _chapter(chapter)
		if chapter < 11:
			var undigitised: bool = sim.digital.links.is_empty() and sim.digital.pending_commands.is_empty()
			for device in sim.digital.devices.values():
				undigitised = undigitised and not bool(device.commissioned) and is_zero_approx(float(device.ups_remaining))
			check(undigitised and not sim.feature_enabled("digital"), "pre-SCADA chapters have no free digital gateways, links or UPS despite internal technology prerequisites")
		check(not sim.can_build("fusion").ok and not sim.can_build("thermal_storage").ok, "all historical chapters exclude speculative future equipment")
		check(not sim.research_technology("fusion_engineering").ok and not sim.research_technology("advanced_materials").ok, "historical research cannot unlock the future laboratory")
		check(not sim.trigger_storm().ok and not sim.trigger_cyberattack().ok, "campaign event injection is controlled by the current assessment")

func _test_fixed_external_supply() -> void:
	var sim = _chapter(6)
	check(sim.feature_enabled("external_supply") and not sim.feature_enabled("market"), "1954 external supply does not enable modern spot trading")
	check(not sim.set_market_policy("trade").ok and not sim.sign_supply_contract(1.0).ok, "Gotland cannot export or sign a modern market contract")
	var terminal: Dictionary = sim.build("hvdc", Vector2i(4, 5))
	check(terminal.ok, "1954 can construct its physical external supply converter")
	if not terminal.ok:
		return
	check(sim.connect_buildings(int(terminal.id), int(sim.campaign.roles.node)).ok, "converter must physically join the island network")
	var fixed_price := float(sim.campaign.chapter().fixed_import_price)
	sim.step(0.5)
	check(float(sim.totals.import_mw) > 0.0 and not sim.market.ledger.is_empty(), "fixed external supply delivers and settles real electricity")
	var bill: Dictionary = sim.market.ledger[0]
	check(float(bill.import_mwh) > 0.0 and is_equal_approx(float(bill.import_cost), float(bill.import_mwh) * fixed_price), "1954 import ledger charges the chapter's fixed price")
	sim.time_hours = 19.0
	sim.step(0.5)
	check(is_equal_approx(float(sim.market.state.spot_price), fixed_price), "fixed external price survives time-of-day changes")
	var forecast_fixed := true
	for row in sim.market_forecast():
		forecast_fixed = forecast_fixed and is_equal_approx(float(row.spot), fixed_price)
	check(forecast_fixed, "1954 forecast does not silently show a modern volatile spot curve")
	# A loaded or stale internal market setting must still respect the chapter.
	sim.market.state.market_mode = "trade"
	sim.market.state.export_price = 500.0
	sim.market.state.sell_floor = 0.0
	sim._solve(0.0)
	check(sim.market.state.market_mode == "balanced" and is_zero_approx(float(sim.totals.export_mw)), "fixed-supply chapter cannot export through stale market state")

func _test_remote_without_auto_restore() -> void:
	var observation_lesson = _chapter(11)
	check(observation_lesson.research().ok and int(observation_lesson.research_level) == 1, "telemetry lesson enables its first digital research level")
	check(not observation_lesson.research().ok and int(observation_lesson.research_level) == 1, "telemetry lesson cannot skip forward to remote facility permissions")
	var sim = _chapter(12)
	check(sim.research().ok and int(sim.research_level) == 2, "remote-control chapter can unlock L2 facility commands")
	check(sim.feature_enabled("remote") and not sim.feature_enabled("auto_restore"), "L2 permission does not expose the later self-healing lesson")
	var tie: Dictionary = sim.get_line(int(sim.campaign.roles.tie))
	var feeder: Dictionary = sim.get_line(int(sim.campaign.roles.main_feeder))
	feeder.closed = false
	feeder.fault = true
	feeder.health = 25.0
	sim._solve(0.0)
	sim.digital.sample_verified(sim)
	check(not tie.closed and sim.digital.can_control(sim, int(tie.id)), "fixture has a controllable healthy tie and an actual outage")
	sim.step(0.4)
	check(not tie.closed and sim.digital.pending_commands.is_empty(), "chapter 12 does not schedule or execute automatic restoration after L2")
	check(sim.remote_switch(int(tie.id)).ok, "player may deliberately request the remote restoration instead")
	sim.step(0.3)
	check(tie.closed, "intentional remote command still executes through its real queue")

func _test_unknown_observations() -> void:
	var sim = _chapter(4)
	var feeder: Dictionary = sim.get_line(int(sim.campaign.roles.main_feeder))
	feeder.fault = true
	feeder.closed = false
	feeder.health = 17.0
	sim._solve(0.0)
	var observation: Dictionary = sim.line_observation(int(feeder.id))
	check(observation.visibility == "unknown" and not observation.fault_known, "undigitised historical line faults remain unconfirmed")
	check(observation.flow == null and observation.health == null and observation.get("fault") == null and observation.get("closed") == null, "unknown line observations do not reveal physical readings or switch state")
	var facility: Dictionary = sim.facility_observation(int(sim.campaign.roles.source))
	check(not facility.trusted and facility.output == null and facility.health == null and facility.fuel_cost == null, "unknown historical facilities do not reveal hidden telemetry")
	check(sim.patrol_line(int(feeder.id)).ok, "the player can obtain independent evidence through field patrol")
	sim.step(0.6)
	observation = sim.line_observation(int(feeder.id))
	check(observation.visibility == "patrol" and observation.fault_known and observation.fault, "completed field patrol reveals the real fault without granting remote telemetry")

func _test_natural_events_disabled() -> void:
	for chapter in range(1, 16):
		var sim = _chapter(chapter)
		check(not sim.feature_enabled("natural_events"), "chapter %d disables uncontrolled natural events" % chapter)
		sim.next_storm_at = 0.01
		sim.digital.next_attack_at = 0.01
		var incidents_before: int = sim.digital.incidents.size()
		sim.step(0.2)
		check(sim.storm_count == 0 and not sim.storm_active and sim.digital.incidents.size() == incidents_before, "chapter %d is not interrupted by overdue automatic storms or cyberattacks" % chapter)

func _test_all_chapter_persistence() -> void:
	for chapter in range(1, 16):
		var sim = _chapter(chapter)
		sim.step(0.1)
		var saved: Dictionary = sim.snapshot()
		check(int(saved.schema_version) == 6 and Campaign.valid_snapshot(saved.campaign) and sim._valid_save(saved), "chapter %d produces a fully valid schema 6 save" % chapter)
		var path := "%s/chapter-%02d.json" % [QA_DIR, chapter]
		check(sim.save_game(path).ok, "chapter %d writes a real isolated save" % chapter)
		var restored = Sim.new()
		var loaded: Dictionary = restored.load_game(path)
		check(loaded.ok and restored.campaign.active and int(restored.campaign.chapter_id) == chapter, "chapter %d restores its active campaign identity" % chapter)
		if loaded.ok:
			check(_same_progress(sim.campaign.snapshot(), restored.campaign.snapshot()), "chapter %d restores steps, receipts, counters and assessment progress" % chapter)
			check(restored.map_spec().id == sim.map_spec().id and restored.map_size() == sim.map_size() and is_equal_approx(restored.cash, sim.cash), "chapter %d restores map, extent and operating funds" % chapter)
			check(restored._valid_save(restored.snapshot()), "chapter %d remains save-valid after loading" % chapter)
		DirAccess.remove_absolute(path)

func _test_legacy_and_invalid_saves() -> void:
	var sandbox = Sim.new()
	var legacy: Dictionary = sandbox.snapshot()
	legacy.schema_version = 5
	legacy.erase("campaign")
	legacy.region.erase("map_size")
	var legacy_path := QA_DIR + "/legacy-schema-5.json"
	_write(legacy_path, legacy)
	var target = _chapter(5)
	check(target.load_game(legacy_path).ok and not target.campaign.active and target.buildings.size() == 10, "schema 5 sandbox loads into free operation rather than an invented campaign")
	DirAccess.remove_absolute(legacy_path)
	target = _chapter(12)
	var stable := _canonical(target.snapshot())
	var variants: Array[Dictionary] = []
	var malformed: Dictionary = target.snapshot()
	malformed.campaign.chapter_id = 16
	variants.append(malformed)
	malformed = target.snapshot()
	malformed.campaign.step_index = 999
	variants.append(malformed)
	malformed = target.snapshot()
	malformed.campaign.roles.source = 2000
	variants.append(malformed)
	malformed = target.snapshot()
	malformed.campaign.required_customers.append(999999)
	variants.append(malformed)
	malformed = target.snapshot()
	malformed.campaign.hold_hours = -1.0
	variants.append(malformed)
	malformed = target.snapshot()
	malformed.campaign.completed = true
	malformed.campaign.failed = true
	variants.append(malformed)
	for index in variants.size():
		var path := QA_DIR + "/malformed-campaign.json"
		_write(path, variants[index])
		var result: Dictionary = target.load_game(path)
		check(not result.ok and _canonical(target.snapshot()) == stable, "malformed campaign save %d is rejected atomically" % index)
		DirAccess.remove_absolute(path)
	check(not target.start_campaign(16).ok and _canonical(target.snapshot()) == stable, "invalid chapter starts preserve the current campaign")
