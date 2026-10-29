extends SceneTree
## Cross-system operating boundaries: real dispatch, support allocation and asset upgrades.
const Sim = preload("res://scripts/sim/grid_sim.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_test_stable_minimum()
	_test_assigned_support()
	_test_useful_upgrades()
	_test_auxiliary_priority_and_recovery()
	_test_maintenance_topology()
	print("THERMAL INTEGRATION: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: "+message)

func near(a: float, b: float) -> bool:
	return absf(a-b)<0.00001

func blank() -> RefCounted:
	var sim = Sim.new()
	sim.buildings.clear()
	sim.lines.clear()
	sim.objectives.clear()
	sim.next_building_id = 1
	sim.next_line_id = 1
	sim.cash = 1000000.0
	sim.next_storm_at = 100000.0
	sim.digital.reset(sim)
	sim.digital.next_attack_at = 100000.0
	sim.evolution.unlocked.assign(sim.evolution.TECHNOLOGIES.keys())
	return sim

func balance(sim: RefCounted) -> void:
	check(absf(float(sim.totals.energy_balance_error))<0.000001,"auxiliary dispatch preserves total power")
	for b in sim.buildings:
		var outgoing := 0.0
		for line in sim.lines:
			outgoing += float(line.flow) if int(line.a)==int(b.id) else (-float(line.flow) if int(line.b)==int(b.id) else 0.0)
		check(absf(outgoing-float(b.output)+float(b.served)+float(b.charging))<0.0001,"auxiliary dispatch preserves node balance")

func _test_stable_minimum() -> void:
	var sim = blank()
	var coal: Dictionary = sim._add_building("coal",Vector2i(3,3))
	var customer: Dictionary = sim._add_building("hospital",Vector2i(4,3))
	customer.base_demand = 100.0
	coal.ramp_mw = 48.0
	coal.startup_remaining = 0.0
	sim._add_line(1,2).capacity = 200.0
	sim._refresh()
	var before: Dictionary = coal.duplicate(true)
	var rejected: Dictionary = sim.evolution.validate_configuration(sim,1,{"enabled":false,"dispatch":0.05})
	check(not rejected.ok and coal==before,"a complete low-dispatch draft is rejected atomically")
	check(near(sim.evolution.generator_minimum(coal),21.6),"coal stable minimum is 45 percent of nameplate")
	coal.dispatch = 0.05 # A legacy saved setpoint must not keep the old loophole alive.
	sim.step(12.0)
	check(float(coal.ramp_mw)>=21.6-0.00001 and float(coal.output)>21.4,"legacy low setpoint cannot settle below the true thermal minimum")
	check(sim.evolution.validate_configuration(sim,1,{"flexible_mode":true,"dispatch":0.35}).ok,"flexible mode and its lower researched minimum validate as one draft")
	check(not sim.evolution.validate_configuration(sim,1,{"dispatch":0.2}).ok,"ordinary coal cannot adopt a twenty-percent stable setpoint")
	check(sim.evolution.configure(sim,1,{"dispatch":0.0}).ok,"zero setpoint requests a real shutdown")
	sim.step(6.0)
	check(near(coal.ramp_mw,0.0) and near(coal.startup_remaining,3.0),"shutdown down-ramps to cold state instead of stabilizing below minimum")
	var reactor: Dictionary = sim._add_building("nuclear",Vector2i(5,3))
	check(not sim.evolution.validate_configuration(sim,int(reactor.id),{"dispatch":0.05}).ok,"nuclear cannot bypass its 55-percent stable minimum")
	var gas: Dictionary = sim._add_building("gas",Vector2i(6,3))
	check(sim.evolution.validate_configuration(sim,int(gas.id),{"dispatch":0.05}).ok,"fast gas retains a genuinely zero minimum")
	check(near(sim.evolution.marginal_cost(coal),43.0) and near(sim.evolution.marginal_cost(gas),68.0),"economic dispatch exposes each actual fuel cost")
	coal.flexible_mode = true
	check(near(sim.evolution.marginal_cost(coal),43.0*1.15),"flexible operation's incremental fuel penalty enters marginal cost")

func _test_assigned_support() -> void:
	var sim = blank()
	var first: Dictionary = sim._add_building("nuclear",Vector2i(3,3))
	var wet: Dictionary = sim._add_building("cooling",Vector2i(4,3))
	var academy: Dictionary = sim._add_building("academy",Vector2i(3,4))
	academy.level = 2
	var second: Dictionary = sim._add_building("nuclear",Vector2i(5,3))
	var dry: Dictionary = sim._add_building("cooling",Vector2i(5,4))
	dry.cooling_mode = "dry"
	for id in [2,3,4,5]: sim._add_line(1,id)
	var ids: Array[int] = [1,2,3,4,5]
	var a: Dictionary = sim.evolution.support_assignment(sim,first,ids)
	var b: Dictionary = sim.evolution.support_assignment(sim,second,ids)
	check(a.ok and b.ok and a.cooling_ids==[2] and b.cooling_ids==[5],"reactors receive explicit finite cooling assignments")
	check(near(a.cooling_factor,1.0) and near(b.cooling_factor,0.88),"dry cooling affects only its assigned reactor")
	check(int(a.staff_allocations[3])+int(b.staff_allocations[3])==12,"shared academy posts are allocated without duplication")
	academy.level = 1
	check(not sim.evolution.support_assignment(sim,second,ids).ok,"one eight-post academy cannot support two reactors")
	academy.level = 2
	wet.level = 2
	dry.enabled = false
	b = sim.evolution.support_assignment(sim,second,ids)
	check(b.ok and b.cooling_ids==[2] and near(b.cooling_factor,1.0),"upgraded cooling provides a second actual quota")
	first.ramp_mw = 90.0
	first.startup_remaining = 0.0
	sim._refresh()
	wet.served = 0.0
	academy.served = 0.0
	check(not sim.evolution.support_powered(sim,a),"structural support does not substitute for actual auxiliary power")
	sim.evolution.advance(sim,0.05)
	check(near(first.ramp_mw,0.0) and near(first.startup_remaining,8.0),"running reactor safely trips after actual auxiliary power loss")

func _test_useful_upgrades() -> void:
	var sim = blank()
	var cooling: Dictionary = sim._add_building("cooling",Vector2i(3,3))
	var before: float = sim.evolution.demand_for(sim,cooling)
	check(sim.upgrade(1).ok,"public cooling upgrade succeeds")
	check(near(sim.evolution.cooling_capacity(cooling),2.0) and near(sim.evolution.demand_for(sim,cooling),before),"cooling upgrade increases useful quota without increasing auxiliary draw")
	for kind in ["substation","sensor","control","relay","soc","condenser"]:
		var asset: Dictionary = sim._add_building(kind,Vector2i(4+sim.buildings.size(),3))
		var cash: float = sim.cash
		var snapshot: Dictionary = asset.duplicate(true)
		check(not sim.upgrade(int(asset.id)).ok and near(sim.cash,cash) and asset==snapshot,"unsupported upgrade is rejected without cash or state mutation: "+kind)
	var battery: Dictionary = sim._add_building("battery",Vector2i(11,4))
	check(sim.upgrade(int(battery.id)).ok and near(battery.capacity,15.0) and near(battery.energy_capacity,45.0),"storage upgrade still improves both power and duration")

func _test_auxiliary_priority_and_recovery() -> void:
	var sim = blank()
	var reactor: Dictionary = sim._add_building("nuclear",Vector2i(3,3))
	var cooling: Dictionary = sim._add_building("cooling",Vector2i(4,3))
	var academy: Dictionary = sim._add_building("academy",Vector2i(3,4))
	var hospital: Dictionary = sim._add_building("hospital",Vector2i(4,4))
	hospital.base_demand = 200.0
	reactor.ramp_mw = 90.0
	reactor.startup_remaining = 0.0
	for id in [2,3,4]: sim._add_line(1,id).capacity = 300.0
	sim._refresh()
	sim.step(0.1)
	check(float(cooling.served)>=float(cooling.demand)*0.98 and float(academy.served)>=float(academy.demand)*0.98,"running auxiliaries receive real priority even ahead of oversized hospital demand")
	check(float(reactor.output)>80.0 and float(hospital.served)>0.0,"a warm reactor supplies its auxiliaries and the remaining customers")
	balance(sim)
	var cooling_line: Dictionary = sim.get_line(1)
	cooling_line.fault = true
	cooling_line.closed = false
	sim._refresh()
	sim.step(0.1)
	check(near(reactor.output,0.0) and near(reactor.ramp_mw,0.0),"disconnecting assigned cooling stops running generation")
	balance(sim)
	cooling_line.fault = false
	cooling_line.closed = true
	sim._refresh()
	sim.step(0.5)
	check(near(reactor.ramp_mw,0.0) and near(reactor.startup_remaining,8.0),"restored cables alone cannot black-start a safety-tripped reactor")
	var gas: Dictionary = sim._add_building("gas",Vector2i(5,4))
	sim._add_line(int(gas.id),2).capacity = 300.0
	sim._refresh()
	sim.step(9.0)
	check(float(reactor.ramp_mw)>0.0,"external auxiliary supply enables a new timed startup after recovery")
	balance(sim)

func _test_maintenance_topology() -> void:
	var sim = blank()
	var gas: Dictionary = sim._add_building("gas",Vector2i(3,3))
	var station: Dictionary = sim._add_building("substation",Vector2i(4,3))
	var customer: Dictionary = sim._add_building("hospital",Vector2i(5,3))
	sim._add_line(1,2)
	sim._add_line(2,3)
	sim._refresh()
	check(customer.powered,"maintenance fixture starts with a genuinely powered feeder")
	station.health = 80.0
	check(sim.repair(2).ok and not station.online and near(customer.served,0.0),"substation maintenance actually isolates downstream demand")
	check(sim.evolution._component(sim,1)==[1],"support connectivity shares the same maintenance isolation rule")
	sim.step(0.7)
	check(station.online and customer.powered and float(gas.output)>0.0,"maintenance completion restores real feeder supply")
