extends RefCounted
## Independent historical lessons using the production simulation and its real receipts.
const Catalog = preload("res://scripts/sim/campaign_catalog.gd")
const Maps = preload("res://scripts/sim/scenario_map.gd")

var active := false
var chapter_id := 1
var step_index := 0
var completed := false
var failed := false
var failure_reason := ""
var roles: Dictionary = {}
var required_customers: Array[int] = []
var flags: Dictionary = {}
var hold_hours := 0.0
var charged_mwh := 0.0
var discharged_mwh := 0.0
var imported_mwh := 0.0
var contract_cost := 0.0
var assessment_net := 0.0
var critical_outage_hours := 0.0
var assessment_started := false
var initial_customer_count := 0
var _initializing := false
var _cached_id := 0
var _chapter_cache: Dictionary = {}
var _steps_cache: Array[Dictionary] = []

func chapter() -> Dictionary:
	_cache()
	return _chapter_cache

func _cache() -> void:
	if _cached_id == chapter_id: return
	_cached_id = chapter_id
	_chapter_cache = Catalog.get_chapter(chapter_id)
	_chapter_cache.research = ["ac_systems"] if chapter_id == 2 else []
	_chapter_cache.allowed_technologies = _chapter_cache.research.duplicate()
	_chapter_cache.budget = _budget()
	_steps_cache = Catalog.steps(chapter_id)

func _budget() -> Dictionary:
	# Reference capital/field-work allowance plus twelve hours of gross operating
	# expenses, with a visible 30% contingency. Existing municipal assets are free.
	var capital: Array = [28000,13000,350,8500,6200,89500,57350,74750,0,27850,19400,33000,900,1750,39500]
	var operating: Array = [12000,3600,21600,13200,4800,28800,54000,12000,12600,21600,9600,10800,14400,15000,9600]
	var construction := float(capital[chapter_id-1])
	var reserve := float(operating[chapter_id-1])
	return {"capital":construction,"operations_12h":reserve,"contingency":0.3,"total":ceilf((construction+reserve)*1.3/100.0)*100.0}

func current_step() -> Dictionary:
	if not active: return {}
	_cache()
	var steps := _steps_cache
	if completed: return {"title":"本关完成", "instruction":chapter().debrief, "why":"前往下一处历史现场，或重玩本关。", "ui_target":"", "hints":[], "action":"", "progress":1.0}
	if failed: return {"title":"本关需要重试", "instruction":failure_reason, "why":"重试恢复本关开局，不清除已解锁章节。", "ui_target":"", "hints":[], "action":"", "progress":0.0}
	var result: Dictionary = steps[step_index].duplicate(true)
	result.progress = clampf(hold_hours / float(result.hold_hours), 0.0, 1.0) if float(result.hold_hours) > 0.0 else 0.0
	result.elapsed_hours = hold_hours
	result.step_number = step_index + 1
	result.step_count = steps.size()
	return result

func allows(feature: String) -> bool:
	if not active: return true
	match feature:
		"research": return chapter_id >= 2
		"region": return chapter_id in [5, 15]
		"external_supply": return chapter_id >= 6
		"market": return chapter_id >= 9
		"digital": return chapter_id >= 11
		"remote": return chapter_id >= 12
		"auto_restore": return chapter_id >= 13
		"demand_response": return chapter_id >= 12
		"storm": return chapter_id == 13
		"security": return chapter_id >= 14
		"storage_control": return chapter_id >= 15
		"natural_events": return false
	return false

func can_build(kind: String) -> bool:
	if not active: return true
	if kind in ["home", "factory", "hospital", "substation"]: return true
	var available: Array = ["dc_dynamo"] if chapter_id == 1 else []
	if chapter_id >= 3: available.append_array(["steam", "coal"])
	if chapter_id >= 5: available.append("hydro")
	if chapter_id >= 6: available.append_array(["hvdc", "condenser"])
	if chapter_id >= 7: available.append_array(["cooling", "academy", "nuclear"])
	if chapter_id >= 8: available.append("pumped_storage")
	if chapter_id >= 9: available.append("intertie")
	if chapter_id >= 10: available.append_array(["gas", "wind", "ccgt"])
	if chapter_id >= 11: available.append_array(["sensor", "control", "relay"])
	if chapter_id >= 14: available.append("soc")
	if chapter_id >= 15: available.append_array(["solar", "battery", "community_battery", "flow_battery", "hydrogen"])
	return kind in available

func can_research(technology: String) -> bool:
	return not active or technology in chapter().research

func start(sim: RefCounted, id: int) -> Dictionary:
	if id < 1 or id > 15: return _result(false, "未知历史章节。")
	active = true
	chapter_id = id
	step_index = 0
	completed = false
	failed = false
	failure_reason = ""
	roles.clear()
	required_customers.clear()
	flags.clear()
	hold_hours = 0.0
	charged_mwh = 0.0
	discharged_mwh = 0.0
	imported_mwh = 0.0
	contract_cost = 0.0
	assessment_net = 0.0
	critical_outage_hours = 0.0
	assessment_started = false
	_initializing = true
	sim.buildings.clear()
	sim.lines.clear()
	sim.objectives.clear()
	sim.log_entries.clear()
	sim.next_building_id = 1
	sim.next_line_id = 1
	sim.region.reset()
	sim.digital.reset(sim)
	sim.evolution.reset()
	sim.evolution.heritage = true
	sim.evolution.unlocked.assign(_technologies())
	sim.market.reset()
	sim.market.state.market_mode = "off"
	sim.cash = float(_budget().total)
	sim.time_hours = 23.0 if id == 8 else (6.0 if id == 3 else 8.0)
	sim.research_level = 0 if id <= 11 else (1 if id == 12 else 2)
	_build_fixture(sim)
	initial_customer_count = required_customers.size()
	sim.digital.reset(sim)
	if id >= 12:
		sim.digital.commission_initial(sim, int(roles.root))
	if id == 14: sim.digital.state.policy = "segmented"
	if id >= 9:
		sim.market.state.market_mode = "balanced"
		sim.market.state.buy_limit = 500.0
	if id in [5, 15]: sim.region.seed_from_scenario(sim, Maps.for_chapter(id).settlements)
	_initializing = false
	sim._log("历史战役 · %s · %s" % [chapter().place, chapter().years], "info")
	return _result(true, "历史现场已整备。阅读简报后开始本关。")

func _technologies() -> Array[String]:
	var result: Array[String] = ["dc_basics"]
	if chapter_id >= 3: result.append_array(["ac_systems", "turbines"])
	if chapter_id >= 4: result.append("protection")
	if chapter_id >= 5: result.append_array(["hydraulics", "regional_planning"])
	if chapter_id >= 6: result.append_array(["reactive_support", "power_electronics"])
	if chapter_id >= 7: result.append_array(["nuclear_science", "thermal_cooling", "reactor_engineering"])
	if chapter_id >= 8: result.append("pumped_hydro")
	if chapter_id >= 10: result.append("combined_cycle")
	if chapter_id >= 11: result.append("scada")
	if chapter_id >= 15: result.append_array(["storage_chemistry", "distributed_energy", "smart_storage", "electrolysis", "flexible_thermal", "dry_cooling"])
	# Historical facilities may need later game-tree prerequisites. Capability
	# gates still prevent those prerequisites from commissioning modern devices.
	var cursor := 0
	while cursor < result.size():
		for prerequisite in sim_technology_dependencies(result[cursor]):
			if prerequisite not in result: result.append(prerequisite)
		cursor += 1
	return result

func sim_technology_dependencies(id: String) -> Array:
	const Evolution = preload("res://scripts/sim/grid_evolution.gd")
	return Evolution.TECHNOLOGIES[id].requires

func _add(sim: RefCounted, role: String, kind: String, cell: Vector2i, metadata: Dictionary = {}) -> int:
	var properties := {"ownership":"municipal", "invested_capital":0.0, "refund_basis":0.0}
	properties.merge(metadata, true)
	var b: Dictionary = sim._add_building(kind, cell, properties)
	roles[role] = int(b.id)
	if kind in ["home", "factory", "hospital"]: required_customers.append(int(b.id))
	return int(b.id)

func _line(sim: RefCounted, role: String, a: String, b: String, capacity: float = 60.0, closed: bool = true) -> int:
	var line: Dictionary = sim._add_line(int(roles[a]), int(roles[b]))
	line.capacity = capacity
	line.closed = closed
	roles[role] = int(line.id)
	return int(line.id)

func _basic(sim: RefCounted, kind: String = "gas", demand: float = 11.0) -> void:
	var source := _add(sim, "source", kind, Vector2i(3,7), {"ramp_mw":float(sim.catalog[kind].capacity), "startup_remaining":0.0})
	_add(sim, "node", "substation", Vector2i(6,7))
	_add(sim, "customer", "factory", Vector2i(11,8), {"base_demand":demand})
	_line(sim, "source_feeder", "source", "node")
	_line(sim, "main_feeder", "node", "customer")
	if source < 0: return

func _digital_fixture(sim: RefCounted, hospital: bool = false) -> void:
	_basic(sim)
	_add(sim, "root", "sensor", Vector2i(7,6))
	_line(sim, "root_power", "node", "root")
	if chapter_id >= 12:
		_add(sim, "backup", "substation", Vector2i(7,11))
		_line(sim, "backup_feed", "source", "backup")
		_line(sim, "tie", "backup", "customer", 60.0, false)
	if hospital:
		_add(sim, "hospital", "hospital", Vector2i(12,10))
		_line(sim, "hospital_feeder", "customer", "hospital")

func _build_fixture(sim: RefCounted) -> void:
	match chapter_id:
		1:
			_add(sim, "source", "dc_dynamo", Vector2i(6,7), {"ramp_mw":7.0,"startup_remaining":0.0})
			_add(sim, "node", "substation", Vector2i(7,7), {"name":"街区配电站"})
			_add(sim, "home", "home", Vector2i(8,5), {"base_demand":2.0,"name":"珍珠街住宅"})
			_add(sim, "customer", "factory", Vector2i(9,8), {"base_demand":1.5,"name":"珍珠街小工坊"})
			_line(sim, "source_feeder", "source", "node")
			_line(sim, "home_feeder", "node", "home")
		2:
			_add(sim, "source", "hydro", Vector2i(3,3), {"ramp_mw":30.0,"startup_remaining":0.0,"name":"劳芬水力机房"})
			_add(sim, "node", "substation", Vector2i(10,7))
			_add(sim, "customer", "factory", Vector2i(12,9), {"base_demand":4.0,"name":"法兰克福展场"})
			_line(sim, "main_feeder", "node", "customer")
		3:
			_basic(sim, "coal", 20.0)
			var coal: Dictionary = sim.get_building(int(roles.source))
			coal.dispatch = 0.0
			coal.ramp_mw = 0.0
			coal.startup_remaining = 3.0
			_add(sim, "backup", "steam", Vector2i(4,5), {"ramp_mw":17.0,"startup_remaining":0.0})
			_line(sim, "backup_feed", "backup", "node")
		4:
			_basic(sim, "coal", 23.0)
			sim.get_line(int(roles.main_feeder)).capacity = 24.0
			_add(sim, "backup", "substation", Vector2i(7,11))
			_line(sim, "backup_feed", "source", "backup")
		5:
			_add(sim, "source", "hydro", Vector2i(18,3), {"ramp_mw":30.0,"startup_remaining":0.0})
			_add(sim, "node", "substation", Vector2i(8,7))
			_add(sim, "customer", "factory", Vector2i(11,8), {"base_demand":3.0})
			_add(sim, "home", "home", Vector2i(9,6), {"base_demand":2.0})
			_line(sim, "main_feeder", "node", "customer")
			_line(sim, "home_feeder", "node", "home")
		6:
			_basic(sim, "dc_dynamo", 22.0)
			sim.get_line(int(roles.main_feeder)).capacity = 24.0
		7:
			_basic(sim, "nuclear", 32.0)
			var reactor: Dictionary = sim.get_building(int(roles.source))
			reactor.dispatch = 0.0
			reactor.ramp_mw = 0.0
			reactor.startup_remaining = 8.0
			_add(sim, "startup_source", "hvdc", Vector2i(4,5))
			_add(sim, "hospital", "hospital", Vector2i(10,10))
			_line(sim, "startup_feed", "startup_source", "node", 120.0)
			sim.get_line(int(roles.source_feeder)).capacity = 120.0
			sim.get_line(int(roles.main_feeder)).capacity = 120.0
			_line(sim, "hospital_feeder", "node", "hospital", 120.0)
		8:
			_basic(sim, "coal", 24.0)
			sim.get_building(int(roles.source)).dispatch = 0.45
		9:
			_basic(sim, "intertie", 8.0)
		10:
			_basic(sim)
			_add(sim, "wind", "wind", Vector2i(4,4))
			_line(sim, "wind_feeder", "wind", "node")
		11,12,13,14:
			_digital_fixture(sim, chapter_id >= 13)
			if chapter_id == 14: roles["attack_target"] = roles.customer
		15:
			_basic(sim, "ccgt", 20.0)
			_add(sim, "home", "home", Vector2i(12,10), {"base_demand":3.0})
			_add(sim, "hospital", "hospital", Vector2i(7,12), {"base_demand":4.0})
			_add(sim, "root", "sensor", Vector2i(7,6))
			_add(sim, "external", "intertie", Vector2i(4,9))
			for role in ["home","hospital","root","external"]: _line(sim, role+"_feeder", "node", role)
			for index in range(4):
				var role := "wind_%d" % index
				_add(sim, role, "wind", Vector2i(3+index*2,3))
				_line(sim, role+"_feeder", role, "node")

func record_action(action_name: String, target: int = -1, details: Dictionary = {}) -> void:
	if not active or _initializing or completed or failed: return
	if details.get("phase", "executed") != "executed": return
	flags[action_name] = int(flags.get(action_name, 0)) + 1
	flags["%s:%d" % [action_name,target]] = true
	if action_name == "market": flags["market_"+str(details.get("operation",details.get("kind","")))] = true
	if action_name == "build": flags["build_kind_"+str(details.get("kind",""))] = true
	if action_name == "facility":
		flags["facility_"+str(details.get("method","field"))] = true
		var settings: Dictionary = details.get("settings",{})
		for key in settings: flags["setting_"+str(key)] = true
	if action_name == "contract": flags["contract_signed"] = true
	if action_name == "response": flags["response_started_at"] = float(details.get("elapsed_hours",0.0))

func evaluate(sim: RefCounted) -> void:
	if not active or _initializing or completed or failed: return
	_cache()
	var steps := _steps_cache
	# Never cross a duration gate from a query; advance() owns those clocks.
	for _index in steps.size():
		if completed: break
		var step: Dictionary = steps[step_index]
		if float(step.hold_hours) > 0.0 or not _qualifies(sim,str(step.predicate)): break
		_next(sim)

func advance(sim: RefCounted, dt: float) -> void:
	if not active or _initializing or completed or failed or dt <= 0.0: return
	if float(sim.cash) < -20000.0:
		_fail("运营资金低于 −20,000。请重试本关，重新安排投资和运行成本。")
		return
	for b in sim.buildings:
		if sim.evolution.is_storage(str(b.kind)):
			charged_mwh += float(b.charging)*dt*sim.evolution.storage_efficiency(b)
			discharged_mwh += float(b.output)*dt
	imported_mwh += float(sim.totals.get("import_mw",0.0))*dt
	contract_cost += float(sim.totals.get("contract_cost",0.0))*dt
	if assessment_started and chapter_id in [13,14]:
		var hospital: Dictionary = sim.get_building(int(roles.hospital))
		var supplied := not hospital.is_empty() and float(hospital.served) >= float(hospital.demand)*0.98
		critical_outage_hours = 0.0 if supplied else critical_outage_hours+dt
		if critical_outage_hours + 0.000001 >= 2.0:
			_fail("关键负荷连续失供两游戏小时。重试后先安排备用路径与现场处置。")
			return
	evaluate(sim)
	if completed: return
	var step: Dictionary = _steps_cache[step_index]
	var required := float(step.hold_hours)
	if required <= 0.0: return
	var qualifies := _qualifies(sim,str(step.predicate))
	if qualifies:
		hold_hours += dt
		if str(step.predicate) == "final_assessment": assessment_net += (float(sim.totals.income)-float(sim.totals.expenses))*dt
	else:
		hold_hours = 0.0
		assessment_net = 0.0
	if hold_hours + 0.000001 >= required:
		if str(step.predicate) != "final_assessment" or assessment_net >= -0.000001:
			_next(sim)
		elif str(step.predicate) == "final_assessment":
			hold_hours = 0.0
			assessment_net = 0.0

func action(sim: RefCounted, name: String) -> Dictionary:
	if not active or completed or failed: return _result(false,"当前没有可开始的考核。")
	if name not in ["begin_assessment","prepare"]: return _result(false,"未知战役操作。")
	if current_step().get("action","") != "begin_assessment": return _result(false,"请先完成当前教学目标。")
	if assessment_started: return _result(false,"本关考核已经开始。")
	assessment_started = true
	assessment_net = 0.0
	critical_outage_hours = 0.0
	if chapter_id == 13:
		var line: Dictionary = sim.get_line(int(roles.main_feeder))
		line.fault = true
		line.closed = false
		line.health = 25.0
		line.trip_reason = "风雪损坏"
		sim.storm_active = true
		sim.storm_remaining = 2.5
		sim.storm_count += 1
		sim._log("风雪考核开始：部分区域报告失电，请先核实供电与通信。", "warning")
	elif chapter_id == 14:
		var result: Dictionary = sim.digital.trigger_attack(sim,"intrusion",int(roles.attack_target),true,true)
		if not result.ok:
			assessment_started = false
			return result
		sim._log("安全恢复考核开始：异常控制需要隔离、现场核实与修补。", "warning")
	evaluate(sim)
	return _result(true,"考核开始；时间推进后才会记录真实运营结果。")

func _reliable(sim: RefCounted) -> bool:
	if required_customers.is_empty(): return false
	for id in required_customers:
		var b: Dictionary = sim.get_building(id)
		if b.is_empty() or float(b.demand) <= 0.000001 or float(b.served)+0.000001 < float(b.demand)*0.98: return false
	return float(sim.totals.get("demand",0.0)) > 0.1 and float(sim.totals.get("reliability",0.0)) >= 0.98

func _connected(sim: RefCounted, a: int, b: int) -> bool:
	if sim.get_building(a).is_empty() or sim.get_building(b).is_empty(): return false
	return b in sim.evolution._component(sim,a)

func _kind_connected(sim: RefCounted, kind: String) -> bool:
	for b in sim.buildings:
		if b.kind == kind and _connected(sim,int(b.id),int(roles.node)): return true
	return false

func _receipt(name: String, target: int = -1) -> bool:
	return bool(flags.get(name,false)) if target < 0 else bool(flags.get("%s:%d" % [name,target],false))

func _qualifies(sim: RefCounted, predicate: String) -> bool:
	match predicate:
		"first_connection": return _receipt("connect") and _connected(sim,int(roles.source),int(roles.customer))
		"new_customer":
			for b in sim.buildings:
				if b.kind == "home" and not int(b.id) in required_customers and _connected(sim,int(b.id),int(roles.node)) and b.powered: return _receipt("build")
			return false
		"reliable": return _reliable(sim)
		"ac_research": return sim.evolution.has_technology("ac_systems")
		"facility_action": return _receipt("facility",int(roles.source))
		"thermal_running": return float(sim.get_building(int(roles.source)).output) > 1.0 and float(sim.get_building(int(roles.source)).startup_remaining) <= 0.000001
		"inspection": return _receipt("inspect",int(roles.main_feeder))
		"line_upgrade": return _receipt("upgrade_line")
		"redundancy":
			for line in sim.lines:
				if [int(line.a),int(line.b)] in [[int(roles.backup),int(roles.customer)],[int(roles.customer),int(roles.backup)]]: return true
			return false
		"field_transfer": return _receipt("field_switch",int(roles.main_feeder)) and not bool(sim.get_line(int(roles.main_feeder)).closed) and _reliable(sim)
		"ecology": return _receipt("facility",int(roles.source)) and bool(flags.get("setting_environmental_release",false)) and float(sim.get_building(int(roles.source)).environmental_release) >= 0.25
		"hvdc_connected": return _receipt("build") and _kind_connected(sim,"hvdc")
		"import_reliable": return imported_mwh > 0.01 and _reliable(sim)
		"nuclear_support":
			var assignment: Dictionary = sim.evolution.support_assignment(sim,sim.get_building(int(roles.source)),sim.evolution._component(sim,int(roles.source)))
			return assignment.ok and sim.evolution.support_powered(sim,assignment)
		"nuclear_running": return _receipt("facility",int(roles.source)) and float(sim.get_building(int(roles.source)).output)>0.1 and float(sim.get_building(int(roles.source)).startup_remaining)<=0.000001
		"nuclear_reliable": return _reliable(sim) and float(sim.get_building(int(roles.source)).output)>0.1 and _qualifies(sim,"nuclear_support")
		"pumped_connected": return _receipt("build") and _kind_connected(sim,"pumped_storage")
		"storage_charged": return charged_mwh >= 8.0
		"storage_discharged": return discharged_mwh >= 2.0
		"market_actions": return bool(flags.get("market_tariff",false)) and bool(flags.get("market_policy",false))
		"contract_signed": return bool(flags.get("contract_signed",false))
		"contract_settled": return bool(flags.get("contract_signed",false)) and float(sim.market.state.contract_remaining)<=0.000001 and imported_mwh>0.1 and contract_cost>0.1
		"market_reliable": return _reliable(sim) and float(sim.market.state.satisfaction)>=60.0
		"wind_connected":
			var count := 0
			for b in sim.buildings:
				if b.kind=="wind" and _connected(sim,int(b.id),int(roles.node)): count+=1
			return bool(flags.get("build_kind_wind",false)) and count>=2
		"wind_reliable": return _reliable(sim) and float(sim.totals.get("renewable_supply_share",0.0))>=0.35
		"commissioned": return _receipt("commission",int(roles.root)) and sim.digital.devices[int(roles.root)].role=="root"
		"communication_built": return _receipt("communication") and sim.communication_status(int(roles.node)).trusted and sim.communication_status(int(roles.customer)).trusted
		"telemetry": return int(sim.research_level)>=1 and sim.line_observation(int(roles.main_feeder)).visibility=="verified"
		"telemetry_reliable": return _reliable(sim) and _qualifies(sim,"telemetry")
		"remote_executed": return _receipt("remote_switch",int(roles.tie)) and bool(sim.get_line(int(roles.tie)).closed)
		"remote_facility": return int(sim.research_level)>=2 and bool(flags.get("facility_remote",false))
		"response_executed":
			if not _receipt("response") or float(sim.elapsed_hours)<=float(flags.get("response_started_at",sim.elapsed_hours))+0.000001 or float(sim.demand_response_remaining)<=0.0: return false
			for b in sim.buildings:
				if b.kind in ["home","factory"] and float(b.demand)>0.0 and sim.digital.control_reachable(sim,int(b.id)): return true
			return false
		"assessment_started": return assessment_started
		"auto_restored": return assessment_started and _receipt("remote_switch",int(roles.tie)) and bool(sim.get_line(int(roles.tie)).closed) and _reliable(sim)
		"physical_repaired": return _receipt("repair",int(roles.main_feeder)) and not bool(sim.get_line(int(roles.main_feeder)).fault)
		"isolated_inspected": return _receipt("isolate",int(roles.attack_target)) and bool(sim.digital.devices[int(roles.attack_target)].isolated) and _receipt("inspect",int(roles.main_feeder))
		"trust_restored":
			var device: Dictionary = sim.digital.devices[int(roles.attack_target)]
			return _receipt("patch",int(roles.attack_target)) and not device.intrusion and not device.compromised and not device.isolated and sim.communication_status(int(roles.attack_target)).trusted
		"secure_reliable": return _reliable(sim) and _qualifies(sim,"trust_restored")
		"solar_delivered":
			for b in sim.buildings:
				if b.kind=="solar" and float(b.output)>0.1 and _connected(sim,int(b.id),int(roles.node)): return _receipt("build")
			return false
		"coordinated_storage":
			for b in sim.buildings:
				if b.kind=="community_battery" and b.storage_mode=="peak" and sim.digital.control_reachable(sim,int(b.id)) and bool(flags.get("facility_remote",false)) and bool(flags.get("setting_reserve_soc",false)): return _connected(sim,int(b.id),int(roles.node))
			return false
		"final_assessment": return assessment_started and _reliable(sim) and float(sim.totals.get("renewable_supply_share",0.0))>=0.5
	return false

func _next(sim: RefCounted) -> void:
	hold_hours = 0.0
	step_index += 1
	if step_index >= _steps_cache.size():
		completed = true
		step_index = _steps_cache.size()-1
		sim._log("历史章节完成「%s」。" % chapter().title,"success")

func _fail(reason: String) -> void:
	failed = true
	failure_reason = reason

func snapshot() -> Dictionary:
	return {"active":active,"chapter_id":chapter_id,"step_index":step_index,"completed":completed,"failed":failed,"failure_reason":failure_reason,"roles":roles.duplicate(true),"required_customers":required_customers.duplicate(),"flags":flags.duplicate(true),"hold_hours":hold_hours,"charged_mwh":charged_mwh,"discharged_mwh":discharged_mwh,"imported_mwh":imported_mwh,"contract_cost":contract_cost,"assessment_net":assessment_net,"critical_outage_hours":critical_outage_hours,"assessment_started":assessment_started,"initial_customer_count":initial_customer_count}

func load_snapshot(data: Variant) -> bool:
	if not valid_snapshot(data): return false
	active = bool(data.active)
	if not active: return true
	chapter_id=int(data.chapter_id); step_index=int(data.step_index)
	completed=bool(data.completed); failed=bool(data.failed); failure_reason=str(data.failure_reason)
	roles=data.roles.duplicate(true)
	for key in roles: roles[key]=int(roles[key])
	required_customers.clear()
	for id in data.required_customers: required_customers.append(int(id))
	flags=data.flags.duplicate(true)
	for key in flags:
		if not flags[key] is bool: flags[key]=float(flags[key]) if str(key).ends_with("_at") else int(flags[key])
	hold_hours=float(data.hold_hours); charged_mwh=float(data.charged_mwh); discharged_mwh=float(data.discharged_mwh)
	imported_mwh=float(data.imported_mwh); contract_cost=float(data.contract_cost); assessment_net=float(data.assessment_net)
	critical_outage_hours=float(data.critical_outage_hours); assessment_started=bool(data.assessment_started)
	initial_customer_count=int(data.initial_customer_count)
	return true

static func valid_snapshot(data: Variant) -> bool:
	if not data is Dictionary or not data.get("active") is bool: return false
	if not data.active: return true
	if not _integer(data.get("chapter_id"),1,15): return false
	if not _integer(data.get("step_index"),0,Catalog.steps(int(data.chapter_id)).size()-1): return false
	for key in ["completed","failed","assessment_started"]:
		if not data.get(key) is bool: return false
	if data.completed and data.failed: return false
	var steps := Catalog.steps(int(data.chapter_id))
	if data.completed and int(data.step_index) != steps.size()-1: return false
	if data.assessment_started and int(data.chapter_id) not in [13,14,15]: return false
	if not data.get("failure_reason") is String or data.failure_reason.length()>300: return false
	for key in ["hold_hours","charged_mwh","discharged_mwh","imported_mwh","contract_cost","critical_outage_hours"]:
		if not _number(data.get(key),0.0,1e12): return false
	if float(data.hold_hours) > float(steps[int(data.step_index)].hold_hours)+0.000001: return false
	if not _number(data.get("assessment_net"),-1e15,1e15): return false
	if not _integer(data.get("initial_customer_count"),1,512): return false
	if not data.get("roles") is Dictionary or data.roles.size()>100: return false
	for key in data.roles:
		if not key is String or key.length()>80 or not _integer(data.roles[key],1,2000): return false
	for key in ["source","node","customer"]:
		if not data.roles.has(key): return false
	if int(data.chapter_id)>=2 and not data.roles.has("main_feeder"): return false
	if int(data.chapter_id)>=11 and not data.roles.has("root"): return false
	if int(data.chapter_id) in [4,12,13,14]:
		if not data.roles.has("backup") or not data.roles.has("main_feeder"): return false
	if int(data.chapter_id) in [12,13,14] and not data.roles.has("tie"): return false
	if int(data.chapter_id) in [7,13,14,15] and not data.roles.has("hospital"): return false
	if int(data.chapter_id)==14 and not data.roles.has("attack_target"): return false
	if not data.get("required_customers") is Array or data.required_customers.is_empty() or data.required_customers.size()>512: return false
	var seen := {}
	for id in data.required_customers:
		if not _integer(id,1,1000000000) or seen.has(int(id)): return false
		seen[int(id)] = true
	if not data.get("flags") is Dictionary or data.flags.size()>2048: return false
	for key in data.flags:
		if not key is String or key.length()>100 or not (data.flags[key] is bool or _number(data.flags[key],0.0,1e12)): return false
	return true

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value,float(minimum),float(maximum)) and float(value)==floorf(float(value))

func _result(ok: bool, message: String) -> Dictionary:
	return {"ok":ok,"message":message,"id":chapter_id}
