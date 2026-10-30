extends SceneTree
const Lifecycle=preload("res://scripts/sim/asset_lifecycle.gd")
var checks:=0
var failures:=0

class CampaignStub extends RefCounted:
	var active:=false

class FieldStub extends RefCounted:
	var facilities: Dictionary={}
	var lines: Dictionary={}
	func _sample_facility(_sim: RefCounted,asset: Dictionary,_source: String) -> void: facilities[int(asset.id)]=float(asset.health)
	func _sample(_sim: RefCounted,asset: Dictionary,_source: String) -> void: lines[int(asset.id)]=float(asset.health)

class TestGrid extends RefCounted:
	var campaign:=CampaignStub.new()
	var digital:=FieldStub.new()
	var cash:=1000000.0
	var elapsed_hours:=0.0
	var storm_active:=false
	var rng:=RandomNumberGenerator.new()
	var buildings: Array[Dictionary]=[]
	var lines: Array[Dictionary]=[]
	var catalog: Dictionary={"battery":{"price":22000.0},"gas":{"price":38000.0},"substation":{"price":10000.0}}
	var life: RefCounted=Lifecycle.new()
	var other_crews:=0
	var cash_events: Array[Dictionary]=[]
	var messages: Array[String]=[]
	func _init() -> void: rng.seed=42
	func add(kind: String,health: float=100.0,cell: Vector2i=Vector2i(6,7)) -> Dictionary:
		var b: Dictionary={"id":buildings.size()+1,"name":kind,"kind":kind,"cell":cell,"health":health,"online":true,"repair_remaining":0.0,"capacity":10.0,"energy_capacity":30.0 if kind=="battery" else 0.0,"energy":15.0 if kind=="battery" else 0.0,"renewable_energy_mwh":7.5 if kind=="battery" else 0.0,"output":0.0,"charging":0.0}
		buildings.append(b)
		return b
	func get_building(id: int) -> Dictionary:
		for b in buildings:
			if int(b.id)==id: return b
		return {}
	func get_line(id: int) -> Dictionary:
		for line in lines:
			if int(line.id)==id: return line
		return {}
	func active_repairs() -> int: return other_crews+life.active_jobs()
	func record_cash_change(amount: float,category: String,description: String) -> void:
		cash+=amount
		cash_events.append({"amount":amount,"category":category,"description":description})
	func _log(message: String,_severity: String="info") -> void: messages.append(message)
	func facility_observation(id: int) -> Dictionary: return {"trusted":digital.facilities.has(id),"health":digital.facilities.get(id,null)}
	func line_observation(id: int) -> Dictionary: return {"fault_known":digital.lines.has(id),"health":digital.lines.get(id,null)}
	func advance(hours: float) -> void:
		for _i in ceili(hours/0.05):
			elapsed_hours+=0.05
			life.advance(self,0.05)
	func add_line(a: int,b: int) -> Dictionary:
		var line: Dictionary={"id":lines.size()+1,"a":a,"b":b,"health":100.0,"capacity":24.0,"flow":0.0,"closed":true,"fault":false,"heat":0.0,"repair_remaining":0.0,"trip_reason":""}
		lines.append(line)
		return line

func _initialize() -> void:
	_test_opt_in_and_risk()
	_test_maintenance_and_crews()
	_test_stock_priority_and_travel()
	_test_storage_and_queries()
	_test_failure_and_restore()
	_test_validation()
	print("ASSET LIFECYCLE: %d checks; %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+message)

func _test_opt_in_and_risk() -> void:
	var sim:=TestGrid.new()
	var b:=sim.add("gas")
	var original:=b.duplicate(true)
	var rng_state:=sim.rng.state
	sim.life.advance(sim,1.0)
	check(b==original and sim.rng.state==rng_state,"disabled migration default never changes assets or RNG")
	sim.campaign.active=true
	check(not sim.life.enable(sim).ok,"historical capability boundary rejects activation")
	sim.campaign.active=false
	check(sim.life.enable(sim).ok and not sim.life.enable(sim).ok,"activation is explicit and idempotent")
	check(float(b.age_hours)==0.0 and not b.lifecycle_busy,"activation initializes neutral defaults")
	var good: float=sim.life.risk_rate(b)
	b.health=30.0
	check(sim.life.risk_rate(b)>good*100.0,"deferred health maintenance increases failure hazard")
	var worn: float=sim.life.risk_rate(b)
	b.age_hours=1000.0
	check(sim.life.risk_rate(b)>worn,"age changes risk")
	check(sim.life.risk_rate(b,false,true)>sim.life.risk_rate(b),"severe weather changes risk")
	var line:=sim.add_line(1,1)
	sim.life.initialize_line(line)
	line.flow=48.0
	check(sim.life.risk_rate(line,true)>sim.life.risk_rate(line.duplicate().merged({"flow":0.0},true),true),"overload stress changes line risk")

func _test_maintenance_and_crews() -> void:
	var sim:=TestGrid.new()
	var b:=sim.add("gas",70.0)
	sim.life.enable(sim)
	check(sim.life.maintenance(sim,"facility",1,"inspect").ok,"inspection can be dispatched")
	check(b.online and sim.active_repairs()==1,"inspection travel occupies crew without taking power offline")
	sim.advance(0.15)
	check(b.online,"inspection work keeps asset online")
	sim.advance(0.2)
	check(sim.active_repairs()==0 and sim.digital.facilities.has(1),"inspection completes and publishes field evidence")
	check(is_equal_approx(float(b.health),70.0),"inspection reveals condition without repairing it")
	check(sim.life.maintenance(sim,"facility",1,"service").ok,"planned service starts")
	sim.advance(0.15)
	check(not b.online,"planned service has actual downtime after travel")
	sim.advance(0.6)
	check(b.online and is_equal_approx(float(b.health),85.0),"service restores limited condition rather than full health")
	b.lifecycle_failure=true
	b.online=false
	check(not sim.life.maintenance(sim,"facility",1,"service").ok,"routine service cannot clear permanent failure")
	check(sim.life.maintenance(sim,"facility",1,"overhaul").ok,"overhaul repairs failure")
	sim.advance(1.8)
	check(b.online and not b.lifecycle_failure and float(b.health)>=90.0,"overhaul restores availability and substantial condition")
	check(sim.cash_events.size()==3 and float(sim.cash)<1000000.0,"every maintenance dispatch uses cash journal")

func _test_stock_priority_and_travel() -> void:
	var sim:=TestGrid.new()
	sim.add("gas",80.0,Vector2i(7,7))
	sim.add("gas",80.0,Vector2i(40,40))
	sim.add("gas",80.0,Vector2i(8,7))
	sim.life.enable(sim)
	check(float(sim.life.quote(sim,"facility",2,"service").travel_hours)>float(sim.life.quote(sim,"facility",1,"service").travel_hours),"remote asset takes longer to reach")
	sim.other_crews=2
	var first: Dictionary=sim.life.maintenance(sim,"facility",1,"overhaul",0)
	var second: Dictionary=sim.life.maintenance(sim,"facility",2,"overhaul",0)
	var third: Dictionary=sim.life.maintenance(sim,"facility",3,"replace",2)
	check(first.ok and second.ok and third.ok and sim.life.active_jobs()==0,"existing electric/digital work occupies shared crews")
	check(sim.life.spares==0,"queued maintenance reserves inventory")
	check(not sim.life.maintenance(sim,"facility",1,"inspect").ok,"duplicate target task rejected")
	check(sim.life.set_priority(int(second.id),1).ok,"waiting job can be reprioritized")
	check(sim.life.cancel(sim,int(first.id)).ok and sim.life.spares==1,"cancelled queued job returns money and spare")
	sim.other_crews=1
	sim.life.advance(sim,0.01)
	check(sim.life.active_jobs()==1 and sim.life.jobs[0].target_id==3 and sim.life.jobs[0].status=="travel","highest priority waiting job gets freed shared crew")
	check(not sim.life.cancel(sim,int(third.id)).ok,"travelling job cannot be cancelled for a free refund")
	check(sim.life.restock(sim,2).ok and sim.life.spares==3,"inventory can be bought through cash journal")
	check(not sim.life.restock(sim,100).ok,"inventory bounded")
	var orphan:=TestGrid.new()
	orphan.add("gas")
	orphan.life.enable(orphan)
	orphan.other_crews=2
	var cash_before:=orphan.cash
	orphan.life.maintenance(orphan,"facility",1,"overhaul")
	orphan.buildings.clear()
	orphan.life.prune(orphan)
	check(orphan.life.jobs.is_empty() and orphan.life.spares==4 and is_equal_approx(orphan.cash,cash_before),"demolition immediately prunes queued work and refunds reserved resources")
	check(Lifecycle.valid_references(orphan.life.snapshot(),orphan.buildings,orphan.lines,orphan.elapsed_hours),"pruned work leaves a valid save with bounded historical receipt")

func _test_storage_and_queries() -> void:
	var sim:=TestGrid.new()
	var b:=sim.add("battery")
	sim.life.enable(sim)
	b.output=10.0
	var original:=b.duplicate(true)
	var snapshot: Dictionary=sim.life.snapshot()
	var rng_state:=sim.rng.state
	sim.life.report(sim)
	sim.life.quote(sim,"facility",1,"replace")
	sim.life.after_solve(sim,0.0)
	sim.life.advance(sim,0.0)
	check(b==original and snapshot==sim.life.snapshot() and sim.rng.state==rng_state,"reports quotes and zero-time solves have no state/RNG effects")
	var unknown: Dictionary=sim.life.report(sim).assets[0]
	check(unknown.health==null and unknown.soh==null and unknown.risk_per_hour==null,"unknown telemetry does not reveal true health or wear")
	sim.life.after_solve(sim,3.0)
	check(is_equal_approx(float(b.throughput_mwh),30.0) and float(b.soh)<100.0 and float(b.energy_capacity)<30.0,"actual delivered throughput changes SOH and usable capacity")
	var resting:=TestGrid.new()
	var rested:=resting.add("battery")
	resting.life.enable(resting)
	resting.life.after_solve(resting,3.0)
	check(float(b.soh)<float(rested.soh),"cycling ages storage more than calendar time alone")
	b.energy=float(b.energy_capacity)
	b.renewable_energy_mwh=float(b.energy)*0.5
	sim.life.after_solve(sim,30.0)
	check(float(b.energy)<=float(b.energy_capacity) and float(b.renewable_energy_mwh)<=float(b.energy),"capacity fade bounds energy and clean provenance")
	check(is_equal_approx(float(b.renewable_energy_mwh)/float(b.energy),0.5),"fade removes energy without changing its source ratio")
	var before:=float(b.nominal_energy_capacity)
	b.energy_capacity=float(b.energy_capacity)*1.5
	sim.life.after_solve(sim,0.05)
	check(is_equal_approx(float(b.nominal_energy_capacity),before*1.5),"paid capacity upgrade preserved as larger nominal asset")
	check(sim.life.maintenance(sim,"facility",1,"replace").ok,"storage replacement can be ordered")
	sim.advance(3.3)
	check(is_equal_approx(float(b.soh),100.0) and is_equal_approx(float(b.energy_capacity),float(b.nominal_energy_capacity)),"replacement renews storage capacity")
	check(float(b.energy)<float(b.energy_capacity),"replacement never creates free energy")

func _test_failure_and_restore() -> void:
	var a:=TestGrid.new()
	var b:=TestGrid.new()
	for sim in [a,b]:
		var asset: Dictionary=sim.add("gas",5.0)
		sim.life.enable(sim)
		asset.age_hours=8000.0
		sim.storm_active=true
		sim.advance(5.0)
	check(not a.buildings[0].online and a.life.failures==1,"neglected stressed asset can actually fail")
	check(a.life.snapshot()==b.life.snapshot() and a.rng.state==b.rng.state and a.buildings==b.buildings,"same seed and operations yield identical failures")
	check(a.messages[0].find("#")==-1,"unobserved failure announcement hides target identity")
	var c:=TestGrid.new()
	c.add("gas",65.0)
	c.life.enable(c)
	c.life.maintenance(c,"facility",1,"overhaul")
	c.advance(0.3)
	var d:=TestGrid.new()
	d.buildings.assign(c.buildings.duplicate(true))
	d.cash=c.cash
	d.elapsed_hours=c.elapsed_hours
	d.rng.state=c.rng.state
	d.life.restore(c.life.snapshot())
	c.advance(2.0)
	d.advance(2.0)
	check(c.life.snapshot()==d.life.snapshot() and c.buildings==d.buildings and c.rng.state==d.rng.state,"restore mid-maintenance preserves subsequent work and RNG")

func _test_validation() -> void:
	var sim:=TestGrid.new()
	sim.add("gas",65.0)
	sim.life.enable(sim)
	sim.life.maintenance(sim,"facility",1,"service")
	var state: Dictionary=sim.life.snapshot()
	check(Lifecycle.valid_snapshot(state),"valid in-flight snapshot accepted")
	var corrupt: Dictionary=state.duplicate(true)
	corrupt.jobs[0].travel_remaining=NAN
	check(not Lifecycle.valid_snapshot(corrupt),"nonfinite queued time rejected atomically")
	corrupt=state.duplicate(true)
	corrupt.jobs[0].priority=0.5
	check(not Lifecycle.valid_snapshot(corrupt),"fractional priority rejected")
	corrupt=state.duplicate(true)
	corrupt.jobs.append(corrupt.jobs[0].duplicate(true))
	check(not Lifecycle.valid_snapshot(corrupt),"duplicate job identity rejected")
	corrupt=state.duplicate(true)
	corrupt.spares=31
	check(not Lifecycle.valid_snapshot(corrupt),"inventory bounds checked")
	check(Lifecycle.validate_asset(sim.buildings[0]),"new asset fields validated")
	sim.buildings[0].soh=-1.0
	check(not Lifecycle.validate_asset(sim.buildings[0]),"invalid storage wear rejected")
