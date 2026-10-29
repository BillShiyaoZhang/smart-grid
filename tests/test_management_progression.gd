extends SceneTree
## Meaningful model-level checks for operating intent, staged liability and safe persistence.
const Sim=preload("res://scripts/sim/grid_sim.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	_test_route_and_weather()
	_test_complete_management_route()
	_test_city_liability()
	_test_public_city_sources()
	_test_storage_intent_and_observations()
	_test_storage_observed_policy_status()
	_test_market_intent()
	_test_contract_with_operating_intent()
	_test_campaign_intent()
	_test_migration_and_validation()
	print("MANAGEMENT PROGRESSION: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check(value: bool, caption: String) -> void:
	checks+=1
	if not value: failures+=1; push_error("FAIL: "+caption)

func near(a: float,b: float,tolerance: float=0.00001) -> bool:
	return absf(a-b)<=tolerance

func blank() -> RefCounted:
	var sim:=Sim.new()
	sim.buildings.clear(); sim.lines.clear(); sim.objectives.clear()
	sim.next_building_id=1; sim.next_line_id=1; sim.cash=1e6
	sim.digital.reset(sim); sim.digital.next_attack_at=1e8; sim.next_storm_at=1e8
	return sim

func _test_route_and_weather() -> void:
	var legacy:=Sim.new()
	check(not legacy.management_status().active and near(legacy.next_storm_at,6),"legacy sandbox keeps its original schedule")
	var sim:=Sim.new()
	check(sim.start_management_game().ok and sim.objectives.size()==5,"new management route has all five outcome objectives")
	check(sim.management_status().stage==0 and not sim.feature_enabled("market") and not sim.feature_enabled("digital"),"opening stage exposes basic construction before advanced centers")
	check(not sim.prepare_first_storm().ok,"first storm cannot skip the basic management lessons")
	var before:=JSON.stringify(sim.snapshot(),"",true,true)
	for index in 4:
		sim.management_status(); sim.operating_snapshot(); sim.next_event_hours(); sim.storage_status(9)
	check(JSON.stringify(sim.snapshot(),"",true,true)==before,"management and operating queries do not sample history, advance time, spend money or RNG")
	sim.connect_buildings(2,6)
	sim.step(1.1)
	check(int(sim.management_status().stage)==1 and bool(sim.objectives[0].done),"reliable actual supply advances the first outcome")
	check(sim.feature_enabled("market") and not sim.feature_enabled("digital"),"market unlock follows actual reliable service")
	sim.step(12)
	check(sim.storm_count==0 and not sim.storm_active,"first storm stays deferred through the initial operating day")
	check(sim.management.state.night_seen,"night lesson tracks actual game clock")
	check(not sim.management.state.history.is_empty() and sim.management.state.history.size()<=300,"only elapsed simulation time creates bounded operating history")
	# A controlled operating fixture isolates continuous outcome behavior from weather variability.
	sim.management.state.stage=2; sim.management.state.hold_hours=0.0
	sim.totals.reliability=1.0; sim.totals.renewable_supply_share=0.5; sim.totals.income=1000; sim.totals.expenses=100
	sim.management.advance(sim,0.5)
	sim.totals.reliability=0.5
	sim.management.advance(sim,0.1)
	check(near(float(sim.management.state.hold_hours),0) and near(float(sim.management.state.best_hours),0.5) and "供电率" in sim.management.state.interruption,"failed continuous conditions retain best record and the reason for reset")
	sim.totals.reliability=1.0
	sim.management.advance(sim,2.0)
	check(sim.management_status().stage==3 and sim.management_status().first_storm_ready,"clean delivery and nonnegative operations unlock preparation")
	check(sim.prepare_first_storm().ok and near(sim.next_storm_at,sim.elapsed_hours+1),"preparation schedules one full hour of warning")
	sim.step(0.95)
	check(sim.storm_count==0,"warning does not trigger the storm early")
	sim.step(0.1)
	check(sim.storm_count==1 and sim.storm_active,"prepared first storm occurs after the real warning interval")
	check(sim.digital.incidents.is_empty(),"first basic storm does not also inject an overdue cyber incident")
	check(sim.next_storm_at>sim.elapsed_hours+20,"subsequent storms resume the natural cycle")

func _test_city_liability() -> void:
	var sim:=Sim.new()
	sim.next_storm_at=1e8; sim.digital.next_attack_at=1e8
	sim.connect_buildings(2,6)
	var demand:=float(sim.totals.demand)
	var expenses:=float(sim.totals.expenses)
	check(sim.explore_region().ok,"regional exploration creates a map of prospective markets")
	check(sim.region.cities.size()==8 and sim.region.summary().prospect_count==7,"all seven new cities begin as prospects")
	check(near(float(sim.totals.demand),demand) and near(float(sim.totals.expenses),expenses),"exploration creates neither new demand nor municipal upkeep liability")
	var city: Dictionary=sim.region.city_status(1)
	var population:=float(city.population)
	sim.step(10)
	check(near(float(sim.region.city_status(1).population),population) and near(float(sim.region.city_status(1).unserved_hours),0),"prospective cities do not decline from unserved hours")
	var first:=int(city.building_ids[0])
	check(not sim.customer_service_active(first),"prospective public buildings do not count as reported outages")
	check(not sim.start_city_service(1).ok,"service requires an explicit planning stage")
	check(sim.plan_city(1).ok and sim.region.city_status(1).service_phase=="planned","planning is explicit and does not activate liability")
	check(not sim.start_city_service(1).ok,"unconnected planned city cannot open service")
	check(sim.connect_buildings(2,first).ok,"regional customer can be connected with an actual paid feeder")
	check(sim.start_city_service(1).ok and sim.customer_service_active(first),"explicit service activation starts real customer responsibility")
	check(float(sim.totals.demand)>demand and sim.region.summary().serving_count==2,"active city joins actual demand and service denominators")
	check(not sim.start_city_service(1).ok,"repeated activation cannot duplicate a city or its demand")
	var saved:=sim.snapshot()
	check(sim._valid_save(saved),"staged city state is valid in schema seven")
	var later:=Sim.new()
	later.day=12
	later._refresh()
	var grown_demand:=float(later.totals.demand)
	later.explore_region()
	check(near(float(later.totals.demand),grown_demand),"later regional exploration preserves existing city's accumulated demand growth")

func _test_complete_management_route() -> void:
	var sim:=Sim.new()
	sim.start_management_game()
	check(sim.connect_buildings(2,6).ok,"route reference playthrough starts with paid industry connection")
	var solar: Dictionary=sim.build("solar",Vector2i(6,3))
	check(solar.ok and sim.connect_buildings(2,int(solar.id)).ok,"a chosen clean expansion is built and actually connected")
	for interval in 160:
		if int(sim.management_status().stage)>=3: break
		sim.step(0.25)
	check(int(sim.management_status().stage)==3,"actual day/night, delivered renewable supply and positive economics reach the resilience stage")
	check(sim.cash>0 and sim.storm_count==0,"route remains solvent and first storm waits for preparation")
	check(sim.prepare_first_storm().ok,"reference playthrough explicitly accepts the first forecast")
	sim.step(1.1)
	check(sim.storm_count==1,"actual first storm occurs in the reference playthrough")
	# Survey public feeders and use only each returned observation to decide repairs.
	for line in sim.lines:
		var id:=int(line.id)
		var patrol: Dictionary=sim.patrol_line(id)
		if patrol.ok: sim.step(0.55)
		var observation: Dictionary=sim.line_observation(id)
		if observation.get("fault_known",false) and observation.get("fault",false):
			check(sim.repair_line(id).ok,"confirmed storm damage can be repaired through the real command")
			sim.step(2.0)
	sim.step(3.0)
	check(int(sim.management_status().stage)==4 and not bool(sim.objectives[4].done),"storm recovery advances to expansion without prematurely completing all objectives")
	check(sim.explore_region().ok and sim.plan_city(1).ok,"reference playthrough discovers and plans its first market")
	var city: Dictionary=sim.region.city_status(1)
	check(sim.connect_buildings(2,int(city.building_ids[0])).ok and sim.start_city_service(1).ok,"new city uses actual constructed and paid access before responsibility begins")
	sim.step(16.0)
	check(int(sim.management_status().stage)==5 and bool(sim.objectives[4].done),"all five management outcomes can be completed with real simulation operations")
	check(sim._valid_save(sim.snapshot()),"completed management route with active city produces a valid save")

func _test_public_city_sources() -> void:
	for kind in ["gas","dc_dynamo","hydro"]:
		var sim:=blank()
		var source: Dictionary=sim._add_building(kind,Vector2i(3,3))
		sim._refresh()
		check(sim.explore_region().ok and sim.plan_city(1).ok,"%s-only network can explore and plan a city without wind or solar" % kind)
		var city: Dictionary=sim.region.city_status(1)
		var customer:=int(city.building_ids[0])
		check(sim.connect_buildings(int(source.id),customer).ok,"%s source has an actual paid feeder to the city" % kind)
		check(sim.start_city_service(1).ok,"public %s source identity is sufficient to commission the constructed access path" % kind)
		sim.step(0.1)
		check(float(sim.totals.demand)>0 and float(sim.totals.served)>0 and float(source.output)>0,"commissioned %s network has real demand and physically delivered output" % kind)
		if kind=="gas":
			check(float(sim.totals.fuel_cost)>0 and float(sim.totals.maintenance_cost)>9,"pure gas service adds actual fuel and network maintenance costs")
			var paid:=float(sim.cash)
			sim.step(0.1)
			check(float(sim.total_served_mwh)>0 and not near(sim.cash,paid),"pure gas service settles delivered energy and cash rather than just changing a city flag")
	var unknown:=blank()
	var source: Dictionary=unknown._add_building("gas",Vector2i(3,3))
	unknown.explore_region(); unknown.plan_city(1)
	var city: Dictionary=unknown.region.city_status(1)
	var connected: Dictionary=unknown.connect_buildings(int(source.id),int(city.building_ids[0]))
	var feeder: Dictionary=unknown.get_line(int(connected.id))
	feeder.fault=true; feeder.closed=false
	unknown._refresh()
	check(unknown.line_observation(int(feeder.id)).visibility=="unknown","constructed feeder's physical fault remains unobserved")
	check(unknown.start_city_service(1).ok,"service commissioning uses public topology instead of rejecting on a hidden fault")
	check(float(unknown.totals.demand)>0 and near(float(unknown.totals.served),0) and float(unknown.totals.outage_cost)>0,"explicit service responsibility includes real outage costs when the unknown path cannot deliver")
	check(not unknown.line_observation(int(feeder.id)).fault_known,"commissioning does not reveal the hidden fault")

func _test_storage_intent_and_observations() -> void:
	var sim:=blank()
	var gas: Dictionary=sim._add_building("gas",Vector2i(3,3))
	var battery: Dictionary=sim._add_building("battery",Vector2i(4,3))
	var home: Dictionary=sim._add_building("home",Vector2i(5,3),{"base_demand":20.0})
	sim._add_line(gas.id,battery.id); sim._add_line(battery.id,home.id)
	sim._refresh()
	battery.storage_mode="hold"; battery.reserve_soc=0.8
	check(sim.set_storage_intent("supply",0.1).ok,"global supply intent can be selected directly")
	check(sim.storage_status(battery.id).intent=="supply" and near(float(sim.storage_status(battery.id).reserve_soc),0.1),"new inherited intent has exactly one effective reserve")
	check(sim.evolution.storage_can_discharge(sim,battery),"new supply intent does not secretly inherit the old hold flag")
	check(sim.set_storage_intent("supply",0.3,battery.id,"field").ok,"per-device intent is a real accepted field command")
	check(near(float(sim.storage_status(battery.id).reserve_soc),0.1),"accepted command does not prematurely change effective strategy")
	var job: Dictionary=sim.digital.field_jobs[0]
	check(job.has("started_at") and near(float(job.duration),0.35),"new task records genuine start time and original duration")
	check(near(sim.next_event_hours(),0.35),"next known event includes field completion")
	sim.step(0.4)
	check(not sim.storage_status(battery.id).inherited and near(float(sim.storage_status(battery.id).reserve_soc),0.3),"field execution makes a single-device override effective")
	check(sim.set_storage_intent("supply",0.1).ok and near(float(sim.storage_status(battery.id).reserve_soc),0.3),"global default edits preserve a device's explicit override")
	var observed: Dictionary=sim.facility_observation(battery.id)
	check(observed.trusted and observed.charging!=null,"fresh field measurements include measured charging power")
	var sample: Dictionary=sim.digital.facility_observations[battery.id]
	sample.erase("charging")
	check(sim.facility_observation(battery.id).charging==null,"legacy samples without charging remain unknown rather than guessed zero")
	sim.digital._sample_facility(sim,battery,"field")
	check(sim.storage_status(battery.id).known,"storage reasoning uses fresh observed evidence")
	sim.elapsed_hours+=2
	check(not sim.storage_status(battery.id).known and sim.storage_status(battery.id).energy==null,"stale storage status does not expose hidden energy or causes")
	check(not sim.set_storage_intent("supply",NAN).ok and not sim.set_storage_intent("unknown",0.2).ok,"invalid strategy drafts are rejected")
	check(sim.storage_status(-1).has("reserve_soc"),"global status has the same public reserve field")
	check(not sim.operating_snapshot().totals.has("faults") and not sim.operating_snapshot().totals.has("max_loading"),"public operating snapshots do not leak unknown physical faults or precise hidden bottlenecks")

func _test_market_intent() -> void:
	var sim:=blank()
	var gas: Dictionary=sim._add_building("gas",Vector2i(3,3))
	var tie: Dictionary=sim._add_building("intertie",Vector2i(4,3))
	var home: Dictionary=sim._add_building("home",Vector2i(5,3))
	sim._add_line(gas.id,tie.id); sim._add_line(tie.id,home.id)
	sim.time_hours=1.0; sim.market.state.buy_limit=500
	check(sim.set_operating_intent("economic",false).ok,"economic procurement is independent of export permission")
	check(float(sim.totals.import_mw)>0 and near(float(sim.totals.gas_output),0),"economic operation buys cheaper imports before costly gas")
	check(not sim.operating_policy().allow_export and near(float(sim.totals.export_mw),0),"economic operation does not implicitly permit outward trade")
	check(sim.set_operating_intent("self_supply",false).ok and float(sim.totals.gas_output)>0,"self-supply preference has a different real dispatch outcome")
	check(sim.set_operating_intent("island",true).ok and near(float(sim.totals.import_mw),0) and not sim.operating_policy().allow_export,"island operation disables both directions even if export preference was set")
	check(sim.set_market_policy("trade",500,0).ok and sim.operating_policy().intent=="legacy_custom","legacy policy API retains its exact combined trading behavior")

func _test_storage_observed_policy_status() -> void:
	var sim:=blank()
	sim.time_hours=12.0
	var gas: Dictionary=sim._add_building("gas",Vector2i(3,3),{"enabled":false})
	var battery: Dictionary=sim._add_building("battery",Vector2i(4,3),{"storage_mode":"hold","reserve_soc":0.8})
	var customer: Dictionary=sim._add_building("home",Vector2i(5,3))
	sim._add_line(int(gas.id),int(battery.id)); sim._add_line(int(battery.id),int(customer.id))
	sim._refresh()
	check(sim.configure_facility(int(battery.id),{"enabled":true},"field").ok,"legacy storage status is obtained through a real on-site settings visit")
	sim.step(0.4)
	var old: Dictionary=sim.facility_observation(int(battery.id))
	check(old.trusted and "双向待机" in str(old.status) and "80%" in str(old.status),"fresh legacy observations retain the original hold-and-reserve description")
	check(sim.set_storage_intent("supply",0.1,int(battery.id),"field").ok,"new local supply intent is submitted as real work")
	check("双向待机" in str(sim.facility_observation(int(battery.id)).status),"pending supply intent does not rewrite the last measured legacy status")
	sim.step(0.4)
	var local: Dictionary=sim.facility_observation(int(battery.id))
	check(local.trusted and "有效保留 10%" in str(local.status) and "单机覆盖" in str(local.status) and "本地自动保供" in str(local.status),"fresh executed supply observation describes the effective reserve and local policy")
	check(not "双向待机" in str(local.status) and not "80%" in str(local.status) and float(local.output)>0,"supply observation agrees with actual discharge rather than stale legacy hold settings")
	var solar: Dictionary=sim.build("solar",Vector2i(6,3))
	check(solar.ok and sim.connect_buildings(int(battery.id),int(solar.id)).ok,"actual renewable expansion provides surplus charging power")
	check(sim.configure_facility(int(battery.id),{"enabled":true},"field").ok,"another on-site visit collects current storage measurements")
	sim.step(0.4)
	var charging: Dictionary=sim.facility_observation(int(battery.id))
	check(charging.trusted and float(charging.charging)>0 and "有效保留 10%" in str(charging.status),"fresh charging measurement and effective supply status remain consistent")
	check(sim.set_storage_intent("supply",0.25).ok and sim.set_storage_intent("inherit",0.9,int(battery.id),"field").ok,"device may explicitly inherit the global intent while its ignored local value differs")
	sim.step(0.4)
	var inherited: Dictionary=sim.facility_observation(int(battery.id))
	check(inherited.trusted and "继承全网" in str(inherited.status) and "有效保留 25%" in str(inherited.status) and not "90%" in str(inherited.status),"inherited status shows the global effective reserve instead of the ignored device reserve")
	sim.evolution.unlocked.append("smart_storage")
	sim.research_level=1
	check(sim.set_storage_intent("peak",0.2).ok and sim.configure_facility(int(battery.id),{"enabled":true},"field").ok,"unreachable-controller fixture has a real inherited peak intent and on-site visit")
	sim.step(0.4)
	var fallback: Dictionary=sim.facility_observation(int(battery.id))
	check(fallback.trusted and "继承全网" in str(fallback.status) and "有效保留 20%" in str(fallback.status) and "退回本地自动保供" in str(fallback.status),"new inherited peak status reports the actual local fallback and effective reserve")
	check(sim.evolution.storage_can_charge(sim,battery) and sim.evolution.storage_can_discharge(sim,battery),"unreachable inherited peak control really permits both local balancing directions")
	sim.step(1.2)
	var stale: Dictionary=sim.facility_observation(int(battery.id))
	check(not stale.trusted and not "退回本地" in str(stale.status),"status correction does not bypass stale-observation boundaries")
	check(sim.configure_facility(int(battery.id),{"storage_mode":"hold","reserve_soc":0.8},"field").ok,"legacy custom settings remain available as an explicit executed strategy")
	sim.step(0.4)
	var legacy: Dictionary=sim.facility_observation(int(battery.id))
	check(legacy.trusted and "双向待机" in str(legacy.status) and "80%" in str(legacy.status) and near(float(legacy.output),0) and near(float(legacy.charging),0),"explicit legacy custom behavior and measured legacy status remain unchanged")

func _test_migration_and_validation() -> void:
	var sim:=Sim.new()
	sim.start_management_game(); sim.connect_buildings(2,6); sim.step(0.4)
	var path:="user://test_management_progression.json"
	check(sim.save_game(path).ok,"new management game saves")
	var restored:=Sim.new()
	check(restored.load_game(path).ok and restored.management_status().active,"management route restores from schema seven")
	check(near(float(restored.management.state.hold_hours),float(sim.management.state.hold_hours)),"continuous operating progress survives a JSON round trip")
	var before:=JSON.stringify(restored.snapshot(),"",true,true)
	var invalid:=sim.snapshot()
	invalid.management.storage_reserve=1.5
	_write(path,invalid)
	check(not restored.load_game(path).ok and JSON.stringify(restored.snapshot(),"",true,true)==before,"invalid new policy state is rejected atomically")
	invalid=sim.snapshot(); invalid.management.stage=4
	_write(path,invalid)
	check(not restored.load_game(path).ok,"mismatched route stage and completed outcomes cannot be forged")
	var legacy:=Sim.new()
	legacy.expand_region()
	var data:=legacy.snapshot(); data.schema_version=6
	data.erase("management")
	data.region.cities[1].service_phase="prospect"
	data.buildings[8].storage_intent="supply"
	_write(path,data)
	check(restored.load_game(path).ok and not restored.management_status().active,"schema six loads with the management route disabled")
	check(restored.region.city_status(1).service_phase=="active" and restored.get_building(9).storage_intent=="legacy_custom","older saves preserve city responsibility and complex strategy even with future fields")
	check(near(restored.next_storm_at,legacy.next_storm_at),"legacy schedules never gain a preparation gate on load")
	var queued:=Sim.new()
	queued.set_dispatch(1,0.6,"field")
	var old_queue:=queued.snapshot()
	old_queue.schema_version=6
	old_queue.erase("management")
	for job in old_queue.digital.field_jobs:
		job.erase("started_at"); job.erase("duration")
	_write(path,old_queue)
	check(restored.load_game(path).ok and not restored.digital.field_jobs[0].has("duration"),"legacy in-flight jobs stay remaining-only rather than acquiring made-up progress")
	check(near(restored.next_event_hours(),0.35),"legacy in-flight job completion remains a real known event")
	restored.step(0.4)
	check(near(float(restored.get_building(1).dispatch),0.6),"legacy accepted command still executes after schema seven migration")
	var bad_queue:=queued.snapshot()
	bad_queue.digital.field_jobs[0].duration=0.1
	_write(path,bad_queue)
	check(not restored.load_game(path).ok,"task duration shorter than its actual remaining work is rejected")
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

func _test_contract_with_operating_intent() -> void:
	var sim:=blank()
	var gas: Dictionary=sim._add_building("gas",Vector2i(3,3))
	var tie: Dictionary=sim._add_building("intertie",Vector2i(4,3))
	var factory: Dictionary=sim._add_building("factory",Vector2i(5,3),{"base_demand":10.0})
	sim._add_line(int(gas.id),int(tie.id)); sim._add_line(int(tie.id),int(factory.id))
	sim.time_hours=1.0
	sim._refresh()
	check(sim.sign_supply_contract(4.0,12.0).ok,"operating-intent regression starts with a real signed fixed-power contract")
	var committed_rate:=float(sim.market.state.contract_mw)*float(sim.market.state.contract_price)
	check(sim.set_market_policy("off",500,0).ok,"legacy advanced policy can suspend physical exchange without canceling the contract")
	check(near(float(sim.totals.import_mw),0) and near(float(sim.totals.contract_import_mw),0) and near(float(sim.totals.contract_cost),committed_rate),"legacy-off mode stops delivery but retains the contractual hourly charge")
	for intent in ["economic","self_supply"]:
		check(sim.set_operating_intent(intent,false).ok and sim.market.state.market_mode=="off","front-end %s intent supersedes a stored legacy-off flag" % intent)
		check(near(float(sim.totals.contract_import_mw),4.0) and float(sim.totals.import_mw)>=4.0,"effective %s operation consumes the prepaid quota before additional procurement" % intent)
		var spot_cost:=maxf(0,float(sim.totals.import_mw)-float(sim.totals.contract_import_mw))*float(sim.market.state.spot_price)
		check(near(float(sim.totals.import_cost),spot_cost) and near(float(sim.totals.contract_cost),committed_rate),"effective %s does not double-bill prepaid delivery as spot imports" % intent)
		if intent=="self_supply": check(near(float(sim.totals.import_mw),4.0) and float(sim.totals.gas_output)>0,"self-supply still takes prepaid delivery before using local gas for the remainder")
		var before: Dictionary=sim.market.ledger[-1].duplicate(true) if not sim.market.ledger.is_empty() else {}
		sim.step(0.1)
		var entry: Dictionary=sim.market.ledger[-1]
		check(near(float(entry.contract_cost)-float(before.get("contract_cost",0)),committed_rate*0.1),"%s intent settles the signed contract exactly once per elapsed interval" % intent)
		check(float(entry.import_mwh)-float(before.get("import_mwh",0))>=0.4-0.00001,"%s prepaid delivery becomes real delivered MWh in the ledger" % intent)
	check(sim.set_operating_intent("island",true).ok,"island intent can suspend a previously active prepaid interface")
	check(near(float(sim.totals.import_mw),0) and near(float(sim.totals.contract_import_mw),0) and near(float(sim.totals.import_cost),0),"effective island mode does not deliver or spot-charge contract electricity")
	var prior: Dictionary=sim.market.ledger[-1].duplicate(true)
	sim.step(0.1)
	check(near(float(sim.market.ledger[-1].contract_cost)-float(prior.contract_cost),committed_rate*0.1),"island operation still pays the fixed contractual commitment")
	check(near(float(sim.market.ledger[-1].import_mwh),float(prior.import_mwh)),"island contractual payment does not manufacture delivered energy")
	check(sim.set_operating_intent("economic",false).ok and near(float(sim.totals.contract_import_mw),4.0),"reopening exchange resumes the remaining prepaid quota")
	var path:="user://test_management_contract_intent.json"
	check(sim.save_game(path).ok,"effective intent and a legacy-off contract state can be saved")
	var restored:=Sim.new()
	check(restored.load_game(path).ok and restored.market.state.market_mode=="off" and near(float(restored.totals.contract_import_mw),4.0),"loaded effective intent retains prepaid priority over the legacy-off flag")
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

func _test_campaign_intent() -> void:
	var sim:=Sim.new()
	check(sim.start_campaign(15).ok,"final historical chapter retains its independent capability gates")
	var battery: Dictionary={}
	for x in range(3,14):
		for y in range(3,14):
			var result: Dictionary=sim.build("community_battery",Vector2i(x,y))
			if result.ok: battery=sim.get_building(int(result.id)); break
		if not battery.is_empty(): break
	check(not battery.is_empty(),"final lesson can build its real community storage")
	if battery.is_empty(): return
	check(sim.connect_buildings(int(sim.campaign.roles.node),int(battery.id)).ok,"community storage uses a real power connection")
	check(sim.connect_communication(int(sim.campaign.roles.root),int(battery.id),"fiber").ok,"community storage receives its own trusted communication path")
	sim.step(0.25)
	check(sim.digital.can_configure(sim,int(battery.id)),"remote storage editing has actual fresh telemetry and permission")
	check(sim.set_storage_intent("peak",0.25,int(battery.id),"remote").ok,"new intent editor queues a genuine remote settings command")
	check(not sim.campaign._qualifies(sim,"coordinated_storage"),"acceptance does not count as executed coordinated storage")
	sim.step(0.25)
	check(sim.campaign._qualifies(sim,"coordinated_storage"),"new intent and reserve command fulfills the historical coordinated-storage outcome after execution")
	var observed: Dictionary=sim.facility_observation(int(battery.id))
	check(observed.trusted and "有效保留 25%" in str(observed.status) and "可信削峰" in str(observed.status),"actual remote peak execution is reflected in the fresh trusted storage status")
	check(sim._valid_save(sim.snapshot()),"new intent in a historical scenario remains a valid saved campaign")

func _write(path: String,data: Dictionary) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
