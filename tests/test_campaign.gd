extends SceneTree
## Reference solutions use only player-facing API calls after each fixture is loaded.
const Sim = preload("res://scripts/sim/grid_sim.gd")
const Campaign = preload("res://scripts/sim/campaign.gd")
const Catalog = preload("res://scripts/sim/campaign_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	check(Catalog.chapters().size()==15,"fifteen documented historical chapters")
	for chapter_id in range(1,16):
		var sim: RefCounted = Sim.new()
		ok(sim.start_campaign(chapter_id),"start chapter %d" % chapter_id)
		check(sim.objectives.is_empty(),"campaign does not inherit modern reward objectives")
		check(sim.cash==float(sim.campaign.chapter().budget.total),"documented reference budget sets chapter funds")
		check(Campaign.valid_snapshot(sim.campaign.snapshot()),"chapter fixture has a valid runtime snapshot")
		_checkpoint(sim,"chapter_%d_open" % chapter_id)
		_replay(sim,chapter_id)
		_finish(sim,70.0)
		check(sim.campaign.completed and not sim.campaign.failed,"chapter %d completes through real actions: %s / %s" % [chapter_id,sim.campaign.current_step().title,sim.campaign.failure_reason])
		check(sim.cash>-20000.0,"chapter %d remains solvent" % chapter_id)
		if chapter_id==8: check(sim.campaign.charged_mwh>=8.0 and sim.campaign.discharged_mwh>=2.0,"pumped storage actually charges before delivering energy")
		if chapter_id==15: check(sim.campaign.assessment_net>=0.0,"final full-day window has nonnegative actual operating profit")
		print("CAMPAIGN CHAPTER %d: step %d, completed=%s, cash=%.0f, t=%.2f" % [chapter_id,sim.campaign.step_index,str(sim.campaign.completed),sim.cash,sim.elapsed_hours])
	_test_queries_and_receipts()
	_test_hardened_recovery()
	print("CAMPAIGN TESTS: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+message)

func ok(result: Dictionary, message: String) -> int:
	check(bool(result.get("ok",false)),message+" — "+str(result.get("message","")))
	return int(result.get("id",-1))

func _advance(sim: RefCounted, hours: float) -> void:
	var remaining := hours
	while remaining>0.000001 and not sim.campaign.completed and not sim.campaign.failed:
		var dt := minf(remaining,0.05)
		sim.step(dt)
		remaining-=dt

func _finish(sim: RefCounted, hours: float) -> void:
	_advance(sim,hours)

func _checkpoint(sim: RefCounted, tag: String) -> void:
	var path := "user://test_campaign_"+tag+".json"
	ok(sim.save_game(path),"save "+tag)
	var restored: RefCounted = Sim.new()
	ok(restored.load_game(path),"load "+tag)
	check(restored.campaign.chapter_id==sim.campaign.chapter_id and restored.campaign.step_index==sim.campaign.step_index,"checkpoint preserves current lesson")
	check(absf(float(restored.campaign.hold_hours)-float(sim.campaign.hold_hours))<0.000001,"checkpoint preserves duration without advancing it")
	check(restored.campaign.flags==sim.campaign.flags,"checkpoint preserves executed action evidence")
	if sim.campaign.active and not sim.campaign.completed and not sim.campaign.failed:
		restored.step(0.05)
		check(not restored.campaign.failed,"checkpoint can resume real simulation")
	ok(sim.load_game(path),"continue actual reference solution from restored "+tag)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _replay(sim: RefCounted, chapter_id: int) -> void:
	var r: Dictionary = sim.campaign.roles
	match chapter_id:
		1:
			ok(sim.connect_buildings(r.node,r.customer),"connect first customer")
			var home := ok(sim.build("home",Vector2i(8,8)),"build new street")
			var generator := ok(sim.build("dc_dynamo",Vector2i(8,9)),"add local generation for growing demand")
			ok(sim.connect_buildings(generator,r.node),"connect local generation")
			ok(sim.connect_buildings(home,r.node),"connect new street")
		2:
			ok(sim.research_technology("ac_systems"),"research AC")
			_advance(sim,1.1)
			ok(sim.connect_buildings(r.source,r.node),"connect water-powered AC exhibition")
		3:
			ok(sim.configure_facility(r.source,{"dispatch":1.0},"field"),"queue coal startup setting")
			check(sim.campaign.step_index==0,"accepted setting is not executed evidence")
			_checkpoint(sim,"coal_in_transit")
			_advance(sim,10.0)
		4:
			ok(sim.patrol_line(r.main_feeder),"inspect constrained feeder")
			_advance(sim,0.55)
			ok(sim.upgrade_line(r.main_feeder),"increase feeder capacity")
			ok(sim.connect_buildings(r.backup,r.customer),"build an alternate path")
			ok(sim.field_switch(r.main_feeder),"isolate main feeder for planned maintenance")
			_advance(sim,0.4)
		5:
			ok(sim.connect_buildings(r.source,r.node),"connect valley hydro")
			ok(sim.configure_facility(r.source,{"environmental_release":0.25},"field"),"set ecological release")
			_advance(sim,0.4)
			_checkpoint(sim,"valley_service")
		6:
			var terminal := ok(sim.build("hvdc",Vector2i(4,4)),"build mainland converter")
			ok(sim.connect_buildings(terminal,r.node),"connect external supply")
			ok(sim.upgrade_line(r.main_feeder),"upgrade island feeder")
		7:
			var cooling := ok(sim.build("cooling",Vector2i(6,5)),"build reactor cooling")
			var academy := ok(sim.build("academy",Vector2i(8,5)),"build operating academy")
			ok(sim.connect_buildings(cooling,r.node),"supply cooling auxiliaries")
			ok(sim.connect_buildings(academy,r.node),"supply academy auxiliaries")
			ok(sim.configure_facility(r.source,{"dispatch":1.0},"field"),"queue reactor startup")
			_advance(sim,10.0)
			_checkpoint(sim,"reactor_starting")
		8:
			var pumped := ok(sim.build("pumped_storage",Vector2i(28,28)),"build hillside pumped storage")
			ok(sim.connect_buildings(pumped,r.node),"connect real storage")
			_advance(sim,3.0)
			_checkpoint(sim,"pumped_night")
		9:
			ok(sim.set_market_policy("trade",500.0,90.0),"apply procurement policy")
			ok(sim.set_tariff("flat",85.0,145.0,220.0),"apply retail tariff")
			ok(sim.sign_supply_contract(3.0,12.0),"sign a twelve-hour supply commitment")
			_advance(sim,6.0)
			_checkpoint(sim,"contract_halfway")
		10:
			var wind := ok(sim.build("wind",Vector2i(4,10)),"build additional wind capacity")
			ok(sim.connect_buildings(wind,r.node),"connect coastal wind")
			ok(sim.configure_facility(r.source,{"dispatch":1.0},"field"),"submit dispatchable reserve")
			_advance(sim,0.4)
		11:
			ok(sim.commission_device(r.root,"root"),"commission dispatch root")
			ok(sim.connect_communication(r.root,r.node,"fiber"),"build separate feeder communication")
			ok(sim.connect_communication(r.root,r.customer,"fiber"),"build separate customer communication")
			ok(sim.research(),"enable L1 telemetry")
			_advance(sim,0.2)
			_checkpoint(sim,"fresh_telemetry")
		12:
			_advance(sim,0.1)
			ok(sim.remote_switch(r.tie),"submit remote tie closure")
			check(sim.campaign.step_index==0,"accepted remote command does not complete tutorial")
			_advance(sim,0.2)
			ok(sim.research(),"enable L2 facility control")
			ok(sim.configure_facility(r.source,{"dispatch":1.0},"remote"),"submit verified facility control")
			_advance(sim,0.2)
			ok(sim.demand_response(),"activate controllable loads")
			check(sim.campaign.step_index==2,"submitted response needs a real later settlement tick")
			_advance(sim,0.1)
		13:
			_advance(sim,0.1)
			ok(sim.campaign_action("begin_assessment"),"start deterministic snow assessment")
			_advance(sim,0.4)
			check(sim.get_line(r.tie).closed,"self-healing actually closes the healthy tie")
			ok(sim.repair_line(r.main_feeder),"repair the damaged physical feeder")
			_advance(sim,0.7)
			_checkpoint(sim,"snow_recovery")
		14:
			_advance(sim,0.1)
			ok(sim.campaign_action("begin_assessment"),"start persistent intrusion")
			ok(sim.isolate_device(r.attack_target,true),"isolate affected gateway")
			ok(sim.patrol_line(r.main_feeder),"independently verify physical feeder")
			ok(sim.field_switch(r.tie),"restore critical load by field switching")
			_advance(sim,0.55)
			ok(sim.recover_device(r.attack_target),"start actual patch recovery")
			check(not sim.campaign.flags.has("patch:%d" % int(r.attack_target)),"accepted recovery is not executed patch evidence")
			_advance(sim,0.8)
			ok(sim.isolate_device(r.attack_target,false),"reconnect recovered gateway")
			_advance(sim,0.1)
			_checkpoint(sim,"trusted_recovery")
		15:
			var solar := ok(sim.build("solar",Vector2i(10,4)),"build daytime solar")
			ok(sim.connect_buildings(solar,r.node),"deliver solar to customers")
			_advance(sim,0.1)
			var battery := ok(sim.build("community_battery",Vector2i(9,10)),"build community storage")
			ok(sim.connect_buildings(battery,r.node),"connect local storage power")
			ok(sim.connect_communication(r.root,battery,"fiber"),"connect storage control communication")
			_advance(sim,0.1)
			ok(sim.configure_facility(battery,{"storage_mode":"peak","peak_hour":17.0,"reserve_soc":0.2},"remote"),"schedule actual trusted community peak control")
			_advance(sim,0.2)
			ok(sim.campaign_action("begin_assessment"),"start full-day clean operation")
			_advance(sim,12.0)
			_checkpoint(sim,"final_half_day")

func _test_queries_and_receipts() -> void:
	var sim: RefCounted = Sim.new()
	ok(sim.start_campaign(12),"start receipt boundary")
	for _index in range(30): sim._refresh()
	check(sim.campaign.step_index==0 and sim.campaign.hold_hours==0.0,"queries cannot advance action gates or duration")
	sim.campaign.record_action("remote_switch",int(sim.campaign.roles.tie),{"phase":"rejected"})
	check(not sim.campaign.flags.has("remote_switch"),"rejected commands never count as successful actions")
	var snapshot: Dictionary = sim.campaign.snapshot()
	snapshot.step_index=100
	check(not Campaign.valid_snapshot(snapshot),"out-of-range lesson rejected")
	snapshot=sim.campaign.snapshot()
	snapshot.required_customers=[]
	check(not Campaign.valid_snapshot(snapshot),"empty required customers rejected")
	var observation_sim: RefCounted = Sim.new()
	ok(observation_sim.start_campaign(11),"start observation schema check")
	snapshot=observation_sim.campaign.snapshot()
	snapshot.roles.erase("main_feeder")
	check(not Campaign.valid_snapshot(snapshot),"observation lesson requires its referenced main feeder")

func _test_hardened_recovery() -> void:
	var sim: RefCounted = Sim.new()
	ok(sim.start_campaign(14),"start hardened incident classroom")
	ok(sim.set_security_policy("zero_trust"),"harden policy before assessment")
	ok(sim.upgrade_security(),"upgrade protection before assessment")
	_replay(sim,14)
	_finish(sim,5.0)
	check(sim.campaign.completed,"controlled local recovery lesson remains solvable after prior security upgrades")
	check(sim.campaign.flags.has("patch:%d" % int(sim.campaign.roles.attack_target)),"hardened lesson still requires real executed patch")
	var bypass: RefCounted = Sim.new()
	ok(bypass.start_campaign(14),"start isolation evidence boundary")
	_advance(bypass,0.1)
	ok(bypass.campaign_action("begin_assessment"),"inject isolation boundary event")
	ok(bypass.isolate_device(int(bypass.campaign.roles.attack_target),false),"a reconnect is a successful but different operation")
	ok(bypass.patrol_line(int(bypass.campaign.roles.main_feeder)),"complete independent field check")
	_advance(bypass,0.55)
	check(bypass.campaign.step_index==1,"reconnecting a gateway cannot stand in for actual isolation")
