extends SceneTree

const Sim=preload("res://scripts/sim/grid_sim.gd")
const Engineering=preload("res://scripts/sim/grid_engineering.gd")
var checks:=0
var failures:=0

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition: failures+=1; push_error("FAIL: "+message)

func network(distance: int = 12) -> RefCounted:
	var sim=Sim.new()
	sim.buildings.clear(); sim.lines.clear(); sim.next_building_id=1; sim.next_line_id=1
	sim.cash=1000000.0
	sim._add_building("gas",Vector2i(0,0))
	sim._add_building("substation",Vector2i(distance/2,0))
	sim._add_building("factory",Vector2i(distance,0))
	sim._add_line(1,2); sim._add_line(2,3)
	sim.get_building(1).capacity=100.0
	sim.get_building(3).base_demand=2.0
	for line in sim.lines: line.capacity=200.0
	sim.digital.reset(sim)
	sim._refresh()
	return sim

func _initialize() -> void:
	var sim=network()
	check(not sim.engineering.enabled,"legacy/default simulation retains old electrical rules")
	var baseline: float=sim.totals.served
	check(sim.engineering.enable(sim).ok,"engineering can be commissioned")
	sim._refresh()
	check(float(sim.totals.network_loss_mw)>0.0,"resistive losses are actually source-funded")
	check(absf(float(sim.totals.energy_balance_error))<0.00001,"generation balances delivered load and explicit network losses")
	check(float(sim.get_building(3).voltage)<1.0,"downstream load sees voltage drop")
	check(float(sim.totals.served)<=baseline+0.00001,"engineering never creates free delivery")
	var before: String=JSON.stringify(sim.snapshot())
	for _i in 3: sim._refresh()
	check(JSON.stringify(sim.snapshot())==before,"query repeats neither consume energy nor advance economics")
	var long_network=network(30)
	long_network.engineering.enable(long_network); long_network._refresh()
	check(float(long_network.get_building(3).voltage)<float(sim.get_building(3).voltage),"long feeder has worse voltage")
	check(float(long_network.totals.network_loss_mw)>float(sim.totals.network_loss_mw),"long feeder incurs more losses")
	var original_loss: float=long_network.totals.network_loss_mw
	check(long_network.engineering.configure_line(long_network,1,"transmission").ok,"line level can be changed at transformer")
	check(long_network.engineering.configure_line(long_network,2,"transmission").ok,"feeder level upgrade available")
	long_network._refresh()
	check(float(long_network.totals.network_loss_mw)<original_loss,"higher voltage reduces actual energy loss")
	check(long_network.engineering.configure_substation(long_network,2,10.0,"医院馈线").ok,"transformer independent capacity configured")
	long_network.get_building(3).base_demand=50.0
	long_network._refresh()
	check(float(long_network.get_building(3).served)<=10.00001,"transformer rating limits physical delivered power")
	var weak=network(4)
	weak.engineering.enable(weak)
	weak.engineering.configure_substation(weak,2,10.0)
	weak.get_building(3).base_demand=20.0
	var weak_source: Dictionary=weak._add_building("gas",Vector2i(4,1))
	weak_source.capacity=1.0
	weak._add_line(int(weak_source.id),3)
	weak._refresh()
	check(absf(float(weak.get_line(1).flow))<=10.00001,"small local source cannot bypass upstream transformer bottleneck")
	var protected=network(4)
	protected.engineering.enable(protected)
	protected.engineering.configure_substation(protected,2,10.0)
	var healthy: Dictionary=protected._add_building("home",Vector2i(2,2))
	protected._add_line(2,int(healthy.id))
	protected.get_line(1).flow=20.0
	protected.get_line(2).flow=12.0
	protected.get_line(3).flow=8.0
	protected.get_building(2).transformer_heat=0.95
	protected.engineering.advance(protected,0.1)
	check(protected.get_line(1).closed and not protected.get_line(2).closed and protected.get_line(3).closed,"transformer protection sheds largest outward feeder instead of upstream main")
	var branch=long_network._add_building("home",Vector2i(14,3))
	long_network._add_line(2,int(branch.id))
	check(long_network.engineering.trip_fault(long_network,2).ok,"local protection isolates selected branch")
	check(not long_network.get_line(2).closed and long_network.get_line(3).closed,"healthy adjacent branch remains connected")
	var saved: Dictionary=long_network.engineering.snapshot()
	check(Engineering.valid(saved),"engineering snapshot validates")
	var restored=Engineering.new(); restored.restore(JSON.parse_string(JSON.stringify(saved,"",true,true)))
	check(restored.snapshot()==saved,"engineering persists configuration and causal records")
	var invalid: Dictionary=saved.duplicate(true); invalid.lines["1"].delay=-2
	check(not Engineering.valid(invalid),"malformed protection setting rejected")
	check(not long_network.engineering.configure_line(long_network,1,"invalid").ok,"invalid voltage class rejected without payment")
	print("test_grid_engineering: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
