extends SceneTree
## Department contracts, urgency, provenance and the player-information boundary.
const Sim = preload("res://scripts/sim/grid_sim.gd")
const Attention = preload("res://scripts/ui/attention_model.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func _initialize() -> void:
	_contracts()
	_hidden_truth()
	_evidence_and_priority()
	_finance_and_resources()
	_customer_meter_boundary()
	_empty_and_migrated()
	print("ATTENTION MODEL: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)

func network() -> RefCounted:
	var sim: RefCounted = Sim.new()
	sim.buildings.clear()
	sim.lines.clear()
	sim.next_building_id = 1
	sim.next_line_id = 1
	sim._add_building("gas",Vector2i(2,3))
	sim._add_building("substation",Vector2i(5,3))
	sim._add_building("hospital",Vector2i(8,3))
	sim._add_building("factory",Vector2i(6,6))
	sim._add_building("home",Vector2i(3,6))
	sim._add_line(1,2)
	sim._add_line(2,3)
	sim._add_line(2,4)
	sim._add_line(2,5)
	sim.digital.reset(sim)
	sim._refresh()
	return sim

func state(sim: RefCounted) -> String:
	return JSON.stringify(sim.snapshot(),"",true,true) + JSON.stringify(sim.operation_receipts(),"",true,true)

func views(sim: RefCounted) -> String:
	var data: Array = [Attention.global_kpis(sim)]
	for lens in Attention.LENSES: data.append(Attention.snapshot(sim,lens))
	return JSON.stringify(data,"",true,true)

func find_id(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if str(row.get("id","")) == id: return row
	return {}

func asset(rows: Array, kind: String, id: int) -> Dictionary:
	for row in rows:
		if row.target_type == kind and int(row.id) == id: return row
	return {}

func _contracts() -> void:
	var sim := network()
	var original := state(sim)
	var global: Array[Dictionary] = Attention.global_kpis(sim)
	check(global.map(func(row: Dictionary): return str(row.id)) == ["supply","reliability","economy","carbon","asset","observability"],"six global outcomes keep stable report IDs")
	for lens in Attention.LENSES:
		var first: Dictionary = Attention.snapshot(sim,lens,"engineer")
		check(first.lens == lens and first.title == Attention.TITLES[lens] and not first.purpose.is_empty(),"department identity and purpose: " + lens)
		check(first.risks.size()<=5 and first.cross_lens.size()<=3,"bounded attention and related department links: " + lens)
		check(not first.kpis.is_empty(),"department has useful operating metrics: " + lens)
		for metric in first.kpis:
			var complete := true
			for key in ["id","label","value","unit","detail","source","confidence","target_type","target_id"]:
				complete = complete and metric.has(key)
			check(complete and not metric.source.is_empty() and metric.confidence in ["public","trusted","field","stale","unknown"],"unified KPI provenance: " + str(metric.id))
		for risk in first.risks:
			var complete := true
			for key in ["id","severity","title","detail","source","confidence","target_type","target_id","action","lens","consequence","urgency"]:
				complete = complete and risk.has(key)
			check(complete and risk.lens in Attention.LENSES and not risk.has("_order"),"risk explains urgency, consequence and navigation without an opaque score")
		check(JSON.stringify(first)==JSON.stringify(Attention.snapshot(sim,lens,"engineer")),"department queries are deterministic: " + lens)
	check(state(sim)==original,"all department queries preserve the world, clock, money, observations, RNG and queues")
	var fallback: Dictionary = Attention.snapshot(sim,"missing","missing")
	check(fallback.lens=="operations" and fallback.depth=="operator","unknown preferences fall back to valid department and depth")
	for depth in ["beginner","operator","engineer"]:
		check(Attention.snapshot(sim,"operations",depth).depth==depth,"canonical display depth is accepted: "+depth)

func _hidden_truth() -> void:
	var sim := network()
	sim.digital.observations.clear()
	sim.digital.facility_observations.clear()
	var original := views(sim)
	for building in sim.buildings:
		building.health = 0.0
		building.online = not bool(building.online)
		building.available = 9876.0
		building.output = 6543.0
		building.energy = 4321.0
		building.lifecycle_failure = true
	for line in sim.lines:
		line.fault = true
		line.closed = false
		line.flow = 9987.0
		line.health = 0.0
		line.heat = 999.0
	check(views(sim)==original,"changing unobserved health, faults, output, energy and switch states cannot alter any department view")
	var unknown: Dictionary = Attention.snapshot(sim,"assets")
	check(unknown.assets.all(func(row: Dictionary): return row.health==null and row.confidence=="unknown"),"unknown health stays null rather than zero or hidden truth")
	check(find_id(Attention.global_kpis(sim),"asset").value==null,"global asset health remains unknown when no current evidence exists")
	check(find_id(Attention.global_kpis(sim),"reliability").value==0,"hidden line overloads and faults are excluded from known safety counts")
	var digital := Attention.snapshot(sim,"digital")
	check(not find_id(digital.risks,"observation_gap").is_empty(),"missing observations create an explicit information task")

func _evidence_and_priority() -> void:
	var sim := network()
	sim.get_building(3).powered = false
	sim.get_building(3).health = 42.0
	sim.digital._sample_facility(sim,sim.get_building(3),"field")
	var overloaded: Dictionary = sim.get_line(1)
	overloaded.flow = float(overloaded.capacity)*1.3
	sim.digital._sample(sim,overloaded,"patrol")
	var known_fault: Dictionary = sim.get_line(3)
	known_fault.fault = true
	sim.digital._sample(sim,known_fault,"patrol")
	var operations: Dictionary = Attention.snapshot(sim,"operations")
	check(not operations.risks.is_empty() and operations.risks[0].id=="customer_3","public hospital interruption ranks ahead of known thermal and repair concerns")
	check(operations.risks[0].confidence=="public" and operations.risks[0].target_id==3,"hospital priority comes from public feedback and keeps its exact actionable target")
	var thermal: Dictionary = find_id(operations.risks,"line_load_1")
	check(not thermal.is_empty() and thermal.confidence=="field" and "保护" in thermal.consequence,"verified overload carries field provenance and explicit protection consequence")
	var assets: Dictionary = Attention.snapshot(sim,"assets")
	var hospital: Dictionary = asset(assets.assets,"facility",3)
	var hospital_line: Dictionary = asset(assets.assets,"line",2)
	check(hospital.health==42.0 and hospital.confidence=="field","asset matrix reads sampled health and preserves field confidence")
	check(hospital.criticality==1.0 and hospital_line.criticality==1.0 and "代理" in hospital.criticality_detail,"hospital and adjacent line impact use an explicitly labeled public topology proxy")
	check(assets.assets.all(func(row: Dictionary): return float(row.criticality)>=0 and float(row.criticality)<=1),"asset criticality uses normalized categories suitable for the matrix")
	sim.get_building(3).health = 1.0
	check(asset(Attention.snapshot(sim,"assets").assets,"facility",3).health==42.0,"live hidden deterioration cannot replace the player's sampled health")
	sim.get_building(3).inspected_at = 0.0
	sim.get_building(3).inspected_health = 42.0
	sim.elapsed_hours = 1.25
	var stale: Dictionary = asset(Attention.snapshot(sim,"assets").assets,"facility",3)
	check(stale.health==42.0 and stale.confidence=="stale" and not stale.current_verified,"expired inspections keep past health explicitly stale")
	var stale_risk: Dictionary = find_id(Attention.snapshot(sim,"assets").risks,"asset_facility_3")
	check(not stale_risk.is_empty() and stale_risk.action=="observe" and "复核" in stale_risk.title,"past low health asks for verification rather than declaring a current fault")
	check(find_id(Attention.global_kpis(sim),"asset").value==null,"expired readings are excluded from current minimum-health KPI")

func _finance_and_resources() -> void:
	var sim := network()
	sim.lifecycle.enabled = true
	sim.lifecycle.spares = 0
	sim.get_building(1).repair_remaining = 1.0
	sim.get_line(1).repair_remaining = 1.0
	sim.lifecycle.jobs.append({"id":41,"target_type":"facility","target_id":2,"action":"inspect","priority":0,"status":"queued","travel_remaining":.2,"work_remaining":.1,"cost":250.0,"spares":0,"queued_at":0.0,"original_online":true,"original_closed":true})
	sim.strategy.state.loans.append({"id":31,"principal":12000.0,"daily_rate":.005,"due":-1.0})
	sim.cash = -100.0
	sim.totals.income = 50.0
	sim.totals.expenses = 400.0
	var market: Dictionary = Attention.snapshot(sim,"market")
	check(market.risks[0].id=="cash_negative" and not find_id(market.risks,"loan_31").is_empty(),"negative cash and signed overdue debt produce concrete finance priorities")
	check(find_id(market.kpis,"economy").value==-350.0 and find_id(market.kpis,"debt").value==12000.0,"net operating rate and loan principal remain distinct")
	var maintenance: Dictionary = Attention.snapshot(sim,"maintenance")
	check(not find_id(maintenance.risks,"crew_queue").is_empty() and not find_id(maintenance.risks,"spares").is_empty(),"full crews and stockout produce actionable maintenance concerns")
	check(find_id(maintenance.kpis,"maintenance_queue").value==1,"queued maintenance is counted separately from active field crews")
	check(market.cross_lens.any(func(row: Dictionary): return row.lens=="maintenance"),"related department action bridges finance and constrained field resources")

func _customer_meter_boundary() -> void:
	var sim := network()
	sim.customers.enabled = true
	var meter: Dictionary = sim.customers._defaults(sim)
	meter.metered = true
	meter.ev_mw = 2.0
	meter.ev_target_mwh = 10.0
	meter.ev_remaining_mwh = 8.0
	meter.energy_mwh = 7.0
	meter.deadline_hour = 9.0
	sim.customers.devices["5"] = meter
	var before: Dictionary = Attention.snapshot(sim,"customers")
	var home: Dictionary = asset(before.customers,"facility",5)
	check(home.ev_remaining_mwh==null and home.energy_mwh==null and home.meter_confidence=="unknown","no meter sample reveals neither stored energy nor charging obligations")
	check(find_id(before.kpis,"ev_obligation").value==null and find_id(before.risks,"charging_5").is_empty(),"unknown charging total remains null and cannot create an exact deadline alert")
	var stable := JSON.stringify(before)
	meter.ev_remaining_mwh = 999.0
	meter.energy_mwh = 999.0
	meter.shift_debt_mwh = 999.0
	meter.fatigue = .99
	check(JSON.stringify(Attention.snapshot(sim,"customers"))==stable,"hidden meter energy, deferred demand and fatigue cannot change customer lens")
	# A fresh meter plus a functioning public control path can support a deadline.
	sim._add_building("control",Vector2i(4,4))
	sim._add_line(2,6)
	sim.evolution.unlocked.append("scada")
	sim.research_level = 2
	sim.digital.reset(sim)
	sim.digital.commission_initial(sim,6)
	sim._refresh()
	sim.digital._sample_facility(sim,sim.get_building(5),"field")
	sim.customers.telemetry["5"]={"sampled_at":float(sim.elapsed_hours),"energy_mwh":7.0,"ev_remaining_mwh":8.0,"shift_debt_mwh":2.0,"fatigue":.1}
	var current: Dictionary = Attention.snapshot(sim,"customers")
	check(asset(current.customers,"facility",5).ev_remaining_mwh==8.0,"fresh trusted meter uses sampled EV obligation rather than live hidden value")
	check(not find_id(current.risks,"charging_5").is_empty(),"known remaining charge and signed deadline produce a customer task")
	sim.elapsed_hours += .3
	var expired: Dictionary = Attention.snapshot(sim,"customers")
	check(asset(expired.customers,"facility",5).ev_remaining_mwh==null and find_id(expired.risks,"charging_5").is_empty(),"expired meter removes exact charging amount and deadline inference")
	var persistent: RefCounted = Sim.new()
	persistent.step(.1)
	var reliable_view: Dictionary = Attention.snapshot(persistent,"customers")
	check(not find_id(reliable_view.kpis,"saidi").is_empty() and "负荷点口径" in find_id(reliable_view.kpis,"saidi").detail,"reliability KPIs state the aggregate supply-point denominator and window")

func _empty_and_migrated() -> void:
	check(Attention.snapshot(null).risks.is_empty() and Attention.global_kpis(null).is_empty(),"absent session produces safe empty view")
	var sim := network()
	sim.buildings.clear()
	sim.lines.clear()
	sim.digital.reset(sim)
	sim._refresh()
	for lens in Attention.LENSES:
		var data := Attention.snapshot(sim,lens)
		check(data.assets.is_empty() and data.customers.is_empty() and data.risks.size()<=5,"empty grid supports department: " + lens)
	var baseline: RefCounted = Sim.new()
	var save: Dictionary = baseline.snapshot()
	save.schema_version = 7
	for key in ["planning","lifecycle","engineering","customers","strategy","reliability_metrics"]: save.erase(key)
	var restored: RefCounted = Sim.new()
	var result: Dictionary = restored.restore_snapshot(save)
	check(result.ok,"old baseline can migrate before department display")
	if result.ok:
		var original := state(restored)
		for lens in Attention.LENSES: Attention.snapshot(restored,lens)
		check(state(restored)==original and not restored.lifecycle.enabled and not restored.engineering.enabled,"departments leave migrated advanced systems uncommissioned and preserve state")
