extends SceneTree
## Cross-system acceptance: real dispatch, real command queues and atomic JSON
## restore, with all modernization modules operating in the same world.

const Sim=preload("res://scripts/sim/grid_sim.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	_test_combined_operations()
	_test_construction_entrypoints()
	_test_shared_crews_and_persistence()
	_test_atomic_cross_references()
	_test_forecast_information_boundary()
	_test_local_protection_and_demolition()
	_test_transformer_selectivity()
	print("EXPANSION ACCEPTANCE: %d checks; %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+message)

func equivalent(a: Variant,b: Variant,tolerance: float=0.0000001) -> bool:
	if (a is float or a is int) and (b is float or b is int): return absf(float(a)-float(b))<=tolerance
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key],tolerance): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for index in a.size():
			if not equivalent(a[index],b[index],tolerance): return false
		return true
	return a==b

func modern() -> RefCounted:
	var sim=Sim.new()
	sim.cash=1000000.0
	sim.research_level=2
	sim.next_storm_at=10000.0
	sim.digital.next_attack_at=10000.0
	sim.connect_buildings(2,6)
	sim.engineering.enable(sim)
	sim.customers.enable(sim)
	sim.lifecycle.enable(sim)
	sim.strategy.enable(sim)
	sim._refresh()
	sim.digital.sample_verified(sim)
	return sim

func copy_world(sim: RefCounted) -> RefCounted:
	var clone=Sim.new()
	var data: Dictionary=JSON.parse_string(JSON.stringify(sim.snapshot(),"",true,true))
	check(clone.restore_snapshot(data).ok,"combined snapshot restores atomically through actual validator")
	return clone

func cash_balances(sim: RefCounted) -> bool:
	var report: Dictionary=sim.planning.report(sim)
	var computed:=float(report.opening_cash)
	for entry in report.cash_entries: computed+=float(entry.amount)
	return absf(computed-float(sim.cash))<0.00001 and absf(float(report.cash_balance)-float(sim.cash))<0.00001

func nodal_balances(sim: RefCounted) -> bool:
	if absf(float(sim.totals.energy_balance_error))>0.00001: return false
	for b in sim.buildings:
		var outgoing:=0.0
		for line in sim.lines:
			if int(line.a)==int(b.id): outgoing+=float(line.flow)
			if int(line.b)==int(b.id): outgoing-=float(line.flow)
		var injected:=float(b.output)-float(b.served)-float(b.charging)-float(b.get("network_loss_mw",0.0))
		if absf(injected-outgoing)>0.00001: return false
	return true

func _test_combined_operations() -> void:
	var sim=modern()
	sim.get_building(7).enabled=false
	sim.get_building(8).enabled=false
	var intertie: Dictionary=sim._add_building("intertie",Vector2i(2,4))
	sim._add_line(int(intertie.id),2)
	check(sim.customers.configure(sim,3,{"metered":true,"consent":true,"participation":1.0,"pv_mw":6.0,"battery_mwh":12.0,"battery_mw":3.0,"ev_mw":2.0,"ev_target_mwh":4.0,"deadline_hour":12.0,"smart":true}).ok,"AMI, solar, battery and EV contracts share one real load aggregate")
	check(sim.engineering.configure_line(sim,1,"transmission",0.75).ok,"backbone voltage upgrade is a real paid action")
	check(sim.engineering.configure_substation(sim,2,50.0,"海湾供电区").ok,"transformer bottleneck can be uprated independently")
	check(sim.strategy.take_loan(sim,24000,48).ok,"construction debt is live alongside energy settlement")
	check(sim.strategy.start_project(sim,"substation",Vector2i(13,4)).ok,"new capital asset remains under construction")
	check(sim.strategy.submit_day_ahead(sim,[3.0,4.0,5.0]).ok,"hourly physical import promises accepted alongside retail load")
	check(sim.strategy.configure_policy(sim,{"carbon_price":12.0,"production_subsidy":4.0,"tariff_cap":140.0}).ok,"emission and affordability constraints join actual settlement")
	sim._refresh()
	sim.digital.sample_verified(sim)
	check(sim.customers.demand_response(sim,3,"shift",0.35,0.5).ok,"authorized customer receives credible demand response")
	var initial: Dictionary=sim.snapshot()
	var prediction: Dictionary=sim.planning.forecast(sim,{"reserve":0.4},3)
	check(prediction.ok and prediction.rows.size()==3,"same expanded world can produce an isolated operational forecast")
	check(equivalent(sim.snapshot(),initial),"forecast neither bills debt nor advances projects, DR or storage")
	var power_ok:=true
	var accounting_ok:=true
	var loss_seen:=false
	var delivered_forward:=false
	for i in 30:
		sim.step(0.1)
		power_ok=power_ok and nodal_balances(sim)
		accounting_ok=accounting_ok and cash_balances(sim)
		loss_seen=loss_seen or float(sim.totals.network_loss_mw)>0.0001
		delivered_forward=delivered_forward or float(sim.totals.day_ahead_import_mw)>0.01
	check(power_ok,"PV, physical forward imports and resistive loss preserve every network node balance")
	check(accounting_ok,"capital, debt, response compensation and energy charges reconcile to live cash throughout")
	check(loss_seen and delivered_forward,"both real network losses and prepaid physical delivery occur")
	check(float(sim.customers.devices["3"].pv_generated_mwh)>0,"user-owned solar actually produces metered energy")
	check(float(sim.customers.devices["3"].shifted_total_mwh)>0 and float(sim.customers.devices["3"].repaid_total_mwh)>0,"shift creates and later repays an energy obligation")
	check(float(sim.get_building(9).soh)<100 and float(sim.get_building(9).age_hours)>0,"live batteries age while performing network service")
	check(sim.building_at(Vector2i(13,4)).kind=="substation","prepaid construction completes without a second capital charge")
	check(float(sim.strategy.state.forward_cost)>0 and float(sim.strategy.state.interest_paid)>0,"both contract energy and financing accrue actual liabilities")
	var stable: Dictionary=sim.snapshot()
	for i in 3:
		sim._refresh()
		sim.planning.report(sim)
		sim.lifecycle.report(sim)
		sim.customers.report(sim)
	check(equivalent(sim.snapshot(),stable),"workbench refresh cannot repeat degradation, customer energy or contract charges")

func _test_shared_crews_and_persistence() -> void:
	var sim=modern()
	check(sim.lifecycle.maintenance(sim,"facility",7,"inspect",1).ok,"inspection starts one shared field team")
	var grid: Dictionary=sim.customers.define_microgrid(sim,"医院保供",[1,2,5,9],[5])
	check(grid.ok and sim.customers.set_microgrid(sim,int(grid.id),true,"field").ok,"microgrid boundary switching acquires second shared team")
	check(sim.active_repairs()==2,"microgrid and asset inspection share the same two-team budget")
	var cash_before:=float(sim.cash)
	check(not sim.field_switch(2).ok and absf(float(sim.cash)-cash_before)<0.00001,"third independent field operation is rejected without charge")
	check(sim.lifecycle.maintenance(sim,"facility",8,"inspect",0).ok,"additional inspection may wait in priority queue")
	check(sim.active_repairs()==2 and sim.lifecycle.jobs[-1].status=="queued","queued task does not overbook a third crew")
	sim.step(0.1)
	var clone=copy_world(sim)
	check(sim.active_repairs()==clone.active_repairs(),"in-flight shared crew usage survives JSON restore")
	sim.step(1.2)
	clone.step(1.2)
	var first: Dictionary=sim.snapshot()
	var second: Dictionary=clone.snapshot()
	first.erase("log_entries")
	second.erase("log_entries")
	check(equivalent(first,second,0.000001),"mixed queued inspections, isolation and staged recovery continue deterministically")
	check(sim.customers.microgrids[0].islanded and int(sim.customers.microgrids[0].stage)==2,"microgrid physically isolates and restores critical then ordinary loads")
	check(sim.active_repairs()==0,"completed modernization work releases shared crews")
	check(nodal_balances(sim) and cash_balances(sim),"reconfigured islands retain both physical and financial conservation")

func _test_construction_entrypoints() -> void:
	var sim=modern()
	var cell:=Vector2i(13,3)
	var preview: Dictionary=sim.preview_build("gas",cell)
	var before:=float(sim.cash)
	var count: int=sim.buildings.size()
	var result: Dictionary=sim.build("gas",cell)
	check(result.ok and int(result.id)==-1 and result.has("project_id") and sim.buildings.size()==count,"ordinary large-facility build routes into real construction instead of bypassing lead time")
	check(absf(before-float(sim.cash)-float(preview.cost))<0.00001 and absf(float(preview.cost)-38000.0*1.03)<0.00001,"build preview and actual project charge include site preparation exactly once")
	check(not sim.preview_build("home",cell).ok,"ordinary construction cannot occupy a reserved future footprint")
	var line_preview: Dictionary=sim.preview_connection(1,6)
	var line_count: int=sim.lines.size()
	before=float(sim.cash)
	var corridor: Dictionary=sim.connect_buildings(1,6)
	check(corridor.ok and int(corridor.id)==-1 and sim.lines.size()==line_count,"ordinary long-distance connect routes into a construction project")
	check(absf(before-float(sim.cash)-float(line_preview.cost))<0.00001,"long-corridor quote and payment agree without duplicated preparation fees")
	sim.step(1.5)
	check(not sim.building_at(cell).is_empty() and sim.lines.size()==line_count+1,"both construction entrypoints produce actual commissioned equipment after their lead times")
	check(cash_balances(sim) and nodal_balances(sim),"normal construction flow remains financially and electrically reconciled")

func _test_atomic_cross_references() -> void:
	var sim=modern()
	sim.customers.configure(sim,3,{"metered":true,"consent":true})
	sim.engineering.configure_line(sim,1,"transmission")
	sim.customers.define_microgrid(sim,"核对分区",[1,2,5,9],[5])
	sim.lifecycle.maintenance(sim,"facility",7,"inspect")
	var original: Dictionary=sim.snapshot()
	var malformed: Array=[]
	var data: Dictionary=original.duplicate(true)
	data.customers.devices["99999"]=data.customers.devices["3"].duplicate(true)
	malformed.append(data)
	data=original.duplicate(true)
	data.engineering.lines["99999"]={"tier":"distribution","delay":1.0}
	malformed.append(data)
	data=original.duplicate(true)
	data.lifecycle.jobs[0].target_id=99999
	malformed.append(data)
	data=original.duplicate(true)
	data.customers.microgrids[0].members.append(99999)
	malformed.append(data)
	data=original.duplicate(true)
	data.customers.microgrids[0].pending={"island":true,"method":"field","lines":[99999],"remaining":0.2}
	malformed.append(data)
	var atomic:=true
	for bad in malformed:
		atomic=atomic and not sim.restore_snapshot(bad).ok and equivalent(sim.snapshot(),original)
	check(atomic,"bad customer, engineering, inspection and microgrid references reject the whole snapshot atomically")

func _test_forecast_information_boundary() -> void:
	var sim=modern()
	sim.time_hours=20.0
	sim.customers.configure(sim,3,{"metered":true,"consent":true,"battery_mwh":20.0,"battery_mw":5.0})
	sim.customers.devices["3"].energy_mwh=1.0
	sim._refresh()
	sim.digital.sample_verified(sim)
	sim.digital.isolate(sim,3,true)
	var other=copy_world(sim)
	other.customers.devices["3"].energy_mwh=18.0
	other._refresh()
	var before: Dictionary=sim.snapshot()
	var a: Dictionary=sim.planning.forecast(sim,{},1)
	var b: Dictionary=other.planning.forecast(other,{},1)
	check(a.ok and b.ok,"unknown customer storage has an explicit forecast assumption")
	check(equivalent(a.rows,b.rows) and absf(float(a.net_cash)-float(b.net_cash))<0.00001,"forecast cannot reveal hidden behind-meter energy through future imports or bills")
	check(equivalent(sim.snapshot(),before),"information-boundary forecast remains read only")
	# Fresh telemetry is evidence of the sampled instant, not omniscience about
	# physical changes that have happened since the last sample.
	var known=modern()
	known.time_hours=20
	known._refresh()
	known.digital.sample_verified(known)
	var latent=copy_world(known)
	latent.get_line(1).fault=true
	latent.get_line(1).closed=false
	var first: Dictionary=known.planning.forecast(known,{},1)
	var second: Dictionary=latent.planning.forecast(latent,{},1)
	check(equivalent(first.rows,second.rows),"forecast uses cached trusted evidence instead of a newly hidden unsampled fault")
	var servicing=modern()
	servicing.time_hours=20
	servicing.digital.isolate(servicing,10,true)
	check(servicing.lifecycle.maintenance(servicing,"line",1,"service").ok,"unobserved line can receive a planned field maintenance task")
	var historical=copy_world(servicing)
	historical.lifecycle.jobs[0].original_closed=false
	var service_a: Dictionary=servicing.planning.forecast(servicing,{},2)
	var service_b: Dictionary=historical.planning.forecast(historical,{},2)
	check(equivalent(service_a.rows,service_b.rows),"maintenance completion cannot reintroduce an unobserved historical switch state into a forecast")

func _test_local_protection_and_demolition() -> void:
	var sim=modern()
	sim.digital.isolate(sim,10,true)
	sim.get_line(3).fault=true
	sim.get_line(3).closed=true
	sim.step(0.05)
	check(not sim.get_line(3).closed,"local feeder protection isolates an energized fault without central communications")
	check(sim.get_line(4).closed and sim.get_building(5).served>0,"selective local action keeps healthy critical branch energized")
	check(sim.customers.configure(sim,3,{"metered":true,"consent":true,"pv_mw":1.0}).ok,"demolition fixture includes a registered prosumer")
	sim.engineering.configure_line(sim,2,"distribution")
	check(sim.demolish(3).ok,"configured prosumer can be removed by ordinary demolition")
	check(not sim.customers.devices.has("3") and not sim.engineering.line_settings.has("2"),"demolition prunes customer and attached engineering references")
	var clone=copy_world(sim)
	check(nodal_balances(clone) and cash_balances(clone),"post-demolition world remains saveable and reconciled")

func _test_transformer_selectivity() -> void:
	var sim=Sim.new()
	sim.buildings.clear()
	sim.lines.clear()
	sim.objectives.clear()
	sim.next_building_id=1
	sim.next_line_id=1
	sim.next_storm_at=10000
	sim.digital.reset(sim)
	sim.digital.next_attack_at=10000
	sim._add_building("gas",Vector2i(3,6))
	sim._add_building("substation",Vector2i(5,6))
	sim._add_building("home",Vector2i(7,5),{"base_demand":10.0})
	sim._add_building("home",Vector2i(7,7),{"base_demand":10.0})
	sim._add_line(1,2)
	sim._add_line(2,3)
	sim._add_line(2,4)
	sim.engineering.enable(sim)
	sim.engineering.configure_substation(sim,2,10.0,"下级选择性")
	sim._refresh()
	sim.step(3.0)
	check(float(sim.get_building(3).served)+float(sim.get_building(4).served)<=10.0001,"sustained transformer capacity limiting constrains delivery before thermal protection is needed")
	check(sim.get_line(2).closed and sim.get_line(3).closed and float(sim.get_building(2).transformer_heat)<1,"requested demand alone does not heat equipment beyond actual delivered power")
	# Replay an abnormal measured-current transient immediately before the local
	# protection pass; the capacity limiter normally prevents this steady state.
	sim.get_line(1).flow=24.0
	sim.get_line(2).flow=12.0
	sim.get_line(3).flow=12.0
	sim.engineering.advance(sim,0.3)
	check(sim.get_line(1).closed,"transformer overload isolates downstream feeder before sacrificing upstream supply")
	check(sim.get_line(2).closed!=sim.get_line(3).closed,"selective transformer action removes one overloaded feeder and retains the other")
	sim._refresh()
	check(float(sim.get_building(3).served)+float(sim.get_building(4).served)>1,"healthy downstream service survives transformer overload protection")
