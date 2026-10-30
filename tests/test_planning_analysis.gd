extends SceneTree
const Sim=preload("res://scripts/sim/grid_sim.gd")
var checks:=0
var failures:=0
func check(value: bool, text: String) -> void:
	checks+=1
	if not value: failures+=1; push_error("FAIL: "+text)
func _initialize() -> void:
	var sim:=Sim.new()
	sim.buildings.clear(); sim.lines.clear(); sim.objectives.clear()
	sim.next_building_id=1; sim.next_line_id=1
	sim.digital.reset(sim)
	sim.digital.next_attack_at=10000
	sim.next_storm_at=10000
	sim.cash=1000000
	sim.planning.reset(sim.cash)
	var gas: Dictionary=sim._add_building("gas",Vector2i(2,2))
	var load: Dictionary=sim._add_building("factory",Vector2i(4,2))
	var hospital: Dictionary=sim._add_building("hospital",Vector2i(4,4))
	var a: Dictionary=sim._add_line(int(gas.id),int(load.id))
	sim._add_line(int(gas.id),int(hospital.id))
	sim._solve(0)
	for b in sim.buildings: sim.digital._sample_facility(sim,b,"field")
	for l in sim.lines: sim.digital._sample(sim,l,"patrol")
	var before:=JSON.stringify(sim.snapshot())
	var forecast: Dictionary=sim.planning_forecast({},24)
	check(forecast.ok and forecast.rows.size()==24,"24 hourly supply-demand rows")
	check(JSON.stringify(sim.snapshot())==before,"forecast cannot mutate cash RNG energy queues or objectives")
	check(forecast.rows[0].has("demand_high") and forecast.rows[0].has("storage_mwh") and forecast.rows[0].has("reserve_mw"),"forecast carries uncertainty energy and reserve")
	var comparisons: Dictionary=sim.compare_operating_plans([{}, {"generator_id":int(gas.id),"dispatch":0.0,"imports":false},{"outage_line":int(a.id)}])
	check(comparisons.ok and comparisons.plans.size()==3,"three independent operating alternatives")
	check(float(comparisons.plans[1].unserved_mwh)>float(comparisons.plans[0].unserved_mwh),"turning off generation worsens evening coverage")
	check(float(comparisons.plans[2].unserved_mwh)>0,"selected single outage affects demand delivery")
	check(JSON.stringify(sim.snapshot())==before,"comparisons cannot affect real graph")
	check(not sim.planning_forecast({},25).ok,"forecast horizon bounded")
	check(not sim.planning_forecast({"outage_line":999}).ok,"invalid contingency rejected")
	sim.digital.facility_observations.clear(); sim.digital.observations.clear()
	var unknown: Dictionary=sim.planning_forecast({},2)
	gas.health=10; gas.online=false; a.closed=false; a.fault=true
	sim.rng.seed=909
	var concealed: Dictionary=sim.planning_forecast({},2)
	check(unknown.ok and concealed.ok and unknown.rows==concealed.rows,"unknown faults health and RNG cannot leak through forecast")
	gas.health=100; gas.online=true; a.fault=false; a.closed=false
	sim._solve(0)
	sim.step(.25)
	var report: Dictionary=sim.operating_report()
	check(report.active==1 and report.unserved_mwh>0,"actual interruptions record duration and missing energy")
	a.closed=true
	sim.step(.1)
	report=sim.operating_report()
	check(report.active==0 and report.events.size()==1 and float(report.events[0].end)>=0,"restoration closes event and retains recovery curve")
	var cash_before:=sim.cash
	sim.record_cash_change(-250,"inspection","测试巡检")
	sim.record_cash_change(1000,"loan","测试借款")
	report=sim.operating_report()
	var total: float=report.opening_cash
	for entry in report.cash_entries: total+=float(entry.amount)
	check(absf(total-sim.cash)<.00001 and absf(sim.cash-cash_before-750)<.00001,"all cash categories reconcile opening to closing balance")
	before=JSON.stringify(sim.snapshot())
	sim.operating_report(); sim.market_forecast()
	check(before==JSON.stringify(sim.snapshot()),"reports are read only")
	var saved: Dictionary=JSON.parse_string(JSON.stringify(sim.snapshot()))
	var restored:=Sim.new()
	check(restored.restore_snapshot(saved).ok,"JSON current-schema roundtrip valid")
	check(restored.planning.snapshot()==saved.planning,"outage and journal state persisted")
	before=JSON.stringify(restored.snapshot())
	var bad: Dictionary=saved.duplicate(true)
	bad.planning.cash_entries[0].amount="bad"
	check(not restored.restore_snapshot(bad).ok and JSON.stringify(restored.snapshot())==before,"malformed journal atomically rejected")
	bad=saved.duplicate(true); bad.customers.devices["99999"]={}
	check(not restored.restore_snapshot(bad).ok and JSON.stringify(restored.snapshot())==before,"malformed customer snapshot rejected without mutation")
	bad=saved.duplicate(true); bad.buildings[0].erase("id")
	check(not restored.restore_snapshot(bad).ok and JSON.stringify(restored.snapshot())==before,"missing base identity rejected before new reference validation")
	bad=saved.duplicate(true); bad.campaign="corrupt"
	check(not restored.restore_snapshot(bad).ok and JSON.stringify(restored.snapshot())==before,"malformed campaign rejected before expansion compatibility checks")
	var old: Dictionary=saved.duplicate(true)
	old.schema_version=7
	for key in ["planning","lifecycle","engineering","customers","strategy"]: old.erase(key)
	check(restored.restore_snapshot(old).ok,"schema7 migration remains supported")
	check(not restored.lifecycle.enabled and not restored.engineering.enabled and not restored.customers.enabled and not restored.strategy.enabled,"old saves retain original operational rules until commissioning")
	var smart:=Sim.new()
	smart.objectives.clear()
	smart.research_level=2
	smart.customers.enable(smart)
	var customer: Dictionary=smart.get_building(3)
	smart.digital._sample_facility(smart,customer,"field")
	check(smart.customers.configure(smart,3,{"metered":true,"consent":true,"participation":.5}).ok,"AMI enrollment for migrated global response control")
	var response_cash:=smart.cash
	check(smart.demand_response().ok and smart.demand_response_remaining==0 and smart.customers.devices["3"].response_kind=="shift","old response button uses enrolled shift contracts after commissioning")
	check(smart.cash==response_cash and not smart.demand_response().ok,"response compensation is actual-energy based and cannot duplicate running contracts")
	smart.strategy.enable(smart)
	smart.strategy.configure_policy(smart,{"tariff_cap":100.0})
	smart.strategy.configure_market(smart,"auction",1.0)
	var market_before:=JSON.stringify(smart.snapshot())
	var prices: Array=smart.market_forecast()
	check(prices.size()==24 and float(prices[0].retail)<=100.0,"forecast retail curve follows commissioned price cap")
	check(float(prices[0].spot)==float(smart.strategy.auction_at(float(prices[0].hour),maxf(0.0,sin((float(prices[0].hour)-6.0)*PI/12.0))).price),"reference curve uses configured regional clearing rule")
	check(JSON.stringify(smart.snapshot())==market_before,"market forecast cannot mutate bidding or policy state")
	print("PLANNING ANALYSIS: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)
