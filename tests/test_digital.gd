extends SceneTree
const Sim = preload("res://scripts/sim/grid_sim.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_test_independent_topology_and_cache()
	_test_radio_ups_and_crews()
	_test_remote_field_and_patrol()
	_test_security_and_physics()
	_test_forecasts_and_persistence()
	print("DIGITAL TESTS: %d checks; %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func near(a: float, b: float, tolerance: float = 0.00001) -> bool:
	return absf(a - b) <= tolerance

func prepared() -> RefCounted:
	var sim = Sim.new()
	sim.next_storm_at = 10000.0
	sim.digital.next_attack_at = 10000.0
	return sim

func blank() -> RefCounted:
	var sim = prepared()
	sim.buildings.clear()
	sim.lines.clear()
	sim.objectives.clear()
	sim.next_building_id = 1
	sim.next_line_id = 1
	sim.cash = 1000000.0
	sim.digital.reset(sim)
	sim.digital.next_attack_at = 10000.0
	return sim

func _test_independent_topology_and_cache() -> void:
	var sim = prepared()
	check(sim.buildings.size() == 10 and sim.objectives.size() == 4, "digital expansion preserves the initial ten assets and four missions")
	check(sim.digital.links.size() == 8 and sim.communication_status(10).root, "initial smart terminal is the basic dispatch root")
	check(not sim.communication_status(6).reachable, "unwired industrial gateway is outside the communication topology")
	check(sim.line_observation(1).visibility == "unknown", "no global telemetry appears before research and sampling")
	sim.step(0.01)
	check(sim.line_observation(8).visibility == "verified", "initial root terminal observes its adjacent feeder")
	check(sim.line_observation(1).visibility == "unknown", "local instrumentation does not expose the entire grid")
	sim.research()
	check(sim.line_observation(1).visibility == "unknown", "research action alone does not fabricate a telemetry sample")
	sim.step(0.01)
	check(sim.line_observation(1).visibility == "verified" and sim.has_telemetry(1), "researched telemetry uses a real trusted communication path")
	var old_flow: float = sim.line_observation(1).flow
	var root_link := -1
	for link in sim.digital.links:
		if (int(link.a)==10 and int(link.b)==2) or (int(link.a)==2 and int(link.b)==10): root_link=int(link.id)
	sim.toggle_communication(root_link)
	check(not sim.communication_status(2).reachable and sim.get_building(2).powered, "cutting communications leaves electrical power independent")
	check(sim.line_observation(1).visibility == "stale", "loss of communication turns a prior measurement into a stale cache")
	sim.get_line(1).flow = 999.0
	check(near(sim.line_observation(1).flow, old_flow), "stale observations retain their sampled value rather than exposing live truth")
	check(not sim.has_telemetry(1), "stale cache is not valid live telemetry")
	var before := JSON.stringify(sim.digital.snapshot(), "", true, true)
	var cash: float = sim.cash
	var energy: float = sim.get_building(9).energy
	for _index in 50:
		sim.communication_status(2)
		sim.line_observation(1)
		sim.digital.summarize(sim)
		sim._solve(0.0)
	check(JSON.stringify(sim.digital.snapshot(), "", true, true) == before, "status, overlays and zero-time solves do not mutate persistent digital state")
	check(near(sim.cash, cash) and near(sim.get_building(9).energy, energy), "digital queries cannot settle cash or create energy")
	var control: Dictionary = sim._add_building("control", Vector2i(12, 12))
	check(sim.connect_communication(control.id, 3).ok, "a second independent control root can provide redundancy")
	check(sim.communication_status(1).reachable, "redundant root bypasses the failed original communication route")
	sim.step(0.01)
	check(sim.line_observation(1).visibility == "verified", "restored communication produces fresh measurements on the next positive tick")
	check(sim.connect_buildings(2, 6).ok, "industrial power feeder can be connected")
	check(not sim.communication_status(6).reachable, "building an electrical feeder does not secretly create a data link")
	check(sim.connect_communication(2, 6).ok, "industrial gateway requires its own communications investment")
	sim.research_level = 2
	var industrial_before: float = sim.get_building(6).demand
	sim.demand_response()
	check(float(sim.get_building(6).demand) < industrial_before, "demand response reaches a trusted controllable industrial load")
	sim.isolate_device(6)
	check(near(sim.get_building(6).demand, industrial_before), "isolated industrial gateway cannot receive virtual demand-response commands")

func _test_radio_ups_and_crews() -> void:
	var sim = blank()
	sim._add_building("control", Vector2i(2, 2))
	sim._add_building("gas", Vector2i(3, 2))
	sim._add_building("home", Vector2i(8, 2))
	sim._add_building("home", Vector2i(13, 13))
	sim._add_building("relay", Vector2i(11, 2))
	sim._add_line(1, 2)
	sim._refresh()
	check(sim.connect_communication(1, 3, "wireless").ok, "ordinary wireless link reaches six cells")
	check(not sim.connect_communication(1, 4, "wireless").ok, "wireless range is a real construction constraint")
	check(sim.connect_communication(1, 5, "wireless").ok, "relay extends a wireless hop to ten cells")
	check(sim.connect_communication(1, 4, "fiber").ok, "fiber can span a long distance")
	check(not sim.connect_communication(1, 3, "fiber").ok, "duplicate communication edge is rejected")
	var initial_ups: float = sim.communication_status(3).ups_remaining
	sim.step(0.5)
	check(near(sim.communication_status(3).ups_remaining, initial_ups - 0.5), "unpowered gateways consume UPS hours at a real simulated rate")
	check(sim.communication_status(3).reachable, "UPS keeps a disconnected load gateway observable temporarily")
	sim.step(1.6)
	check(near(sim.communication_status(3).ups_remaining, 0.0) and not sim.communication_status(3).reachable, "gateway goes offline when its two-hour UPS expires")
	sim.get_building(3).online = false
	check(not sim.communication_status(3).reachable, "equipment maintenance disables its gateway even if UPS existed")
	sim.trigger_storm()
	var radio_faults := 0
	for link in sim.digital.links:
		if link.fault:
			radio_faults += 1
			check(link.kind == "wireless", "storm damages wireless links without inventing a fiber failure")
	check(radio_faults == 1, "storm selects one existing wireless link")
	for link in sim.digital.links:
		if link.fault:
			check(sim.repair_communication(link.id).ok, "communication repair can dispatch a real crew")
	check(sim.active_repairs() == 1, "communication repair shares the field workforce")
	sim.step(0.4)
	for link in sim.digital.links:
		check(not link.fault, "wireless repair completes after its duration")
	check(absf(sim.totals.energy_balance_error) < 0.00001, "radio outages and repairs do not manufacture electrical energy")

func _test_remote_field_and_patrol() -> void:
	var sim = prepared()
	sim.research_level = 1
	sim.step(0.01)
	check(sim.remote_switch(2).ok and sim.digital.pending_commands.size() == 1, "trusted remote switching enters a command queue")
	check(sim.get_line(2).closed, "remote operation does not act instantly at the client")
	var wait: float = sim.digital.pending_commands[0].remaining
	sim.step(wait)
	check(not sim.get_line(2).closed and sim.digital.state.remote_success == 1, "remote command executes after transport and validation")
	var observation: Dictionary = sim.line_observation(2)
	check(observation.visibility == "verified" and not observation.closed and near(observation.flow, 0.0), "exact acknowledgement endpoint exposes the newly solved switch and flow state")
	check(near(sim.market.ledger[0].served_mwh, sim.total_served_mwh), "command acknowledgement does not double-settle served MWh")
	check(sim.remote_switch(2).ok, "reclose can be requested over still-available UPS communications")
	sim.isolate_device(3)
	sim.step(0.2)
	check(not sim.get_line(2).closed and sim.digital.state.remote_rejected == 1, "in-flight command cannot bypass a path that becomes isolated")
	var field = blank()
	field._add_building("gas", Vector2i(3, 3))
	field._add_building("factory", Vector2i(5, 3))
	field._add_line(1, 2)
	field._refresh()
	check(not field.remote_switch(1).ok, "remote controls cannot operate without a communications root")
	var cash: float = field.cash
	check(field.field_switch(1).ok and near(field.cash, cash - 350.0), "field switching pays its dispatch fee")
	check(field.active_repairs() == 1 and field.digital.field_jobs.size() == 1, "field queue exposes real workforce occupancy")
	field.step(0.35)
	observation = field.line_observation(1)
	check(not field.get_line(1).closed and observation.visibility == "patrol" and not observation.closed and near(observation.flow, 0.0), "disconnected field operator verifies the final physical switch and flow")
	field.get_line(1).fault = true
	field.get_line(1).health = 25.0
	check(field.patrol_line(1).ok, "outage location can be investigated without data connectivity")
	field.step(0.5)
	check(field.line_observation(1).fault_known and field.line_observation(1).fault, "patrol identifies an actual physical fault")
	check(field.repair_line(1).ok and near(field.get_line(1).repair_remaining, 0.6), "known fault receives the shorter targeted repair")
	field.step(0.6)
	observation = field.line_observation(1)
	check(not field.get_line(1).fault and observation.visibility == "patrol" and not observation.fault and observation.closed, "completed repair replaces the old red fault cache with a verified field record")
	field.step(1.1)
	check(field.line_observation(1).visibility == "stale" and not field.has_telemetry(1), "old patrol records expire instead of becoming permanent truth")
	field._add_building("home", Vector2i(5, 5))
	field._add_building("home", Vector2i(3, 5))
	field._add_line(1, 3)
	field._add_line(1, 4)
	check(field.patrol_line(1).ok and field.patrol_line(2).ok, "two field teams may work concurrently")
	check(not field.patrol_line(3).ok, "third simultaneous patrol is rejected by crew capacity")
	var unlocated = blank()
	unlocated._add_building("gas", Vector2i(3, 3))
	unlocated._add_building("home", Vector2i(5, 3))
	unlocated._add_line(1, 2)
	unlocated.get_line(1).fault = true
	unlocated.get_line(1).closed = false
	check(unlocated.repair_line(1).ok and near(unlocated.get_line(1).repair_remaining, 1.1), "legacy repair command includes discovery delay when no fault location is known")

func _test_security_and_physics() -> void:
	var sim = prepared()
	sim.research_level = 1
	sim.step(0.02)
	var closed := JSON.stringify(sim.lines)
	check(sim.trigger_cyberattack("spoof", 4).ok, "spoof exercise creates an abstract incident")
	check(not sim.digital.incidents[-1].detected and not sim.communication_status(4).compromised, "undetected attack does not leak its target through public device status")
	var observation: Dictionary = sim.line_observation(3)
	check(observation.visibility == "suspect" and observation.flow == null and observation.health == null and observation.heat == null, "suspect data never exposes live numerical truth")
	check(not sim.remote_switch(3).ok, "untrusted telemetry cannot authorize remote control even before attribution")
	check(JSON.stringify(sim.lines) == closed, "spoofing does not directly alter physical electricity")
	sim.step(0.65)
	check(sim.digital.incidents[-1].detected and sim.communication_status(4).compromised, "detection time reveals the confirmed compromised device")
	check(int(sim.totals.cyber_active) == 1, "public active incident count includes detected events")
	sim.isolate_device(4)
	check(sim.communication_status(4).isolated and not sim.communication_status(4).reachable, "isolation removes both spread and the device's own telemetry path")
	check(sim.recover_device(4).ok, "compromised device can be patched and recovered")
	sim.step(0.75)
	check(not sim.digital.devices[4].compromised and not sim.digital.devices[4].isolated, "patch recovery clears compromise and reconnects the device")
	check(sim.recover_device(3).ok, "open network propagation leaves another gateway requiring cleanup")
	sim.step(0.75)
	check(sim.communication_status(4).trusted, "trusted path returns after the propagated compromise is removed")
	var dos = prepared()
	dos.research_level = 1
	dos.step(0.01)
	check(dos.trigger_cyberattack("dos", 2).ok, "denial-of-service exercise is available")
	check(not dos.communication_status(2).reachable, "DoS interrupts communication reachability")
	check(dos.get_building(2).powered, "DoS does not turn off electrical power by itself")
	dos.get_line(3).capacity = 0.25
	dos.step(0.2)
	check(not dos.get_line(3).closed, "local electrical protection still trips with dispatch communications offline")
	dos.step(1.4)
	check(dos.communication_status(2).reachable, "temporary DoS naturally expires")
	var intrusion = prepared()
	intrusion.research_level = 1
	intrusion.step(0.01)
	intrusion.trigger_cyberattack("intrusion", 3)
	check(not intrusion.get_line(2).closed and not intrusion.get_line(2).fault, "unprotected intrusion can maliciously open a healthy electrical switch")
	check(absf(intrusion.totals.energy_balance_error) < 0.00001, "intrusion changes topology without inventing electrical injections")
	var protected = prepared()
	protected.set_security_policy("zero_trust")
	protected.trigger_cyberattack("intrusion", 3)
	check(protected.get_line(2).closed and protected.digital.state.blocked_attacks == 1, "zero-trust policy rejects unverified malicious control")
	check(near(protected.totals.security_cost, 75.0), "strict policy has an explicit recurring cost")
	check(protected.upgrade_security().ok and protected.upgrade_security().ok and not protected.upgrade_security().ok, "security progression has two bounded levels")
	protected.trigger_cyberattack("dos", 2)
	check(protected.communication_status(2).reachable and protected.digital.state.blocked_attacks == 2, "strong defense blocks an abstract availability attack")
	var segmented = prepared()
	segmented.set_security_policy("segmented")
	segmented.trigger_cyberattack("intrusion", 3)
	check(segmented.digital.incidents[-1].affected_ids.size() == 1, "segmentation limits compromise propagation to its initial target")
	var soc = prepared()
	var center: Dictionary = soc._add_building("soc", Vector2i(12, 12))
	soc.connect_buildings(2, center.id)
	soc.connect_communication(2, center.id)
	soc.set_security_policy("segmented")
	soc.trigger_cyberattack("spoof", 4)
	check(soc.digital.state.blocked_attacks == 1, "online trusted security center contributes actual defensive capability")
	check(near(soc.totals.security_cost, 65.0), "SOC and policy recurring costs are additive")
	var latency = prepared()
	latency.research_level = 1
	latency.digital.get_link(8).latency_ms = 500.0
	latency.step(0.01)
	check(not latency.remote_switch(6).ok, "fresh telemetry alone cannot bypass excessive control latency")
	latency.upgrade_communication(8)
	latency.upgrade_communication(8)
	check(latency.remote_switch(6).ok, "network upgrade reduces latency enough to unlock actual remote capability")
	var fairness = prepared()
	fairness.set_security_policy("zero_trust")
	var cash_before: float = fairness.cash
	fairness.step(0.1)
	check(near(fairness.cash - cash_before, fairness.market.ledger[0].net), "communication and security fees settle exactly once through the existing daily ledger")
	check(fairness.market.ledger[0].maintenance_cost >= (64.0 + 75.0) * 0.1, "ledger maintenance includes fiber and security operating costs")

func _test_forecasts_and_persistence() -> void:
	var sim = Sim.new()
	sim.next_storm_at = 10000.0
	sim.step(9.2)
	check(sim.digital.warning_sent and sim.digital.incidents.is_empty(), "scheduled network event receives an advance warning")
	var path := "user://test_tidal-grid-digital-test.json"
	check(sim.save_game(path).ok and Sim.SCHEMA_VERSION == 6, "cross-system simulation uses schema six")
	var loaded = Sim.new()
	check(loaded.load_game(path).ok, "digital topology and cached state load")
	check(JSON.stringify(sim.digital.snapshot(), "", true, true) == JSON.stringify(loaded.digital.snapshot(), "", true, true), "device timers, observations, forecasts and queues round-trip exactly")
	sim.step(0.8)
	loaded.step(0.8)
	check(sim.digital.incidents.size() == 1 and near(sim.digital.next_attack_at, 46.0), "first automatic network event arrives at hour ten and next is thirty-six hours later")
	check(JSON.stringify(sim.digital.snapshot(), "", true, true) == JSON.stringify(loaded.digital.snapshot(), "", true, true), "saved deterministic network event continues identically")
	check(near(sim.cash, loaded.cash), "digital persistence preserves deterministic economics")
	var queue = prepared()
	queue.research_level = 1
	queue.step(0.01)
	queue.remote_switch(2)
	queue.patrol_line(3)
	check(queue.save_game(path).ok, "in-flight field and remote operations can be saved")
	check(loaded.load_game(path).ok and loaded.digital.pending_commands.size() == 1 and loaded.digital.field_jobs.size() == 1, "command queues restore with integer references")
	check(typeof(loaded.digital.pending_commands[0].line_id) == TYPE_INT, "restored remote target retains integer identity")
	queue.step(0.7)
	loaded.step(0.7)
	check(JSON.stringify(queue.digital.snapshot(), "", true, true) == JSON.stringify(loaded.digital.snapshot(), "", true, true), "saved commands complete deterministically rather than repeating or skipping")
	var legacy: Dictionary = queue.snapshot()
	legacy.schema_version = 2
	legacy.erase("digital")
	write_json(path, legacy)
	check(loaded.load_game(path).ok, "schema-two market saves migrate safely")
	check(loaded.digital.links.size() == loaded.lines.size() and loaded.digital.observations.is_empty(), "legacy migration builds a data graph without fabricating telemetry history")
	legacy.schema_version = 1
	legacy.erase("market")
	write_json(path, legacy)
	check(loaded.load_game(path).ok and loaded.market.state.tariff_mode == "flat", "schema-one saves receive both safe market and digital defaults")
	var before := JSON.stringify(loaded.snapshot(), "", true, true)
	var valid: Dictionary = loaded.snapshot()
	var attacks: Array[Dictionary] = []
	var bad: Dictionary = valid.duplicate(true)
	bad.schema_version = {}
	attacks.append(bad)
	bad = valid.duplicate(true)
	bad.digital.links[0].a = 9999
	attacks.append(bad)
	bad = valid.duplicate(true)
	bad.digital.links[0].latency_ms = -1.0
	attacks.append(bad)
	bad = valid.duplicate(true)
	bad.digital.devices[0].ups_remaining = 2.1
	attacks.append(bad)
	bad = valid.duplicate(true)
	bad.digital.devices[0].spoof_remaining = 1.0
	bad.digital.devices[0].compromised = false
	attacks.append(bad)
	bad = valid.duplicate(true)
	bad.digital.pending_commands = [{"id": 1, "line_id": 9999, "target_closed": true, "remaining": 0.1}]
	bad.digital.next_command_id = 2
	attacks.append(bad)
	bad = valid.duplicate(true)
	bad.digital.observations = [{"line_id": 1, "fault": false, "closed": true, "flow": 0.0, "health": 100.0, "heat": 0.0, "sampled_at": float(bad.elapsed_hours) + 1.0, "source": "telemetry"}]
	attacks.append(bad)
	bad = valid.duplicate(true)
	bad.digital.state.policy = "hacked"
	attacks.append(bad)
	bad = valid.duplicate(true)
	bad.digital.links.append(bad.digital.links[0].duplicate(true))
	attacks.append(bad)
	for invalid in attacks:
		write_json(path, invalid)
		check(not loaded.load_game(path).ok, "malformed digital or schema data is rejected")
		check(JSON.stringify(loaded.snapshot(), "", true, true) == before, "invalid digital load cannot partially replace the live market or world")
	DirAccess.remove_absolute(path)

func write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "", true, true))
	file.close()
