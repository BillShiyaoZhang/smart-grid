extends SceneTree
## Read-only previews, observed operator views and real asynchronous receipts.
const Sim = preload("res://scripts/sim/grid_sim.gd")
const Presenter = preload("res://scripts/ui/grid_presenter.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_test_previews()
	_test_observation_boundary()
	_test_receipts()
	print("OPERATOR MODEL: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+message)

func _canonical(sim: RefCounted) -> String:
	return JSON.stringify(sim.snapshot(),"",true,true)+JSON.stringify(sim.operation_receipts(),"",true,true)

func _test_previews() -> void:
	var sim: RefCounted = Sim.new()
	var before: String = _canonical(sim)
	for index in range(4):
		check(sim.preview_build("solar",Vector2i(1,1)).ok,"valid build preview")
		check(not sim.preview_build("solar",Vector2i(3,7)).ok,"occupied build preview")
		check(not sim.preview_build("solar",Vector2i(0,0)).ok,"out of bounds build preview")
		check(not sim.preview_build("missing",Vector2i(1,1)).ok,"unknown facility preview")
		check(not sim.preview_build("nuclear",Vector2i(1,1)).ok,"locked technology preview")
		check(sim.preview_connection(2,6).ok,"valid power preview")
		check(not sim.preview_connection(1,2).ok,"duplicate power preview")
		check(not sim.preview_connection(1,1).ok,"self-loop preview")
		check(not sim.preview_connection(1,999).ok,"missing endpoint preview")
		check(not sim.preview_connection(1,6,"wireless").ok,"wireless range preview")
		check(sim.preview_connection(2,6,"fiber").ok,"independent fiber preview")
		check(sim.preview_demolition(2).line_ids.size()>0,"demolition lists connected power lines")
	check(_canonical(sim)==before,"all preview queries preserve snapshot, clock, money, RNG and receipts")
	# Objective grants are separate from quoted construction and connection charges.
	for objective in sim.objectives: objective.done=true
	var planned: Dictionary = sim.preview_build("solar",Vector2i(1,1))
	var cash: float = float(sim.cash)
	var built: Dictionary = sim.build("solar",Vector2i(1,1))
	check(built.ok and is_equal_approx(float(sim.cash),cash-float(planned.cost)),"build commits the exact preview price")
	var occupied: Dictionary = sim.preview_build("solar",Vector2i(1,1))
	check(not occupied.ok and sim.build("solar",Vector2i(1,1)).message==occupied.message,"submission revalidates changed occupancy with same reason")
	var connection: Dictionary = sim.preview_connection(2,6)
	cash=float(sim.cash)
	var connected: Dictionary = sim.connect_buildings(2,6)
	check(connected.ok and is_equal_approx(float(sim.cash),cash-float(connection.cost)),"power connection shares preview price")
	check(sim.get_line(int(connected.id)).capacity==connection.capacity,"preview capacity matches new power line")
	var fiber: Dictionary = sim.preview_connection(2,6,"fiber")
	cash=float(sim.cash)
	check(sim.connect_communication(2,6,"fiber").ok and is_equal_approx(float(sim.cash),cash-float(fiber.cost)),"communication commit shares preview price")
	check(not sim.preview_connection(2,6,"wireless").ok,"duplicate communication checked independent of medium")
	sim.cash=0.0
	var poor: Dictionary = sim.preview_build("solar",Vector2i(1,2))
	check(not poor.ok and sim.build("solar",Vector2i(1,2)).message==poor.message,"budget checks agree at commit")
	sim.cash=100000.0
	var demolition: Dictionary = sim.preview_demolition(int(built.id))
	cash=float(sim.cash)
	check(sim.demolish(int(built.id)).ok and is_equal_approx(float(sim.cash),cash+float(demolition.refund)),"demolition refunds exact preview amount")
	var history: RefCounted = Sim.new()
	history.start_campaign(1)
	before=_canonical(history)
	var required_id: int = int(history.campaign.required_customers[0])
	var required: Dictionary = history.preview_demolition(required_id)
	check(not required.ok and history.demolish(required_id).message==required.message,"campaign required customer remains protected")
	check(not history.preview_connection(1,2,"fiber").ok,"historical communication capability stays closed")
	check(_canonical(history)==before,"historical rejection and preview are side-effect free")
	var terrain: RefCounted = Sim.new()
	terrain.region.active=true
	for tech in terrain.evolution.TECHNOLOGIES:
		if tech not in terrain.evolution.unlocked: terrain.evolution.unlocked.append(tech)
	check(not terrain.preview_build("hydro",Vector2i(20,20)).ok,"hydro terrain restriction is previewed")
	check(terrain.preview_build("hydro",Vector2i(20,4)).ok,"valid hydro terrain is previewed")

func _has_target(rows: Array, target_type: String, target_id: int) -> bool:
	for row in rows:
		if row.target_type==target_type and int(row.target_id)==target_id: return true
	return false

func _test_observation_boundary() -> void:
	var sim: RefCounted = Sim.new()
	sim.digital.links.clear()
	sim.digital.observations.clear()
	sim.digital.facility_observations.clear()
	sim.get_line(1).fault=true
	sim.get_line(1).health=0.0
	sim.get_building(1).health=0.0
	var before: String = _canonical(sim)
	var rows: Array[Dictionary] = Presenter.alerts(sim)
	check(not _has_target(rows,"line",1),"hidden line fault never becomes an exact alert")
	check(not _has_target(rows,"facility",1),"hidden facility fault never becomes an exact alert")
	var devices: Array[Dictionary] = Presenter.facilities(sim,"1")
	check(not devices.is_empty() and devices[0].health==null and devices[0].output==null,"directory hides unobserved live readings")
	check(Presenter.facility_marker(sim,1).text=="?","map marker does not disclose hidden fault")
	var diagnostic: Dictionary = Presenter.diagnosis(sim)
	check(diagnostic.has("deficit") and diagnostic.has("causes"),"diagnosis offers public deficit and evidence")
	check(_canonical(sim)==before,"presenter queries do not sample, advance, charge or change saved state")
	sim.digital.observations[1]={"line_id":1,"fault":true,"closed":false,"flow":0.0,"health":0.0,"heat":0.0,"sampled_at":float(sim.elapsed_hours),"source":"patrol"}
	rows=Presenter.alerts(sim)
	check(_has_target(rows,"line",1),"fresh field evidence enables exact fault alert")
	sim.digital.observations[1].sampled_at=float(sim.elapsed_hours)-2.0
	check(not _has_target(Presenter.alerts(sim),"line",1),"expired field record no longer asserts current fault")
	check(Presenter.facilities(sim,"工业园").size()==1,"directory searches localized facility names")
	check(Presenter.facilities(sim,"","storage").size()==1,"directory filters facility categories")
	check(Presenter.facilities(sim,"","trusted").is_empty(),"trusted directory excludes unknown facilities")
	check(not Presenter.facilities(sim,"","issues").is_empty(),"issues directory retains publicly unconnected facilities")
	sim.digital.observations[1].sampled_at=float(sim.elapsed_hours)
	sim.digital.observations[1].fault=false
	sim.digital.observations[1].closed=false
	var open_line: bool = false
	for cause in Presenter.diagnosis(sim).causes:
		if cause.id=="open_1": open_line=true
	check(open_line,"diagnosis distinguishes a known open switch from hidden faults")
	for building in sim.buildings:
		sim.digital.facility_observations[int(building.id)]={"building_id":int(building.id),"source":"field","sampled_at":float(sim.elapsed_hours),
			"available":0.0,"output":0.0,"served":0.0,"demand":10.0 if building.kind=="factory" else 0.0,"energy":0.0,"health":100.0,"fuel_cost":0.0,"status":"现场核实"}
	var known_shortage: bool = false
	for cause in Presenter.diagnosis(sim).causes:
		if cause.id=="available_supply": known_shortage=true
	check(known_shortage,"complete observations support a specific available supply diagnosis")

func _test_receipts() -> void:
	var sim: RefCounted = Sim.new()
	sim.next_storm_at=10000.0
	sim.digital.next_attack_at=10000.0
	check(sim.configure_facility(1,{"dispatch":.5},"field").ok,"field settings enter real queue")
	check(Presenter.jobs(sim)[0].phase=="pending" and sim.get_building(1).dispatch==1.0,"pending view does not claim settings already applied")
	sim.step(.4)
	var receipts: Array[Dictionary] = sim.operation_receipts()
	check(receipts[-1].phase=="executed" and sim.get_building(1).dispatch==.5,"completed field execution produces persistent session acknowledgement")
	receipts[-1].phase="tampered"
	check(sim.operation_receipts()[-1].phase=="executed","receipt reader gets a deep copy")
	sim.research()
	sim.research()
	sim.step(.05)
	check(sim.configure_facility(1,{"dispatch":.75},"remote").ok,"remote command accepted under fresh trusted telemetry")
	sim.isolate_device(1,true)
	sim.step(.2)
	check(sim.operation_receipts()[-1].phase=="rejected" and sim.get_building(1).dispatch==.5,"lost path produces actual rejection acknowledgement")
	check(Presenter.jobs(sim)[0].phase=="rejected","operation view retains failure after queue drains")
	var built: Dictionary = sim.build("gas",Vector2i(1,1))
	check(built.ok and sim.configure_facility(int(built.id),{"dispatch":0.0},"field").ok,"new target can queue field setting")
	sim.demolish(int(built.id))
	check(sim.operation_receipts()[-1].phase=="rejected" and sim.digital.field_jobs.is_empty(),"demolition terminates queued work with a cancellation receipt")
	var persist: RefCounted = Sim.new()
	persist.next_storm_at=10000.0
	persist.digital.next_attack_at=10000.0
	persist.configure_facility(1,{"dispatch":.5},"field")
	var path: String = "user://test_operator_model_save.json"
	check(persist.save_game(path).ok,"pending work saves through production schema")
	persist.step(.4)
	check(persist.load_game(path).ok and persist.operation_receipts().is_empty(),"load clears session history without changing save compatibility")
	check(Presenter.jobs(persist)[0].phase=="pending","saved pending work remains visible after load")
	persist.step(.4)
	check(persist.operation_receipts()[-1].phase=="executed","restored pending work produces a fresh real execution receipt")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	sim.reset()
	check(sim.operation_receipts().is_empty(),"reset clears session receipts")
