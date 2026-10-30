extends SceneTree
var checks:=0
var failures:=0
var game: Node
var planning: Node
var economy: Node

func _initialize() -> void: _run.call_deferred()

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+message)

func press(workbench: Node,key: String) -> void:
	check(workbench.actions.has(key),"actual action exists: "+key)
	if workbench.actions.has(key): workbench.actions[key].pressed.emit()

func wait_calculation(workbench: Node) -> void:
	var deadline:=Time.get_ticks_msec()+60000
	while (workbench.calculating or (workbench.has_method("worker_active") and workbench.worker_active())) and Time.get_ticks_msec()<deadline:
		await process_frame
	check(not workbench.calculating and (not workbench.has_method("worker_active") or not workbench.worker_active()),"forecast worker completes within bounded timeout")

func choose(workbench: Node,key: String,value: Variant) -> void:
	var picker: OptionButton=workbench.fields[key]
	for index in picker.item_count:
		if picker.get_item_metadata(index)==value:
			picker.select(index)
			picker.item_selected.emit(index)
			return
	check(false,"choice exists: %s = %s" % [key,str(value)])

func _run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._activate_session()
	for id in ["ac_systems","protection","regional_planning","scada"]: game.sim.evolution.unlocked.append(id)
	game.sim.research_level=2
	game.sim.record_cash_change(820000.0,"test_setup","验收场景资金")
	game.sim.next_storm_at=10000
	game.sim.digital.next_attack_at=10000
	game.sim.connect_buildings(2,6)
	var terminal: Dictionary=game.sim.build("intertie",Vector2i(5,12))
	check(terminal.ok and game.sim.connect_buildings(2,int(terminal.id)).ok,"test grid has a physically connected market terminal")
	game.sim.step(0.05)
	game._sync_world(true)
	game._update_hud()
	game.planning_panel.open()
	planning=game.planning_panel.decision_workbench
	game.planning_panel.tabs.current_tab=3
	check(planning!=null and planning.is_visible_in_tree(),"planning tab contains an actual visible workbench")
	var original: Dictionary=game.sim.snapshot().duplicate(true)
	var initial_frame:=Engine.get_process_frames()
	press(planning,"forecast")
	check(planning.calculating,"forecast action begins asynchronous computation")
	await process_frame
	check(Engine.get_process_frames()>initial_frame and game.sim.snapshot()==original,"UI frames continue while forecast worker leaves source world unchanged")
	await wait_calculation(planning)
	check(planning.chart.rows.size()==24 and "未来24小时" in planning.status.text,"forecast action fills 24-hour chart and summary")
	check(game.sim.snapshot()==original,"forecast click leaves funds, queues, observations, RNG and energy untouched")
	choose(planning,"generator",1)
	planning.fields.dispatch.value=.5
	planning.fields.reserve.value=.7
	choose(planning,"failure_type","line")
	choose(planning,"failure_line",1)
	press(planning,"compare")
	await wait_calculation(planning)
	check("当前：" in planning.details.text and "计划：" in planning.details.text and "退出情景：" in planning.details.text,"three-plan comparison displays actual baseline, operating and contingency outcomes")
	check(planning.chart.rows.size()==24 and game.sim.snapshot()==original,"contingency comparison only changes disposable worlds")
	game.sim.digital.observations.clear()
	game.sim.digital.facility_observations.clear()
	var unknown_world: Dictionary=game.sim.snapshot().duplicate(true)
	press(planning,"forecast")
	await wait_calculation(planning)
	var unknown_rows: Array=planning.chart.rows.duplicate(true)
	game.sim.get_building(1).health=7.0
	game.sim.get_building(1).online=false
	game.sim.get_line(1).fault=true
	game.sim.get_line(1).closed=false
	game.sim._refresh()
	press(planning,"forecast")
	await wait_calculation(planning)
	check(planning.chart.rows==unknown_rows,"forecast does not reveal unobserved machine health or exact hidden line failure")
	check("未知" in planning.status.text or "典型" in planning.status.text or "未核实" in planning.status.text,"unknown-data forecast explains its assumed state")
	check(game.sim.restore_snapshot(unknown_world).ok,"test restores valid original world atomically")
	game.planning_panel.reset_session()
	check(planning.chart.rows.is_empty() and "尚未计算" in planning.status.text,"session reset clears prior forecast chart and headline")
	check(is_equal_approx(float(planning.fields.dispatch.value),1.0) and is_equal_approx(float(planning.fields.reserve.value),.2),"session reset clears operating-plan field drafts")
	game.planning_panel.close()
	game.market_panel.open()
	game.market_panel.tabs.current_tab=4
	economy=game.market_panel.decision_workbench
	check(economy!=null and economy.is_visible_in_tree(),"market tab exposes long-term operations after prerequisite research")
	press(economy,"enable")
	check(game.sim.strategy.enabled,"commissioning button activates actual long-term rules")
	var cash_before: float=game.sim.cash
	economy.fields.loan_amount.value=50000
	economy.fields.loan_hours.value=24
	press(economy,"loan")
	check(is_equal_approx(float(game.sim.cash),cash_before+50000.0) and game.sim.strategy.state.loans.size()==1,"loan click credits cash and creates repayment obligation")
	check(game._number(game.sim.cash) in game.market_panel.funds_label.text,"loan action immediately updates surrounding funds display")
	economy.fields.repayment.value=10000
	press(economy,"repay")
	check(is_equal_approx(float(game.sim.strategy.state.loans[0].principal),40000.0) and is_equal_approx(float(game.sim.cash),cash_before+40000.0),"repayment click reduces both principal and actual cash")
	economy.fields.carbon.value=15
	economy.fields.subsidy.value=5
	economy.fields.cap.value=130
	economy.fields.penalty.value=20
	press(economy,"policy")
	check(game.sim.strategy.state.policy.carbon_price==15 and game.sim.strategy.state.policy.tariff_cap==130,"policy form changes actual scenario parameters")
	var focused: LineEdit=economy.fields.carbon.get_line_edit()
	focused.grab_focus()
	await process_frame
	var focused_time: float=game.sim.elapsed_hours
	var typed:=InputEventKey.new()
	typed.keycode=KEY_M
	typed.unicode=109
	typed.pressed=true
	root.push_input(typed,true)
	typed=typed.duplicate()
	typed.pressed=false
	root.push_input(typed,true)
	await process_frame
	check(game.market_panel.visible and game._modal_open() and is_equal_approx(float(game.sim.elapsed_hours),focused_time),"typing a centre hotkey in advanced numeric input stays within paused modal")
	focused.release_focus()
	economy.fields.schedule.text="4,4,4"
	press(economy,"day_ahead")
	check(game.sim.strategy.state.day_ahead.size()==3,"day-ahead text form submits three hourly commitments")
	var committed: Array=game.sim.strategy.state.day_ahead.duplicate(true)
	press(economy,"day_ahead")
	check(game.sim.strategy.state.day_ahead==committed and "!" in economy.message.text,"overlapping commitments are refused visibly without replacing accepted schedule")
	choose(economy,"project_kind","gas")
	economy.fields.x.value=11
	economy.fields.y.value=11
	press(economy,"project")
	check(game.sim.strategy.cell_reserved(Vector2i(11,11)) and game.sim.building_at(Vector2i(11,11)).is_empty(),"project form reserves location before delivering capacity")
	check(not game.sim.build("home",Vector2i(11,11)).ok,"ordinary map construction cannot overwrite a reserved project")
	game.sim.step(1.1)
	game.market_panel.refresh()
	check(game.sim.building_at(Vector2i(11,11)).get("kind","")=="gas","project actually commissions generator after work duration")
	check(float(game.sim.strategy.state.interest_paid)>0 and float(game.sim.strategy.state.forward_cost)>0,"actual advance settles interest and day-ahead costs")
	choose(economy,"project_kind","battery")
	economy.fields.x.value=12
	economy.fields.y.value=12
	press(economy,"project")
	var paid: float=game.sim.cash
	press(economy,"cancel_project")
	check(not game.sim.strategy.cell_reserved(Vector2i(12,12)) and float(game.sim.cash)>paid,"cancel button releases site and refunds unbuilt work")
	choose(economy,"reserve_target",9)
	economy.fields.reserve_mw.value=1
	economy.fields.reserve_hours.value=1
	press(economy,"reserve")
	check(game.sim.strategy.state.reserves.size()==1,"reserve action creates a real capacity commitment")
	choose(economy,"auction","auction")
	economy.fields.markup.value=1.1
	press(economy,"auction_apply")
	check(game.sim.strategy.state.market_mode=="auction" and is_equal_approx(float(game.sim.strategy.state.bid_markup),1.1),"market rule form enables simplified uniform clearing")
	economy.fields.carbon.value=25
	economy.fields.markup.value=1.3
	game.market_panel.refresh()
	check(game._has_unsent_drafts() and "未应用" in economy.draft_labels.policy.text,"advanced policy edits join shared draft warnings")
	press(economy,"reset_policy")
	check(economy.fields.carbon.value==15 and is_equal_approx(float(economy.fields.markup.value),1.3),"resetting policy only resets policy and retains separate auction draft")
	press(economy,"reset_auction")
	check(is_equal_approx(float(economy.fields.markup.value),1.1) and game.sim.strategy.state.policy.carbon_price==15,"local draft resets never apply economic changes")
	choose(economy,"goal","reliable")
	press(economy,"goal_apply")
	check(game.sim.strategy.state.goal=="reliable","long-term target action adopts actual continuous operating objective")
	economy.fields.hazard_hours.value=.25
	choose(economy,"hazard","heatwave")
	press(economy,"hazard_start")
	check(game.sim.strategy.state.hazards.size()==1,"regional event form starts actual correlated event")
	game.sim.step(.5)
	game.market_panel.refresh()
	check(game.sim.strategy.state.hazards.is_empty(),"regional event expires only after actual simulation time")
	game.sim.get_line(4).closed=false
	game.sim.step(.15)
	game.sim.get_line(4).closed=true
	game.sim.step(.15)
	game.market_panel.refresh()
	check(not economy.recovery_chart.event.is_empty() and not economy.recovery_chart.event.curve.is_empty(),"actual interruption and restoration populate the recovery curve")
	original=game.sim.snapshot().duplicate(true)
	for _i in 4:
		economy.refresh()
		game.market_panel.refresh()
	check(game.sim.snapshot()==original,"economy report refresh never repeats bills, interest or project work")
	check("现金分类" in economy.details.text and "日前" in economy.details.text and "贷款本金" in economy.status.text,"result view explains actual cash categories, financial obligations and dispatch costs")
	economy.fields.loan_amount.value=77000
	economy.fields.schedule.text="9,9"
	economy.fields.carbon.value=55
	planning.fields.dispatch.value=.35
	game.market_panel.close()
	game.planning_panel.open()
	press(planning,"forecast")
	check(planning.calculating,"test starts a pending forecast before session replacement")
	game._begin_free_sandbox(true)
	await wait_calculation(planning)
	check(planning.chart.rows.is_empty() and "尚未计算" in planning.status.text,"real new-session transition clears previous simulation results")
	check("未来24小时" not in planning.status.text and "预测已更新" not in planning.message.text,"late worker completion cannot publish results from abandoned session")
	check(planning.fields.dispatch.value==1 and economy.fields.loan_amount.value==50000 and economy.fields.carbon.value==0,"new session clears advanced editable fields")
	check(economy.fields.schedule.text!="9,9","new session clears unsubmitted forward schedule")
	game.queue_free()
	await process_frame
	print("DECISION WORKBENCH: %d checks; %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
