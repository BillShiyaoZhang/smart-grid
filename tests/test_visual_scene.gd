extends SceneTree
## Outcome-oriented coverage for the integrated map, time controls and readout boundaries.
var checks := 0
var failures := 0
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+message)

func button(parent: Node, caption: String) -> Button:
	if parent is Button and caption in parent.text: return parent
	for child in parent.get_children():
		var found := button(child,caption)
		if found!=null: return found
	return null

func meter(parent: Node) -> Control:
	if parent.get_script()==preload("res://scripts/ui/facility_readout.gd"): return parent
	for child in parent.get_children():
		var found := meter(child)
		if found!=null: return found
	return null

func settle() -> void:
	for i in range(5): await process_frame

func label_text(parent: Node) -> String:
	var result: String=parent.text+"\n" if parent is Label else ""
	for child in parent.get_children(): result+=label_text(child)
	return result

func _run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	check(button(game.welcome,"开始运营")!=null and button(game.welcome,"自由沙盘")!=null,"guided management and free sandbox are distinct real welcome actions")
	button(game.welcome,"开始运营").pressed.emit()
	check(not game.welcome.visible and game.sim.management_status().active,"primary welcome action starts the actual progressive management model")
	check(game.sim.management_status().stage==0,"new management starts with the first connection stage")
	game._begin_free_sandbox(true)
	check(not game.sim.management_status().active,"free sandbox explicitly restores the complete legacy operating mode")
	game.sim.next_storm_at=1000.0
	game.sim.digital.next_attack_at=1000.0
	game.focus_target("building",1)
	await settle()
	var unknown := meter(game.inspector_box)
	check(unknown!=null and not unknown.snapshot.trusted and unknown.snapshot.output==null,"unknown plant output reaches the visual control as unknown, never as zero")
	game.sim.get_building(1).health=1.0
	game._update_inspector()
	check(meter(game.inspector_box).snapshot.health==null,"inspector does not expose raw hidden health through visual snapshots")
	game.sim.get_building(1).health=100.0
	var result: Dictionary=game.sim.set_dispatch(1,0.5,"field")
	check(result.ok,"onsite operating change is accepted before the waiting workflow")
	var original_speed: int=game.speed
	var before: float=game.sim.elapsed_hours
	var waited: Dictionary=game.wait_for_next_event()
	check(waited.ok and waited.advanced>0 and waited.advanced<=0.35001,"next-event waiting stops at the actual field completion instead of a fixed hour")
	check(is_equal_approx(float(game.sim.get_building(1).dispatch),0.5),"the awaited field change is really applied")
	check(game.speed==original_speed,"manual advancement preserves the selected return speed")
	check(game.chart.sample_hours.size()>1 and float(game.chart.sample_hours[-1])==float(game.sim.elapsed_hours),"time advancement records real intermediate observations and the actual final time")
	var known := meter(game.inspector_box)
	check(known.snapshot.trusted and known.snapshot.output!=null,"execution acknowledgement supplies the real current plant readout")
	var identity: int=known.get_instance_id()
	game._update_inspector()
	check(meter(game.inspector_box).get_instance_id()==identity,"routine updates preserve the live readout control")
	game.sim.connect_buildings(2,6)
	game.sim.research()
	game.sim.research()
	game.sim.step(.05)
	game.sim.set_dispatch(1,1.0,"remote")
	game.sim.isolate_device(1,true)
	var refusal: Dictionary=game.wait_for_next_event()
	check(refusal.ok and "拒绝" in refusal.message,"waiting surfaces a real in-flight rejection")
	check(is_equal_approx(float(game.sim.get_building(1).dispatch),0.5),"rejected command cannot appear as an effective setpoint")
	game.sim.isolate_device(1,false)
	before=game.sim.elapsed_hours
	game.market_panel.open()
	game.market_panel.refresh()
	game._update_hud()
	check(float(game.sim.elapsed_hours)==before,"opening, refreshing and graph drawing do not advance time")
	game.market_panel.close()
	game._begin_free_sandbox(true)
	game.speed=0
	game.sim.next_storm_at=.1
	game.sim.digital.next_attack_at=1000
	game.advance_management(3.5)
	check(game.sim.storm_count==1 and not game.sim.storm_active,"one manual advance can cross the complete real storm")
	check(game.chart.events.any(func(event: Dictionary): return event.title=="风暴抵达") and game.chart.events.any(func(event: Dictionary): return event.title=="风暴离开"),"manual advance records both real weather events rather than only the final state")
	game._rebuild_session(false)
	check(game.chart.events.size()>=2,"saved observation history restores observed storm transitions")
	game.sim.explore_region()
	var city: Dictionary=game.sim.region.city_status(1)
	game.focus_target("building",int(city.building_ids[0]))
	var explanation: String=label_text(game.inspector_box)
	check(not game.sim.customer_service_active(int(city.building_ids[0])) and "尚未开通服务" in explanation,"prospective customer inspector identifies service responsibility explicitly")
	check(not "供电中断" in explanation and not "用户报告停电" in explanation and meter(game.inspector_box)==null,"prospective customers are not mislabeled or charted as current outages")
	game.queue_free()
	await settle()
	print("VISUAL SCENE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
