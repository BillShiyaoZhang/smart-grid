extends SceneTree
## Focused behavior tests independent from the scene and electrical solver.
const Evolution = preload("res://scripts/sim/grid_evolution.gd")
var checks := 0
var failures := 0

class DigitalStub extends RefCounted:
	var reachable := false
	func control_reachable(_sim: RefCounted, _id: int) -> bool:
		return reachable

class TestGrid extends RefCounted:
	var cash := 1000000.0
	var buildings: Array[Dictionary] = []
	var lines: Array[Dictionary] = []
	var day := 1
	var time_hours := 8.0
	var storm_active := false
	var research_level := 1
	var digital := DigitalStub.new()
	var messages: Array[String] = []
	func get_building(id: int) -> Dictionary:
		for b in buildings:
			if int(b.id) == id:
				return b
		return {}
	func _log(message: String, _severity: String = "info") -> void:
		messages.append(message)
	func add(kind: String, model: RefCounted, cell := Vector2i(2,2)) -> Dictionary:
		var item: Dictionary = Evolution.EXTRA_CATALOG[kind] if Evolution.EXTRA_CATALOG.has(kind) else {"capacity":24.0,"demand":0.0}
		var b := {"id":buildings.size()+1,"kind":kind,"cell":cell,"capacity":float(item.capacity),"base_demand":float(item.demand),"dispatch":1.0,"online":true,"health":100.0,"level":1,"available":0.0,"output":0.0}
		model.initialize_building(b)
		buildings.append(b)
		return b
	func connect_ids(a: int,b: int) -> void:
		lines.append({"id":lines.size()+1,"a":a,"b":b,"closed":true,"fault":false,"repair_remaining":0.0})

func _initialize() -> void:
	_test_technology()
	_test_thermal_constraints()
	_test_support_and_queries()
	_test_storage_controls()
	_test_hvdc_and_protection()
	_test_persistence()
	print("EVOLUTION TESTS: %d checks; %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: "+message)

func near(a: float,b: float) -> bool:
	return absf(a-b) < 0.00001

func _test_technology() -> void:
	var model := Evolution.new()
	var sim := TestGrid.new()
	check(Evolution.ERAS.size() == 6 and Evolution.TECHNOLOGIES.size() >= 24,"six generations cover twenty-four research choices")
	check(model.can_build("gas").ok and model.can_build("dc_dynamo").ok,"legacy starter and first-generation equipment remain playable")
	model.heritage = true
	check(not model.can_build("gas").ok and not model.can_build("solar").ok and model.can_build("home").ok,"heritage start gates modern equipment without blocking basic customers")
	model.heritage = false
	check(not model.can_build("nuclear").ok,"nuclear cannot bypass deep research")
	check(not model.research(sim,"reactor_engineering").ok,"research prerequisites are enforced")
	var original_cash := sim.cash
	check(model.research(sim,"ac_systems").ok,"available research starts")
	check(near(sim.cash,original_cash-8500.0),"research pays capital cost once")
	check(not model.can_build("steam").ok,"research does not instantly unlock equipment")
	check(not model.research(sim,"regional_planning").ok,"single team cannot duplicate research")
	model.advance(sim,0.5)
	check(not model.can_build("steam").ok,"half-finished research stays locked")
	model.advance(sim,0.5)
	check(model.can_build("steam").ok and model.project.is_empty(),"research completes only with elapsed simulation time")
	check(sim.messages.size() == 1,"completion produces a single event")
	check(not model.research(sim,"ac_systems").ok and near(sim.cash,original_cash-8500.0),"repeat research cannot spend or duplicate unlock")
	check(not model.can_place("hydro",Vector2i(10,10)).ok and model.can_place("hydro",Vector2i(20,3)).ok,"river hydropower respects regional water terrain")
	check(not model.can_place("pumped_storage",Vector2i(20,3)).ok and model.can_place("pumped_storage",Vector2i(28,27)).ok,"pumped storage needs the hill basin")

func _test_thermal_constraints() -> void:
	var model := Evolution.new()
	var sim := TestGrid.new()
	var coal := sim.add("coal",model)
	var ids: Array[int] = [int(coal.id)]
	check(near(model.generator_available(sim,coal,ids),0.0),"new thermal unit starts cold")
	model.advance(sim,2.0)
	check(near(float(coal.startup_remaining),1.0) and near(model.generator_available(sim,coal,ids),0.0),"coal must finish its three-hour preparation")
	model.advance(sim,2.0)
	check(near(float(coal.ramp_mw),5.0),"startup boundary only ramps during remaining interval")
	coal.available = model.generator_available(sim,coal,ids)
	check(model.generator_minimum(coal) > 0.0,"hot thermal power has a minimum commitment")
	coal.output = 0.0
	check(model.fuel_cost(coal) > 0.0 and model.carbon_rate(coal) > 0.0,"curtailing hot plant does not erase fuel or emissions")
	check(model.configure(sim,int(coal.id),{"enabled":false}).ok,"player can request shutdown")
	check(float(coal.ramp_mw) > 0.0,"shutdown request does not instantly remove thermal state")
	model.advance(sim,0.25)
	check(near(float(coal.ramp_mw),3.75),"thermal shutdown respects down-ramp")
	var before: Dictionary = coal.duplicate(true)
	check(not model.configure(sim,int(coal.id),{"enabled":true,"dispatch":2.0}).ok and coal == before,"a rejected draft applies no partial controls")
	model.unlocked.append("flexible_thermal")
	check(model.configure(sim,int(coal.id),{"flexible_mode":true}).ok,"flexible operation is an explicit researched choice")
	var fixed_upkeep := model.operating_cost(sim)
	coal.flexible_mode = false
	check(fixed_upkeep > model.operating_cost(sim),"flexible thermal mode has a real upkeep penalty")
	coal.dispatch = 0.0
	model.advance(sim,2.0)
	check(near(float(coal.ramp_mw),0.0) and near(float(coal.startup_remaining),3.0),"zero setpoint fully stops the plant and restores cold-start requirement")

func _test_support_and_queries() -> void:
	var model := Evolution.new()
	var sim := TestGrid.new()
	var reactor := sim.add("nuclear",model)
	var ids: Array[int] = [int(reactor.id)]
	model.advance(sim,10.0)
	check(near(float(reactor.ramp_mw),0.0) and "冷却" in model.facility_status(sim,reactor),"nuclear cannot start without supporting cooling")
	var cooling := sim.add("cooling",model)
	var academy := sim.add("academy",model)
	sim.connect_ids(int(reactor.id),int(cooling.id))
	sim.connect_ids(int(reactor.id),int(academy.id))
	ids.assign([1,2,3])
	model.advance(sim,9.0)
	check(near(float(reactor.startup_remaining),8.0),"dark auxiliary island cannot black start nuclear")
	cooling.powered = true
	academy.powered = true
	model.advance(sim,9.0)
	check(near(float(reactor.ramp_mw),5.0),"supporting infrastructure allows slow nuclear startup")
	var before: Dictionary = reactor.duplicate(true)
	var state_before: Dictionary = model.snapshot()
	for i in 10:
		model.generator_available(sim,reactor,ids)
		model.facility_status(sim,reactor)
		model.fuel_cost(reactor)
	check(reactor == before and model.snapshot() == state_before,"repeated UI queries never advance ramp, startup or research")
	var second := sim.add("nuclear",model)
	sim.connect_ids(int(second.id),int(reactor.id))
	check("冷却" in model.facility_status(sim,second),"cooling is finite and cannot support two reactors for free")
	var second_cooling := sim.add("cooling",model)
	sim.connect_ids(int(second_cooling.id),int(reactor.id))
	check("岗位" in model.facility_status(sim,second),"specialist posts are shared finite island resources")
	model.unlocked.append("dry_cooling")
	check(model.configure(sim,int(cooling.id),{"cooling_mode":"dry"}).ok,"researched dry cooling can be selected")
	check(model.demand_for(sim,cooling) > float(cooling.base_demand),"dry cooling has higher auxiliary load")
	var dry_output := model.generator_available(sim,reactor,[1,2,3,4,5])
	cooling.cooling_mode = "wet"
	check(dry_output < model.generator_available(sim,reactor,[1,2,3,4,5]),"dry cooling also lowers net usable nuclear capacity")
	cooling.enabled = false
	check(near(model.generator_available(sim,reactor,[1,2,3]),0.0),"disabled support cannot satisfy a reactor requirement")
	var customer := sim.add("home",model)
	check(not model.configure(sim,int(customer.id),{"enabled":false}).ok,"customer demand cannot be erased through an operating switch")

func _test_storage_controls() -> void:
	var model := Evolution.new()
	var sim := TestGrid.new()
	var battery := sim.add("community_battery",model)
	check(not model.configure(sim,1,{"storage_mode":"peak"}).ok,"advanced storage strategies need software research")
	check(model.configure(sim,1,{"enabled":true,"storage_mode":"auto","reserve_soc":0.0,"peak_hour":17.0}).ok,"unchanged defaults can be applied without advanced research")
	model.unlocked.append_array(["regional_planning","smart_storage"])
	check(model.configure(sim,1,{"storage_mode":"peak","reserve_soc":0.4,"peak_hour":18.0}).ok,"player configures local reserve and peak window")
	sim.time_hours = 10.0
	sim.digital.reachable = true
	check(not model.storage_can_discharge(sim,battery) and model.storage_can_charge(sim,battery),"trusted coordinated storage saves energy outside the peak")
	sim.research_level = 0
	check(model.storage_can_discharge(sim,battery) and "退回本地" in model.facility_status(sim,battery),"software and reachable network still require telemetry research")
	sim.research_level = 1
	sim.time_hours = 19.0
	check(model.storage_can_discharge(sim,battery) and not model.storage_can_charge(sim,battery),"trusted peak dispatch permits discharge without charging in same window")
	sim.digital.reachable = false
	sim.time_hours = 10.0
	check(model.storage_can_discharge(sim,battery),"loss of communication falls back to local supply rather than magical coordination")
	battery.storage_mode = "hold"
	check(not model.storage_can_discharge(sim,battery) and not model.storage_can_charge(sim,battery),"hold mode makes both directions idle")
	var hydrogen := sim.add("hydrogen",model)
	check(model.storage_efficiency(hydrogen) < model.storage_efficiency(battery),"long-duration hydrogen makes a real efficiency tradeoff")

func _test_hvdc_and_protection() -> void:
	var model := Evolution.new()
	var sim := TestGrid.new()
	var converter := sim.add("hvdc",model)
	var condenser := sim.add("condenser",model)
	var unsupported := model.terminal_capacity(sim,converter)
	check(near(unsupported,52.0),"HVDC starts at its unsupported hosting limit")
	sim.connect_ids(int(converter.id),int(condenser.id))
	check(near(model.terminal_capacity(sim,converter),52.0*1.15),"same-island condenser adds bounded converter stability hosting")
	condenser.enabled = false
	check(near(model.terminal_capacity(sim,converter),52.0),"disabled condenser provides no stability assistance")
	var station := sim.add("substation",model)
	sim.connect_ids(int(station.id),int(converter.id))
	model.unlocked.append("protection")
	check(model.configure(sim,int(station.id),{"protection_margin":0.8}).ok,"research permits protection coordination")
	check(near(model.line_trip_threshold(sim,sim.lines[1]),0.8),"conservative protection trips at lower heat without inventing thermal capacity")

func _test_persistence() -> void:
	var model := Evolution.new()
	var sim := TestGrid.new()
	model.research(sim,"ac_systems")
	model.advance(sim,0.4)
	var saved := model.snapshot()
	var restored := Evolution.new()
	check(restored.load_snapshot(saved) and restored.snapshot() == saved,"in-progress research round trips exactly")
	var malformed: Dictionary = saved.duplicate(true)
	malformed.unlocked = ["dc_basics","reactor_engineering"]
	check(not restored.load_snapshot(malformed) and restored.snapshot() == saved,"invalid prerequisite chains preserve live research")
	malformed = saved.duplicate(true)
	malformed.remaining_hours = NAN
	check(not Evolution.valid_snapshot(malformed),"nonfinite progress is rejected")
	var b := sim.add("coal",model)
	b.ramp_mw = 12.5
	b.enabled = false
	model.initialize_building(b)
	check(near(float(b.ramp_mw),12.5) and not bool(b.enabled),"save migration fills defaults without overwriting operating state")
	check(Evolution.validate_building(b),"valid facility controls can be persisted")
	b.reserve_soc = 1.5
	check(not Evolution.validate_building(b),"malformed facility state is rejected before grid replacement")
