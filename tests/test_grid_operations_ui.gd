extends SceneTree
var checks:=0
var failures:=0
var game: Node
var desk: Node
var panel: Node

func _initialize() -> void: _run.call_deferred()

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error("FAIL: "+message)

func find_button(parent: Node,caption: String) -> Button:
	if parent is Button and caption in parent.text: return parent
	for child in parent.get_children():
		var found:=find_button(child,caption)
		if found!=null: return found
	return null

func press(caption: String) -> void:
	var button:=find_button(panel,caption)
	check(button!=null,"real control exists: "+caption)
	if button!=null: button.pressed.emit()

func choose(picker: OptionButton,id: int) -> void:
	for index in picker.item_count:
		if picker.get_item_id(index)==id:
			picker.select(index)
			picker.item_selected.emit(index)
			return
	check(false,"picker contains target %d" % id)

func select_list(list: ItemList,ids: Array) -> void:
	list.deselect_all()
	for index in list.item_count:
		if int(list.get_item_metadata(index)) in ids: list.select(index,false)

func _run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._activate_session()
	desk=game.digital_panel
	desk.open()
	check(desk.tabs.get_tab_count()==4 and desk.grid_operations==null,"advanced tab waits for regional planning research")
	game.sim.evolution.unlocked.append("regional_planning")
	game.sim.evolution.unlocked.append("scada")
	game.sim.research_level=2
	game.sim.cash=1000000.0
	desk.refresh()
	panel=desk.grid_operations
	check(panel!=null and desk.tabs.get_tab_count()==5,"regional planning exposes real operations tab")
	if panel==null:
		_finish()
		return
	desk.tabs.current_tab=4
	var baseline: Dictionary=game.sim.snapshot().duplicate(true)
	for _i in 3:
		panel.refresh()
		desk.refresh(true)
	check(game.sim.snapshot()==baseline,"opening and refreshing advanced controls do not sample or settle simulation")
	press("投运资产风险管理")
	press("投运输配电管理")
	press("投运用户侧协调")
	check(game.sim.lifecycle.enabled and game.sim.engineering.enabled and game.sim.customers.enabled,"commissioning buttons activate all real modules")
	check(panel.commissioning.lifecycle.disabled and panel.commissioning.engineering.disabled,"already commissioned systems cannot charge or restart")
	panel.section.select(1)
	panel.section.item_selected.emit(1)
	choose(panel.line_picker,1)
	panel.tier.select(1)
	panel.tier.item_selected.emit(1)
	panel.delay.value=1.5
	panel.station_capacity.value=80
	panel.zone.text="东区保护"
	panel.zone.text_changed.emit("东区保护")
	press("应用线路等级与保护")
	check(game.sim.engineering.line_settings["1"].tier=="transmission" and is_equal_approx(float(game.sim.engineering.line_settings["1"].delay),1.5),"line controls apply tier and protection timing")
	check(panel.station_capacity.value==80 and panel.zone.text=="东区保护","applying a line preserves a different station draft")
	press("应用变电容量与保护分区")
	check(game.sim.engineering.substation_settings["2"].capacity==80 and game.sim.engineering.substation_settings["2"].zone=="东区保护","station controls apply actual capacity and named zone")
	panel.section.select(2)
	panel.section.item_selected.emit(2)
	choose(panel.customer_picker,3)
	for key in ["metered","consent","smart","grid_forming"]: panel.fields[key].button_pressed=true
	for spec in [["pv_mw",2.0],["battery_mwh",5.0],["battery_mw",2.0],["ev_mw",2.0],["ev_target_mwh",4.0]]: panel.fields[spec[0]].value=float(spec[1])
	choose(panel.customer_picker,4)
	panel.fields.pv_mw.value=1.0
	choose(panel.customer_picker,3)
	check(panel.fields.pv_mw.value==2 and panel.fields.metered.button_pressed,"customer drafts survive switching targets")
	press("应用街区能源方案")
	check(game.sim.customers.devices.has("3") and game.sim.customers.devices["3"].pv_mw==2 and game.sim.customers.devices["3"].ev_target_mwh==4,"customer form creates actual metering, PV, storage and charging")
	choose(panel.customer_picker,4)
	check(panel.fields.pv_mw.value==1.0 and not game.sim.customers.devices.has("4"),"applying one street preserves another street's unapplied draft")
	choose(panel.customer_picker,3)
	game.sim.step(0.05)
	desk.refresh()
	press("签发所选街区需求响应")
	check(float(game.sim.customers.devices["3"].response_remaining)>0,"demand response button submits real eligible response")
	panel.section.select(0)
	panel.section.item_selected.emit(0)
	choose(panel.asset_picker,3)
	game.sim.get_building(3).health=70.0
	var spares_before: int=game.sim.lifecycle.spares
	press("采购关键备件")
	check(game.sim.lifecycle.spares==spares_before+1,"spare button changes real stock and journal")
	press("现场巡检")
	check(game.sim.lifecycle.active_jobs()==1,"maintenance control starts actual field job")
	game.sim.step(0.8)
	desk.refresh()
	check(game.sim.lifecycle.jobs.is_empty() and float(game.sim.get_building(3).inspected_at)>=0,"maintenance job completes through real time advancement")
	check("70" in panel.asset_info.text,"inspection result becomes visible in operations view")
	panel.section.select(3)
	panel.section.item_selected.emit(3)
	panel.microgrid_name.text="医院邻里微网"
	select_list(panel.member_list,[1,2,3])
	select_list(panel.critical_list,[3])
	press("登记所选微电网分区")
	check(game.sim.customers.microgrids.size()==1 and game.sim.customers.microgrids[0].critical_ids==[3],"multi-select membership form registers real critical-load partition")
	press("安排微电网离网")
	check(not game.sim.customers.microgrids[0].pending.is_empty(),"islanding schedules an actual delayed boundary operation")
	game.sim.step(1.0)
	desk.refresh()
	check(game.sim.customers.microgrids[0].islanded and int(game.sim.customers.microgrids[0].stage)==2,"actual source restores island in stages")
	press("安排微电网重联")
	game.sim.step(0.5)
	desk.refresh()
	check(not game.sim.customers.microgrids[0].islanded,"reconnect button actually restores boundary connections")
	check(find_button(panel,"更新任务优先级")!=null and find_button(panel,"取消未出发任务")!=null and find_button(panel,"故障隔离演练")!=null,"priority, cancel and selective-isolation controls are reachable")
	choose(panel.customer_picker,4)
	panel.fields.ev_target_mwh.value=7
	check(game._has_unsent_drafts(),"advanced drafts participate in normal session-switch confirmation")
	baseline=game.sim.snapshot().duplicate(true)
	for _i in 3: panel.refresh()
	check(game.sim.snapshot()==baseline and panel.fields.ev_target_mwh.value==7,"routine report refresh retains drafts and never changes main-world state")
	desk.reset_session()
	desk.refresh()
	check(not desk.drafts.dirty("operations_customer_4") and panel.fields.ev_target_mwh.value==0,"session reset clears advanced drafts")
	game.sim.start_campaign(1)
	desk.refresh()
	check(desk.tabs.is_tab_hidden(desk.grid_operations_tab.get_index()),"historical campaign hides advanced rules tab")
	_finish()

func _finish() -> void:
	game.queue_free()
	await process_frame
	print("GRID OPERATIONS UI: %d checks; %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
