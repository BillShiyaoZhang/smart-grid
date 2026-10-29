extends SceneTree
## Actual inspector buttons route through observation and execution boundaries.
var game: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("FAIL: "+message)

func button(parent: Node,caption: String) -> Button:
	if parent is Button and caption in parent.text: return parent
	for child in parent.get_children():
		var found := button(child,caption)
		if found!=null: return found
	return null

func text_in(parent: Node) -> String:
	var result := str(parent.text)+"\n" if parent is Label else ""
	for child in parent.get_children(): result+=text_in(child)
	return result

func readout(parent: Node) -> Control:
	if parent.get_script()==preload("res://scripts/ui/facility_readout.gd"): return parent
	for child in parent.get_children():
		var found := readout(child)
		if found!=null: return found
	return null

func _run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false); game._activate_session()
	game.sim.next_storm_at=100000.0; game.sim.digital.next_attack_at=100000.0
	game.sim.connect_buildings(2,6)
	game.selected_id=2; game._update_inspector()
	check(button(game.inspector_box,"升级").disabled,"inspector disables upgrades without modeled capability gains")
	game.selected_id=1; game._update_inspector()
	var remote := button(game.inspector_box,"远程0%")
	var field := button(game.inspector_box,"现场0%")
	check(remote!=null and remote.disabled and field!=null and not field.disabled,"early game shows the real remote requirement and an available field alternative")
	var before: float=game.sim.elapsed_hours
	var cash: float=game.sim.cash
	field.pressed.emit()
	check(game.sim.get_building(1).dispatch==1.0 and game.sim.digital.field_jobs.size()==1,"actual field button queues a command without instant shutdown")
	check(game.sim.elapsed_hours==before and is_equal_approx(float(game.sim.cash),cash-350.0),"field button pays travel cost without silently advancing time")
	game.sim.step(.35); game._sync_world(true); game._update_inspector()
	check(game.sim.get_building(1).dispatch==0.0 and game.sim.digital.field_jobs.is_empty(),"real field execution applies the setting after travel")
	var measured := readout(game.inspector_box)
	check(measured!=null and measured.snapshot.trusted and is_zero_approx(float(measured.snapshot.output)),"onsite acknowledgement updates the visual readout to the measured zero output")
	game.sim.research(); game.sim.research(); game.sim.step(.05)
	game._update_inspector()
	remote=button(game.inspector_box,"远程100%")
	check(not remote.disabled,"fresh telemetry and research enable the inspector remote control")
	remote.pressed.emit()
	check(game.sim.get_building(1).dispatch==0.0 and game.sim.digital.pending_commands.size()==1,"remote inspector button queues rather than directly mutating generation")
	game.sim.isolate_device(1,true)
	game.sim.step(.2); game._update_inspector()
	check(game.sim.get_building(1).dispatch==0.0,"in-flight inspector command is refused when the path is lost")
	check("遥测未确认" in text_in(game.inspector_box) and button(game.inspector_box,"远程100%").disabled,"inspector masks measurements and disables remote control under isolation")
	game.planning_panel.open(); game.planning_panel.select_facility(1)
	check(not "每小时燃料" in game.planning_panel.facility_info.text,"planning cannot bypass the same missing observation")
	game.planning_panel.close()
	game.sim.expand_region()
	var city: Dictionary=game.sim.region.cities[1]
	game.selected_id=int(city.building_ids[0]); game._update_inspector()
	check(button(game.inspector_box,"拆除设施 · 回收 ¥0")!=null,"municipal assets clearly disclose zero refund before demolition")
	game.queue_free()
	await process_frame
	print("FACILITY UI: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)
