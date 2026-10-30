extends SceneTree

const Sim=preload("res://scripts/sim/grid_sim.gd")
const Customers=preload("res://scripts/sim/customer_energy.gd")
var checks:=0
var failures:=0

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition: failures+=1; push_error("FAIL: "+message)

func equivalent(a: Variant,b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int): return absf(float(a)-float(b))<0.000000001
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for index in a.size():
			if not equivalent(a[index],b[index]): return false
		return true
	return a==b

func modern() -> RefCounted:
	var sim=Sim.new()
	sim.cash=1000000.0
	sim.research_level=2
	sim.next_storm_at=1000.0
	sim.time_hours=12.0
	sim._refresh()
	sim.digital.sample_verified(sim)
	sim.customers.enable(sim)
	return sim

func _initialize() -> void:
	var sim=modern()
	check(sim.customers.configure(sim,3,{"metered":true,"consent":true,"pv_mw":12.0,"battery_mwh":20.0,"battery_mw":5.0,"smart":true}).ok,"AMI and local generation/battery can be installed")
	sim._refresh()
	check(float(sim.get_building(3).customer_generation_mw)>0.0,"sunny rooftop surplus enters network dispatch")
	check(float(sim.get_building(3).demand)<0.0001,"behind-meter solar covers local demand before export")
	check(absf(float(sim.totals.energy_balance_error))<0.00001,"prosumers preserve network power balance")
	var before: String=JSON.stringify(sim.customers.snapshot())
	for _i in 4: sim._refresh()
	check(JSON.stringify(sim.customers.snapshot())==before,"opening views cannot charge customer battery")
	sim.step(0.2)
	check(float(sim.customers.devices["3"].energy_mwh)>0.0,"battery stores actual surplus during time advancement")
	var stored: float=sim.customers.devices["3"].energy_mwh
	sim.time_hours=20.0; sim._refresh(); sim.step(0.1)
	check(float(sim.customers.devices["3"].energy_mwh)<stored,"battery supplies local evening demand")
	check(sim.customers.configure(sim,4,{"metered":true,"consent":true,"participation":1.0}).ok,"second street signs flexibility agreement")
	sim.digital.sample_verified(sim)
	check(sim.customers.demand_response(sim,4,"shift",0.4,0.25).ok,"trusted authorized street accepts time-limited shift")
	sim.step(0.2)
	var debt: float=sim.customers.devices["4"].shift_debt_mwh
	check(debt>0.0,"shifted consumption becomes an energy obligation")
	check(float(sim.customers.devices["4"].compensation)>0.0,"actual flexible energy receives compensation")
	sim.step(1.0)
	check(float(sim.customers.devices["4"].shift_debt_mwh)<debt,"post-response rebound repays deferred energy")
	check(float(sim.customers.devices["4"].repaid_total_mwh)>0.0,"repaid energy tracked separately from curtailed energy")
	sim.digital.isolate(sim,4,true)
	check(not sim.customers.demand_response(sim,4,"curtail",0.2,1.0).ok,"communication isolation prevents fresh DR commands")
	check(not sim.customers.configure(sim,5,{"metered":false,"pv_mw":5.0}).ok,"unmetered generation cannot silently bypass enrollment")
	check(sim.customers.configure(sim,4,{"ev_mw":2.0,"ev_target_mwh":4.0,"deadline_hour":22.0,"smart":false}).ok,"EV aggregate has target and deadline")
	var ev_before: float=sim.customers.devices["4"].ev_remaining_mwh
	sim.step(0.2)
	check(float(sim.customers.devices["4"].ev_remaining_mwh)<ev_before,"actual charging reduces remaining energy")
	sim.customers.devices["4"].ev_deadline=sim.elapsed_hours+0.05
	sim.customers.devices["4"].ev_remaining_mwh=8.0
	sim.step(0.1)
	check(float(sim.customers.devices["4"].missed_ev_mwh)>0.0,"deadline shortfall produces explicit consequence")
	var micro: Dictionary=sim.customers.define_microgrid(sim,"医院自治区",[1,2,5,9],[5])
	check(micro.ok,"microgrid registers members and critical load")
	check(sim.customers.set_microgrid(sim,int(micro.id),true,"field").ok,"field island operation is scheduled")
	check(not bool(sim.customers.microgrids[0].islanded),"queue acceptance is not execution")
	sim.step(0.4)
	check(bool(sim.customers.microgrids[0].islanded),"boundary isolators operate after crew arrival")
	for line in sim.lines:
		if (int(line.a) in [1,2,5,9]) != (int(line.b) in [1,2,5,9]): check(not line.closed,"every boundary is physically isolated")
	sim.step(0.6)
	check(int(sim.customers.microgrids[0].stage)==2,"black-start capable local source restores critical then ordinary load")
	var saved: Dictionary=sim.customers.snapshot()
	check(Customers.valid(saved),"customer snapshot valid")
	var restored=Customers.new(); restored.restore(JSON.parse_string(JSON.stringify(saved,"",true,true)))
	check(equivalent(restored.snapshot(),saved),"customer obligations, batteries, microgrids survive JSON within numeric precision")
	var invalid: Dictionary=saved.duplicate(true); invalid.devices["3"].energy_mwh=-5
	check(not Customers.valid(invalid),"invalid battery state rejected")
	print("test_customer_energy: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
