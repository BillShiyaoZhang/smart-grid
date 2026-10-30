extends SceneTree
const Sim=preload("res://scripts/sim/grid_sim.gd")
const Delta=preload("res://scripts/ui/decision_delta.gd")
var checks:=0
var failures:=0

func _initialize() -> void: _run.call_deferred()

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+message)

func _world() -> RefCounted:
	var sim: RefCounted=Sim.new()
	sim.buildings.clear(); sim.lines.clear(); sim.objectives.clear()
	sim.next_building_id=1; sim.next_line_id=1
	sim.digital.reset(sim)
	sim.digital.next_attack_at=10000.0; sim.next_storm_at=10000.0
	sim.record_cash_change(820000.0,"test","测试资金")
	var gas: Dictionary=sim._add_building("gas",Vector2i(2,2))
	var load: Dictionary=sim._add_building("factory",Vector2i(4,2))
	var hospital: Dictionary=sim._add_building("hospital",Vector2i(4,4))
	sim._add_line(int(gas.id),int(load.id))
	sim._add_line(int(gas.id),int(hospital.id))
	sim._solve(0.0)
	for building in sim.buildings: sim.digital._sample_facility(sim,building,"field")
	for line in sim.lines: sim.digital._sample(sim,line,"patrol")
	return sim

func _canonical(sim: RefCounted) -> String:
	return JSON.stringify(sim.snapshot(),"",true,true)+JSON.stringify(sim.operation_receipts(),"",true,true)

func _row(rows: Array,id: String) -> Dictionary:
	for item in rows:
		if item.id==id: return item
	return {}

func _wait(workbench: Node) -> void:
	var deadline:=Time.get_ticks_msec()+30000
	while workbench.calculating and Time.get_ticks_msec()<deadline: await process_frame
	check(not workbench.calculating,"real worker completes within a bounded timeout")

func _key(code: Key) -> void:
	var event:=InputEventKey.new()
	event.keycode=code; event.pressed=true
	root.push_input(event,true)
	event=event.duplicate(); event.pressed=false
	root.push_input(event,true)

func _test_asset_plans() -> void:
	var sim:=_world()
	var instruction: Dictionary={"maintenance":{"target_type":"facility","target_id":1,"action":"inspect"}}
	var before:=_canonical(sim)
	check(not sim.planning_forecast(instruction,2).ok and not sim.lifecycle.enabled,"uncommissioned asset preview fails without silently enabling real rules")
	check(_canonical(sim)==before,"unavailable maintenance preview preserves the whole real world")
	sim.lifecycle.enable(sim)
	var quote: Dictionary=sim.lifecycle.quote(sim,"facility",1,"inspect")
	before=_canonical(sim)
	var current: Dictionary=sim.planning_forecast({},2)
	var inspect: Dictionary=sim.planning_forecast(instruction,2)
	check(current.ok and inspect.ok,"commissioned maintenance is modeled with a real disposable work order")
	check(inspect.maintenance_quote.cost==quote.cost and inspect.maintenance_quote.work_hours==quote.work_hours and inspect.maintenance_quote.spares==quote.spares,"preview uses the actual lifecycle quote rather than arbitrary investment numbers")
	check(is_equal_approx(float(inspect.net_cash)-float(current.net_cash),-float(quote.cost)),"cash delta includes the up-front inspection fee exactly once")
	check(is_equal_approx(float(inspect.served_mwh),float(current.served_mwh)),"inspection preserves operation while the field crew verifies the device")
	var alternatives: Dictionary=sim.compare_operating_plans([{}, {"maintenance":{"target_type":"facility","target_id":1,"action":"service"}}, {"maintenance":{"target_type":"facility","target_id":1,"action":"replace"}}])
	check(alternatives.ok and alternatives.plans.size()==3,"continue, actual service and replacement share the common 24-hour world model")
	check(float(alternatives.plans[1].unserved_mwh)>float(alternatives.plans[0].unserved_mwh),"servicing the only generator causes actual modeled downtime")
	check(float(alternatives.plans[2].unserved_mwh)>float(alternatives.plans[1].unserved_mwh),"longer replacement work carries a larger delivery consequence")
	check(float(alternatives.plans[2].maintenance_quote.cost)>float(alternatives.plans[1].maintenance_quote.cost) and alternatives.plans[2].maintenance_quote.spares==2,"replacement reports the real higher charge and reserved spares")
	check(_canonical(sim)==before,"every alternative leaves real cash, spares, queues, health and RNG unchanged")
	sim.lifecycle.spares=1
	check(not sim.planning_forecast({"maintenance":{"target_type":"facility","target_id":1,"action":"replace"}},2).ok,"maintenance comparison respects actual spare inventory")
	sim.lifecycle.spares=4
	check(not sim.planning_forecast({"maintenance":{"target_type":"line","target_id":9999,"action":"service"}},2).ok,"nonexistent maintenance target fails visibly")
	check(not sim.planning_forecast({"maintenance":{"target_type":"facility","target_id":1,"action":"invented"}},2).ok,"unrecognized work action is rejected")
	check(sim.configure_facility(1,{"dispatch":.5},"field").ok and sim.configure_facility(3,{"enabled":true},"field").ok,"public field orders can occupy both crews before maintenance")
	var waiting: Dictionary=sim.planning_forecast({"maintenance":{"target_type":"line","target_id":1,"action":"inspect"}},2)
	check(waiting.ok and waiting.maintenance_quote.initial_status=="queued","isolated maintenance uses the real queue instead of assuming immediate crew availability")
	check("未定时长" in "\n".join(waiting.assumptions),"the queue comparison explicitly declines to invent a departure ETA")
	var hidden_sim:=_world()
	hidden_sim.lifecycle.enable(hidden_sim)
	hidden_sim.digital.observations.clear(); hidden_sim.digital.facility_observations.clear()
	var assumed: Dictionary=hidden_sim.planning_forecast({"maintenance":{"target_type":"facility","target_id":1,"action":"service"}},2)
	hidden_sim.get_building(1).health=0.0; hidden_sim.get_building(1).online=false; hidden_sim.get_building(1).lifecycle_failure=true
	var concealed: Dictionary=hidden_sim.planning_forecast({"maintenance":{"target_type":"facility","target_id":1,"action":"service"}},2)
	check(assumed.ok and concealed.ok and assumed.rows==concealed.rows and assumed.maintenance_quote==concealed.maintenance_quote,"maintenance quote and effects cannot reveal hidden device damage or failure causes")
func _run() -> void:
	var sim:=_world()
	var before:=_canonical(sim)
	var result: Dictionary=sim.compare_operating_plans([{}, {"generator_id":1,"dispatch":0.0,"imports":false},{"outage_line":1}])
	check(result.ok and result.plans.size()==3,"three actual independent plans calculate successfully")
	check(_canonical(sim)==before,"delta metrics do not advance or mutate the real world")
	for plan in result.plans:
		check(plan.horizon_hours==24 and plan.rows.size()==24 and plan.sample_hours==.25,"all plans use the same declared horizon and sampling step")
		check(plan.source_elapsed_hours==sim.elapsed_hours,"every plan records the same source time")
		check(is_equal_approx(float(plan.served_mwh)+float(plan.unserved_mwh),float(plan.demand_mwh)),"served plus unserved energy equals demand over the common horizon")
		check(float(plan.clean_served_mwh)>=0.0 and float(plan.clean_served_mwh)<=float(plan.served_mwh)+.00001,"clean reference energy is bounded by energy delivered")
		check(is_finite(float(plan.min_reserve_mw)) and float(plan.local_carbon_tonnes)>=0.0,"reserve minimum and local generation emissions remain finite")
		check("不含外购电隐含排放" in "\n".join(plan.assumptions) and "负荷点" in "\n".join(plan.assumptions),"projection explains emission scope and critical-customer point basis")
	check(result.plans[1].critical_unserved_points==1 and result.plans[1].critical_unserved_point_hours>0.0,"generator shutdown exposes the actual hospital interruption consequence")
	check(result.plans[1].unserved_mwh>result.plans[0].unserved_mwh and result.plans[1].min_reserve_mw<result.plans[0].min_reserve_mw,"loss of generation worsens delivery and minimum power reserve")
	var rows:=Delta.rows_for(result.plans)
	check(is_equal_approx(float(_row(rows,"served_mwh").delta),float(result.plans[1].served_mwh)-float(result.plans[0].served_mwh)),"table compares delivered energy rather than end-of-horizon MW")
	check(is_equal_approx(float(_row(rows,"max_loading").delta),(float(result.plans[1].max_loading)-float(result.plans[0].max_loading))*100),"capacity-rate changes use percentage points")
	check(_row(rows,"min_voltage").preferred=="higher" and _row(rows,"max_loading").preferred=="lower","voltage minima and utilization maxima have the correct direction of improvement")
	check(is_equal_approx(float(_row(rows,"net_cash").contingency_delta),float(result.plans[2].net_cash)-float(result.plans[1].net_cash)),"contingency difference is measured against the selected plan")
	var view:=Delta.new()
	root.add_child(view)
	view.set_results(result.plans)
	check(view.charts.get_child_count()==3,"all three computed plans receive a chart")
	for chart in view.charts.get_children(): check(chart.maximum==view.shared_maximum,"small multiples share a zero-based MW scale")
	view.size.x=600; view._adapt()
	check(view.charts.columns==1,"narrow viewport stacks small multiples without changing scales")
	view.set_stale(true,"测试状态变化")
	check(view.stale and "已过期" in view.validity.text,"outdated evidence remains visibly labeled")
	view.queue_free()
	# Hidden electrical differences cannot become new plan outcomes, even after
	# asset risk management has been commissioned.
	sim.lifecycle.enable(sim)
	sim.digital.observations.clear(); sim.digital.facility_observations.clear()
	var unknown: Dictionary=sim.planning_forecast({},2)
	sim.get_building(1).health=5.0; sim.get_building(1).online=false; sim.get_building(1).lifecycle_failure=true
	sim.get_line(1).health=0.0; sim.get_line(1).fault=true; sim.get_line(1).closed=false; sim.get_line(1).lifecycle_failure=true
	var hidden: Dictionary=sim.planning_forecast({},2)
	for key in ["rows","served_mwh","demand_mwh","unserved_mwh","clean_served_mwh","min_reserve_mw","local_carbon_tonnes","critical_unserved_points","critical_unserved_point_hours"]:
		check(unknown[key]==hidden[key],"unknown fault and condition changes never leak into "+key)
	_test_asset_plans()

	var game: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false); game._activate_session(); game.speed=0
	game.sim.next_storm_at=10000.0; game.sim.digital.next_attack_at=10000.0
	game.planning_panel.open(); game.planning_panel.tabs.current_tab=3
	var bench: Node=game.planning_panel.decision_workbench
	before=_canonical(game.sim)
	check(bench.preview_target("line",1) and bench._selected("failure_type")=="line" and int(bench._selected("failure_line"))==1,"object preview selects the requested contingency without executing it")
	check(bench.preview_target("facility",1) and int(bench._selected("generator"))==1,"object preview selects the real generator")
	check(not bench.preview_target("line",99999) and _canonical(game.sim)==before,"invalid target and navigation never alter simulation")
	bench.actions.compare.grab_focus()
	await process_frame
	_key(KEY_ENTER)
	await process_frame
	check(bench.calculating,"keyboard activates the actual comparison button")
	await _wait(bench)
	check(bench.delta_view.plans.size()==3 and not bench.delta_view.stale,"actual asynchronous button result populates the comparable table")
	check(_canonical(game.sim)==before,"real keyboard preview leaves funds, commands and energy unchanged")
	bench.fields.dispatch.value=.45
	check(bench.delta_view.stale and "已过期" in bench.status.text,"editing a plan marks prior outcomes stale")
	bench.actions.compare.pressed.emit()
	await _wait(bench)
	check(not bench.delta_view.stale,"successful recalculation renews the plan evidence")
	game.sim.step(.05)
	check(bench.delta_view.stale and "运行状态已变化" in bench.delta_view.validity.text,"advancing the real world invalidates completed previews")
	var live_before:=_canonical(game.sim)
	bench.actions.target_controls.pressed.emit()
	check(game.selected_id==1 and not game.planning_panel.visible,"actual-control action opens the same object inspector")
	check(_canonical(game.sim)==live_before,"opening actual controls does not apply the proposed plan")
	game.planning_panel.open(); game.planning_panel.tabs.current_tab=3
	check(bench.preview_maintenance_target("facility",1) and bench._selected("comparison_mode")=="asset","asset inspector can route directly to the selected maintenance comparison")
	check("尚未投运" in bench.asset_state.text,"asset comparison honestly explains unavailable lifecycle rules")
	game.sim.lifecycle.enable(game.sim)
	bench.refresh()
	live_before=_canonical(game.sim)
	bench.actions.compare.pressed.emit()
	await _wait(bench)
	check(bench.delta_view.plan_titles==["继续运行","计划保养","设备更换"] and bench.delta_view.plans[1].maintenance_quote.action=="service","real asset comparison button computes and labels continue, service and replacement")
	check(not bench.operation_options.visible and bench.asset_options.visible,"asset comparison exposes the relevant object and work controls")
	check(_canonical(game.sim)==live_before,"asset comparison button never sends a real maintenance order")
	bench.actions.target_controls.pressed.emit()
	check(game.selected_id==1 and not game.planning_panel.visible,"maintenance navigation returns to the same asset for deliberate real dispatch")
	bench.reset_session()
	check(bench.delta_view.plans.is_empty() and not bench.delta_view.visible,"session reset clears every old table and comparison chart")
	game.queue_free()
	await process_frame
	print("DECISION DELTA: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)
