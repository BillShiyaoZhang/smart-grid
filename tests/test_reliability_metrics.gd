extends SceneTree
const Sim = preload("res://scripts/sim/grid_sim.gd")
const Metrics = preload("res://scripts/sim/reliability_metrics.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	_exact_metrics()
	_save_continuation()
	_history_and_population()
	_information_boundary()
	_additional_work_receipts()
	_validation_and_migration()
	_actual_simulation()
	print("RELIABILITY METRICS: %d checks; %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL: "+message)

func near(a: float,b: float) -> bool:
	return absf(a-b)<.00001

func world() -> RefCounted:
	var sim:=Sim.new()
	sim.next_storm_at=10000
	sim.digital.next_attack_at=10000
	return sim

func sample(sim: RefCounted,hours: float,fractions: Dictionary={}) -> void:
	# Exact public outcome fixture; electrical integration is checked separately.
	for b in sim.buildings:
		if b.kind in ["home","factory","hospital"]:
			b.demand=10.0
			b.served=10.0*float(fractions.get(int(b.id),1.0))
	sim.elapsed_hours=round((float(sim.elapsed_hours)+hours)*1e9)/1e9
	sim.reliability_metrics.advance(sim,hours)

func _exact_metrics() -> void:
	var sim:=world()
	var empty: Dictionary=sim.reliability_metrics.report(sim)
	check(empty.summary.enrolled_points==0 and empty.summary.active_points==4,"new window declares no fabricated history and four current aggregate supply points")
	check("不是居民户数" in empty.summary.scope_description and empty.summary.scope=="负荷点口径","customer denominator explicitly states aggregate-point scope")
	sample(sim,.5,{3:0.0,5:.5})
	var report: Dictionary=sim.reliability_metrics.report(sim)
	var summary: Dictionary=report.summary
	check(summary.enrolled_points==4 and summary.interruption_count==2,"each disconnected or partially interrupted point enters the fixed cohort once")
	check(near(summary.cmi,60) and near(summary.saidi_minutes,15),"two thirty-minute point interruptions yield 60 CMI and 15-minute SAIDI")
	check(near(summary.saifi,.5) and near(summary.caidi_minutes,30),"SAIFI and CAIDI use the declared supply-point count")
	check(near(summary.ens_mwh,7.5) and near(summary.below_threshold_ens_mwh,0),"ENS integrates actual missing MWh including partial service")
	check(report.incidents.size()==2 and report.incidents[0].critical and report.incidents[0].facility_id==5,"ongoing hospital event sorts before ordinary load")
	check(report.incidents[0].affected_load_ids==[5] and near(report.incidents[0].duration_minutes,30),"incident exposes public affected IDs and actual duration")
	var initial: Dictionary=sim.reliability_metrics.snapshot()
	sim.reliability_metrics.advance(sim,.5)
	check(sim.reliability_metrics.snapshot()==initial,"repeating settlement at the same timestamp cannot double count")
	for _i in 4: sim.reliability_metrics.report(sim)
	check(sim.reliability_metrics.snapshot()==initial,"opening or refreshing reports does not advance longitudinal metrics")
	sample(sim,.25)
	report=sim.reliability_metrics.report(sim)
	check(report.incidents.is_empty() and report.events.size()==2,"public restoration closes both interruption episodes")
	check(near(report.summary.cmi,60) and near(report.events[0].end,.5),"first restored interval adds no false interruption minutes")
	check("供电恢复" in report.events[0].after_action and "不作推断" in report.events[0].after_action,"after-action report separates observed restoration from unknown cause")
	sample(sim,.25,{3:.97})
	check(sim.reliability_metrics.report(sim).summary.interruption_count==3,"a new sub-98-percent interruption increments frequency after recovery")
	sample(sim,.25,{3:.98})
	report=sim.reliability_metrics.report(sim)
	check(report.incidents.is_empty() and near(report.summary.cmi,75),"exactly 98-percent service is outside interruption threshold")
	check(near(report.summary.ens_mwh,7.625) and near(report.summary.below_threshold_ens_mwh,.05),"ENS keeps small sub-threshold deficits separately for reconciliation")
	var cmi:=0.0
	var ens:=float(report.summary.below_threshold_ens_mwh)
	var saidi:=0.0
	for event in report.events:
		cmi+=float(event.cmi)
		ens+=float(event.ens_mwh)
		saidi+=float(event.saidi_contribution_minutes)
	check(near(cmi,report.summary.cmi) and near(ens,report.summary.ens_mwh),"event contributions conserve CMI and total ENS")
	check(near(saidi,report.summary.saidi_minutes),"per-event SAIDI contributions sum to the cumulative indicator")
	check(not report.trend.is_empty() and near(report.trend[-1].cmi,75),"bounded trend records actual cumulative outcomes")

func _save_continuation() -> void:
	var sim:=world()
	sample(sim,.5,{3:0.0,5:.5})
	var loaded:=world()
	var stored: Dictionary=JSON.parse_string(JSON.stringify(sim.snapshot()))
	check(loaded.restore_snapshot(stored).ok,"JSON save restores ongoing interruptions")
	check(loaded.reliability_metrics.snapshot()==sim.reliability_metrics.snapshot(),"save preserves cohort, active episodes, integration and event IDs")
	sample(sim,.25,{3:0.0,5:.5})
	sample(loaded,.25,{3:0.0,5:.5})
	check(loaded.reliability_metrics.snapshot()==sim.reliability_metrics.snapshot(),"continuation after load produces the same longitudinal state")
	var report: Dictionary=loaded.reliability_metrics.report(loaded)
	check(report.summary.interruption_count==2 and near(report.summary.cmi,90) and near(report.summary.ens_mwh,11.25),"loading does not reopen active episodes or lose their accrued minutes")
	check(Metrics.valid_snapshot(loaded.reliability_metrics.snapshot(),loaded.elapsed_hours,loaded.next_building_id),"continued ongoing state passes atomic save validation")

func _history_and_population() -> void:
	var sim:=world()
	for _i in 205:
		sample(sim,.01,{3:0.0})
		sample(sim,.01)
	var report: Dictionary=sim.reliability_metrics.report(sim)
	check(report.events.size()==200 and report.summary.archived.interruption_count==5,"history compaction retains two hundred detailed episodes and exact archived count")
	check(report.summary.interruption_count==205 and near(report.summary.cmi,123),"history compaction preserves cumulative CMI and frequency")
	check(near(report.summary.ens_mwh,20.5) and near(report.summary.archived.ens_mwh,.5),"history compaction preserves MWh contributions")
	check(Metrics.valid_snapshot(sim.reliability_metrics.snapshot(),sim.elapsed_hours,sim.next_building_id),"compacted event archive remains a valid conserved save")
	sim.cash=1000000
	var added: Dictionary=sim.build("home",Vector2i(11,11))
	check(added.ok,"population test creates an actual new supply point")
	sample(sim,.1,{int(added.get("id",-1)):0.0})
	check(sim.reliability_metrics.report(sim).summary.enrolled_points==5,"new service enrollment extends cumulative point cohort once")
	var removed: Dictionary=sim.demolish(int(added.id))
	check(removed.ok,"population test removes an actually enrolled supply point")
	sample(sim,.1)
	report=sim.reliability_metrics.report(sim)
	check(report.summary.enrolled_points==5 and report.summary.active_points==4,"demolition does not erase historical cohort or improve indicator by shrinking its denominator")
	check(report.events[0].outcome=="服务点已移除" and not report.events[0].has_target,"removal closes event without falsely declaring electrical restoration")
	check(Metrics.valid_snapshot(sim.reliability_metrics.snapshot(),sim.elapsed_hours,sim.next_building_id),"event history may reference a removed point without corrupting save")
	for _i in 100: sample(sim,1.0)
	check(sim.reliability_metrics.report(sim).trend.size()==96,"trend history stays bounded during long operations")
	var managed:=world()
	managed.start_management_game(42)
	managed.management.state.stage=5
	managed.explore_region()
	sample(managed,.1)
	var active:=0
	for b in managed.buildings:
		if b.kind in ["home","factory","hospital"] and managed.customer_service_active(int(b.id)): active+=1
	check(managed.reliability_metrics.report(managed).summary.enrolled_points==active,"prospective cities outside the service obligation are excluded from reliability cohort")
	check(active<managed.buildings.size(),"prospective-city case includes facilities outside the enrolled supply-point set")

func _information_boundary() -> void:
	var sim:=world()
	sim.digital.observations.clear()
	sim.digital.facility_observations.clear()
	sample(sim,.1,{3:0.0})
	var before: Dictionary=sim.reliability_metrics.report(sim)
	sim.get_line(1).fault=true
	sim.get_line(1).closed=false
	sim.get_building(1).health=2.0
	check(sim.reliability_metrics.report(sim)==before,"hidden physical failure and health do not leak through reliability report")
	check("原因待核实" in before.incidents[0].cause,"public customer interruption does not imply a known fault cause")
	sim.record_campaign_action("field_switch",2,{"phase":"executed","method":"field"})
	sample(sim,.1,{3:0.0})
	check(not sim.reliability_metrics.report(sim).incidents[0].actions.is_empty(),"relevant executed field receipt is retained as evidence of an action")
	var state_before: Dictionary=sim.snapshot()
	var result: Dictionary=sim.planning.forecast(sim,{},1)
	check(result.ok and sim.snapshot()==state_before,"disposable forecast cannot record interruptions in the real reliability window")

func _validation_and_migration() -> void:
	var sim:=world()
	sample(sim,.1,{3:0.0})
	var good: Dictionary=sim.snapshot()
	var mutations: Array=[]
	var broken: Dictionary=good.duplicate(true)
	broken.reliability_metrics.cmi+=1
	mutations.append(broken)
	broken=good.duplicate(true)
	broken.reliability_metrics.ens_mwh+=1
	mutations.append(broken)
	broken=good.duplicate(true)
	broken.reliability_metrics.next_event+=1
	mutations.append(broken)
	broken=good.duplicate(true)
	broken.reliability_metrics.active["3"].end=-.5
	mutations.append(broken)
	broken=good.duplicate(true)
	broken.reliability_metrics.active["3"].critical=true
	mutations.append(broken)
	broken=good.duplicate(true)
	broken.reliability_metrics.roster["3"].weight=100
	mutations.append(broken)
	broken=good.duplicate(true)
	broken.reliability_metrics.trend[0].hour=1000
	mutations.append(broken)
	broken=good.duplicate(true)
	broken.erase("reliability_metrics")
	mutations.append(broken)
	broken=good.duplicate(true)
	broken.reliability_metrics.interruption_count+=1
	broken.reliability_metrics.next_event+=1
	broken.reliability_metrics.archived.interruption_count=1
	broken.reliability_metrics.archived.cmi=1e12
	broken.reliability_metrics.cmi+=1e12
	mutations.append(broken)
	broken=good.duplicate(true)
	broken.reliability_metrics.roster["3"].kind="factory"
	mutations.append(broken)
	broken=good.duplicate(true)
	broken.reliability_metrics.roster["3"].city_id=0
	mutations.append(broken)
	broken=good.duplicate(true)
	broken.reliability_metrics.active["3"].city_id=0
	mutations.append(broken)
	broken=good.duplicate(true)
	broken.reliability_metrics.roster["10"]=broken.reliability_metrics.roster["3"].duplicate(true)
	broken.reliability_metrics.roster["10"].facility_id=10
	broken.reliability_metrics.roster.erase("3")
	broken.reliability_metrics.active["10"]=broken.reliability_metrics.active["3"].duplicate(true)
	broken.reliability_metrics.active["10"].facility_id=10
	broken.reliability_metrics.active.erase("3")
	mutations.append(broken)
	for index in mutations.size():
		check(not sim.restore_snapshot(mutations[index]).ok,"malformed reliability record is rejected atomically: %d" % index)
		check(sim.snapshot()==good,"failed reliability validation leaves the live game intact: %d" % index)
	for schema in range(1,9):
		var legacy: Dictionary=good.duplicate(true)
		legacy.schema_version=schema
		legacy.erase("reliability_metrics")
		var loaded:=world()
		check(loaded.restore_snapshot(legacy).ok,"schema %d migration still loads" % schema)
		var report: Dictionary=loaded.reliability_metrics.report(loaded)
		check(report.summary.interruption_count==0 and near(report.summary.cmi,0) and near(report.summary.started_at,float(good.elapsed_hours)),"schema %d migration starts fresh declared window without fabricated past" % schema)
		check(loaded.snapshot().schema_version==9,"legacy migration writes schema9 on next save")
	var retired:=world()
	sample(retired,.1,{3:0.0})
	check(retired.demolish(3).ok,"actual enrolled load can be retired between simulation ticks")
	var fresh:=world()
	check(fresh.restore_snapshot(retired.snapshot()).ok,"immediate save after retirement reconciles live roster while retaining ended history")
	check(fresh.reliability_metrics.report(fresh).summary.enrolled_points==4,"retired historical point still belongs to the cumulative denominator")
	var renamed:=world()
	sample(renamed,.1,{3:0.0})
	renamed.get_building(3).name="新住宅名称"
	check(fresh.restore_snapshot(renamed.snapshot()).ok,"public rename may differ from recorded historical or enrollment name")
	var regional:=world()
	sample(regional,.1,{3:0.0})
	check(regional.expand_region().ok,"region expansion assigns pre-existing points to public city identities")
	check(fresh.restore_snapshot(regional.snapshot()).ok,"immediate region-expansion save reconciles existing roster city identities")
	var large_cohort: Dictionary=good.duplicate(true)
	large_cohort.next_building_id=2000
	large_cohort.reliability_metrics.enrolled_points=1000
	check(fresh.restore_snapshot(large_cohort).ok,"cumulative cohort may exceed concurrent-world capacity after historical retirements")
	large_cohort.reliability_metrics.interruption_count+=1
	large_cohort.reliability_metrics.next_event+=1
	large_cohort.reliability_metrics.archived.interruption_count=1
	large_cohort.reliability_metrics.archived.cmi=5000
	large_cohort.reliability_metrics.cmi+=5000
	check(not fresh.restore_snapshot(large_cohort).ok,"archive cannot exceed 512 concurrent point-minute budget even with a larger retired cohort")

func _additional_work_receipts() -> void:
	var sim:=world()
	sim.lifecycle.enable(sim)
	sim.get_building(3).online=false
	sim.get_building(3).health=40.0
	sim.get_building(3).lifecycle_failure=true
	sim._refresh()
	sim.step(.1)
	check(sim.lifecycle.maintenance(sim,"facility",3,"overhaul").ok,"actual lifecycle overhaul is accepted for the interrupted load")
	sim.step(2.0)
	var report: Dictionary=sim.reliability_metrics.report(sim)
	var rows: Array=report.events.duplicate()
	rows.append_array(report.incidents)
	var recorded:=false
	for event in rows:
		if int(event.facility_id)==3:
			for action in event.actions:
				if "部件大修" in action and "已执行" in action: recorded=true
	check(recorded,"incident retains actual completed lifecycle work without misreporting no operation record")
	var micro:=world()
	micro.customers.enabled=true
	micro.get_building(3).online=false
	micro._refresh()
	micro.step(.1)
	var partition: Dictionary=micro.customers.define_microgrid(micro,"公开分区",[1,2,3],[3])
	check(partition.ok and micro.customers.set_microgrid(micro,int(partition.id),true,"field").ok,"actual microgrid member point has an accepted field-switch job")
	micro.step(.2)
	var has_pending_receipt:=false
	for event in micro.reliability_metrics.report(micro).incidents:
		if int(event.facility_id)==3:
			for action in event.actions:
				if "微电网" in action: has_pending_receipt=true
	check(not has_pending_receipt,"in-transit microgrid task is not recorded as an executed incident action")
	micro.step(.2)
	var has_completed_receipt:=false
	var invented_method:=false
	for event in micro.reliability_metrics.report(micro).incidents:
		if int(event.facility_id)==3:
			for action in event.actions:
				if "微电网" in action and "已执行" in action: has_completed_receipt=true
				if "微电网" in action and "远程" in action: invented_method=true
	check(has_completed_receipt,"explicit completed public microgrid event is attached only to its member's incident")
	check(not invented_method,"microgrid event without a saved execution method never invents remote operation")

func _actual_simulation() -> void:
	var sim:=world()
	sim.step(.5)
	var report: Dictionary=sim.reliability_metrics.report(sim)
	check(near(report.summary.ens_mwh,float(sim.total_demand_mwh)-float(sim.total_served_mwh)),"actual tick metrics reconcile aggregate customer energy deficit")
	check(report.summary.interruption_count>=1 and report.incidents.size()>=1,"actual disconnected industrial load produces a longitudinal incident")
	check(near(report.summary.elapsed_hours,.5),"only real simulation time advances reliability observation window")
	var saved: Dictionary=sim.snapshot()
	check(sim.restore_snapshot(JSON.parse_string(JSON.stringify(saved))).ok,"actual integrated metrics survive JSON save/restore")
	sim.reset()
	check(sim.reliability_metrics.report(sim).summary.interruption_count==0,"new game resets prior-session reliability statistics")
