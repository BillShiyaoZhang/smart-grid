extends VBoxContainer
const UI=preload("res://scripts/ui/ui_kit.gd")
const Chart=preload("res://scripts/ui/forecast_chart.gd")
const RecoveryChart=preload("res://scripts/ui/recovery_chart.gd")
const DecisionDelta=preload("res://scripts/ui/decision_delta.gd")
const CASH_LABELS={"opening_adjustment":"期初调整","operations":"运营净额","investment":"设施与线路投资","construction":"工程预付款","research":"研发","maintenance":"检修抢修","disposal":"拆除回收","loan":"贷款到账","repayment":"偿还本金","demand_response":"需求响应补偿","customers":"街区能源改造","engineering":"输配电改造","field":"现场操作","digital":"通信与数字化","security":"安全恢复","reward":"任务奖励","spares":"备件采购","reserve_penalty":"备用违约","project_refund":"工程退款"}
const GOAL_LABELS={"":"尚未选择","reliable":"可靠供电","affordable":"可负担电价","sustainable":"清洁供电","resilient":"灾后韧性","solvent":"财务稳健"}
var game: Node
var mode:="planning"
var fields: Dictionary={}
var actions: Dictionary={}
var message: Label
var status: Label
var details: Label
var chart: Control
var recovery_chart: Control
var delta_view: Control
var _result_stale:=false
var operation_options: Control
var asset_options: Control
var asset_state: Label
var _comparison_titles: Array=["当前","计划","退出情景"]
var _signature:=""
var _world: RefCounted
var calculating:=false
var _worker: Thread
var _revision:=0
var _calculation_revision:=0
var _calculation_world: RefCounted
var _comparison:=false
var _defaults: Dictionary={}
var _baselines: Dictionary={}
var draft_labels: Dictionary={}
const DRAFT_GROUPS={"policy":["carbon","subsidy","cap","reliability","penalty"],"auction":["auction","markup"],"schedule":["schedule"]}

func setup(owner_game: Node, section: String) -> void:
	game=owner_game
	mode=section
	add_theme_constant_override("separation",12)
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	message=_label(self,"参数编辑为草案；只有点击操作或推进时间才会生效。")
	if mode=="planning": _build_planning()
	else: _build_economy()
	for key in fields: _defaults[key]=_value(key)
	_load_effective()
	for section_name in DRAFT_GROUPS: _baselines[section_name]=_read_group(section_name)
	refresh()

func _label(parent: Node, text: String) -> Label:
	var l:=UI.label(parent,text,14)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return l
func _section(title: String) -> VBoxContainer:
	var panel:=PanelContainer.new()
	add_child(panel)
	var box:=UI.column(panel,9)
	_label(box,title).add_theme_color_override("font_color",UI.TEAL)
	return box
func _spin(parent: Node, key: String, caption: String, low: float, high: float, value: float, step: float=1) -> SpinBox:
	var row:=HFlowContainer.new()
	parent.add_child(row)
	_label(row,caption)
	var input:=SpinBox.new()
	input.min_value=low; input.max_value=high; input.step=step; input.value=value
	input.custom_minimum_size=Vector2(120,36)
	row.add_child(input)
	fields[key]=input
	return input
func _pick(parent: Node, key: String, caption: String, items: Array=[]) -> OptionButton:
	_label(parent,caption)
	var input:=OptionButton.new()
	input.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.y=36
	parent.add_child(input)
	for item in items:
		input.add_item(str(item[1]))
		input.set_item_metadata(input.item_count-1,item[0])
	fields[key]=input
	return input
func _line(parent: Node, key: String, caption: String, text: String) -> LineEdit:
	_label(parent,caption)
	var input:=LineEdit.new()
	input.text=text
	parent.add_child(input)
	fields[key]=input
	return input
func _button(parent: Node, key: String, caption: String, action: Callable) -> void:
	actions[key]=UI.button(parent,caption,action)
func _selected(key: String) -> Variant:
	var picker: OptionButton=fields[key]
	return picker.get_selected_metadata() if picker.selected>=0 else -1
func _perform(result: Dictionary, section_name: String="") -> void:
	message.text=("✓ " if result.get("ok",false) else "! ")+str(result.get("message","操作完成"))
	game._apply(result)
	if result.get("ok",false):
		if not section_name.is_empty(): _baselines[section_name]=_read_group(section_name)
		game.sim._refresh()
		game._sync_world(true)
		game._update_hud()
		game._update_inspector()
	refresh()

func _build_planning() -> void:
	var box:=_section("提前24小时 · 负荷、风光、备用与储能")
	_label(box,"预测使用已知观测和明确假设。可疑或未知设备采用典型状态；故障演练只在推演副本中发生。")
	chart=Chart.new(); box.add_child(chart)
	status=_label(box,"尚未计算。")
	_button(box,"forecast","计算24小时供需预测",_forecast)
	var plan:=_section("运行方案比较与单故障检查")
	_pick(plan,"comparison_mode","比较内容",[["operation","运行方案与单故障"],["asset","继续运行 / 检修 / 更换"]])
	operation_options=UI.column(plan,8)
	_pick(operation_options,"generator","计划调整的机组")
	_spin(operation_options,"dispatch","计划出力比例",0,1,1,.05)
	_spin(operation_options,"reserve","储能备用比例",0,.9,.2,.05)
	_pick(operation_options,"imports","计划外购",[[true,"允许外购"],[false,"禁止外购"]])
	_pick(operation_options,"failure_type","假设退出",[["none","无额外退出"],["line","线路退出"],["facility","设施退出"]])
	_pick(operation_options,"failure_line","故障演练线路")
	_pick(operation_options,"failure_facility","故障演练设施")
	asset_options=UI.column(plan,8)
	asset_state=_label(asset_options,"")
	_pick(asset_options,"maintenance_target_type","检修对象类别",[["facility","设施"],["line","电力线路"]])
	_pick(asset_options,"maintenance_facility","设施对象（设施类别时使用）")
	_pick(asset_options,"maintenance_line","线路对象（线路类别时使用）")
	_pick(asset_options,"maintenance_action","与继续运行、更换比较的处置",[["service","计划保养"],["overhaul","部件大修"],["inspect","现场巡检"]])
	_label(asset_options,"比较使用副本内真实工单：计入费用、备件、队伍等待、路程和作业停运；不计算虚构净现值，也不保证未来故障减少。")
	_button(plan,"compare","比较：当前方案 / 所选运行方案 / 单故障情景",_compare)
	_button(plan,"target_controls","查看机组实际控制（另行提交）",_open_actual_controls)
	fields.comparison_mode.item_selected.connect(func(_index: int): _adapt_comparison_controls())
	details=_label(plan,"比较失供电量、现金变化、最大负载和最低电压。")
	delta_view=DecisionDelta.new()
	plan.add_child(delta_view)
	delta_view.hide()
	for input in fields.values():
		if input is SpinBox: input.value_changed.connect(func(_value: float): _plan_edited())
		elif input is OptionButton: input.item_selected.connect(func(_index: int): _plan_edited())
	_adapt_comparison_controls()

func _adapt_comparison_controls() -> void:
	if operation_options==null: return
	var asset_mode: bool=_selected("comparison_mode")=="asset"
	operation_options.visible=not asset_mode
	asset_options.visible=asset_mode
	if asset_state!=null:
		asset_state.text="资产风险管理已投运；计算后列出副本工单报价。" if bool(game.sim.lifecycle.enabled) else "资产风险管理尚未投运，当前不能提交检修推演；请先在运维中心投运。"
	if actions.has("compare"):
		actions.compare.text="比较：继续运行 / 所选检修 / 设备更换" if asset_mode else "比较：当前方案 / 所选运行方案 / 单故障情景"
	if actions.has("target_controls"):
		actions.target_controls.text="查看设备实际操作（另行派工）" if asset_mode else "查看机组实际控制（另行提交）"

func _open_actual_controls() -> void:
	var asset_mode: bool=_selected("comparison_mode")=="asset"
	var target_type:=str(_selected("maintenance_target_type")) if asset_mode else "facility"
	var id:=int(_selected("maintenance_line" if target_type=="line" else "maintenance_facility")) if asset_mode else int(_selected("generator"))
	if id>0: game.focus_target(target_type,id)

func _plan_edited() -> void:
	_mark_result_stale("方案草案已改动")

func _mark_result_stale(reason: String) -> void:
	if mode!="planning" or chart==null or chart.rows.is_empty(): return
	if not _result_stale: status.text="已过期 · %s，请重新计算。\n%s" % [reason,status.text]
	_result_stale=true
	if delta_view!=null: delta_view.set_stale(true,reason)

func preview_target(kind: String,id: int) -> bool:
	if mode!="planning" or calculating: return false
	refresh()
	_write("comparison_mode","operation")
	if kind in ["line","power"]:
		if game.sim.get_line(id).is_empty(): return false
		_write("failure_type","line"); _write("failure_line",id)
	else:
		var building: Dictionary=game.sim.get_building(id)
		if building.is_empty(): return false
		if game.sim.evolution.is_generator(str(building.kind)):
			_write("generator",id)
			_write("dispatch",float(building.get("dispatch",1.0)))
		else:
			_write("failure_type","facility"); _write("failure_facility",id)
	_plan_edited()
	_adapt_comparison_controls()
	message.text="已带入所选对象。编辑方案后比较；实际运行设置仍需另行提交。"
	return true

func preview_maintenance_target(kind: String,id: int) -> bool:
	if mode!="planning" or calculating: return false
	var target_type: String="line" if kind in ["line","power"] else "facility"
	var target: Dictionary=game.sim.get_line(id) if target_type=="line" else game.sim.get_building(id)
	if target.is_empty(): return false
	refresh()
	_write("comparison_mode","asset")
	_write("maintenance_target_type",target_type)
	_write("maintenance_line" if target_type=="line" else "maintenance_facility",id)
	_plan_edited(); _adapt_comparison_controls()
	message.text="已带入设备。比较继续运行、所选检修与更换；实际派工需要另行提交。"
	return true

func _forecast() -> void:
	_start_calculation([])

func _display_forecast(result: Dictionary) -> void:
	if not result.ok: _perform(result); return
	_result_stale=false
	if delta_view!=null: delta_view.set_results([])
	chart.set_rows(result.rows)
	status.text="未来24小时失供 %.1f MWh · 现金变化 ¥%.0f · 最大负载 %.0f%% · 信息可信度 %s\n%s" % [result.unserved_mwh,result.net_cash,float(result.max_loading)*100,result.confidence,"\n".join(result.assumptions)]
	message.text="预测已更新；主世界未推进。"
func _compare() -> void:
	if _selected("comparison_mode")=="asset":
		var target_type:=str(_selected("maintenance_target_type"))
		var target_id:=int(_selected("maintenance_line" if target_type=="line" else "maintenance_facility"))
		var action:=str(_selected("maintenance_action"))
		_comparison_titles=["继续运行",str(game.sim.lifecycle.ACTIONS[action].name),"设备更换"]
		_start_calculation([{}, {"maintenance":{"target_type":target_type,"target_id":target_id,"action":action}}, {"maintenance":{"target_type":target_type,"target_id":target_id,"action":"replace"}}])
		return
	_comparison_titles=["当前","计划","退出情景"]
	var selected:={"reserve":fields.reserve.value,"imports":bool(_selected("imports"))}
	if int(_selected("generator"))>0:
		selected.generator_id=int(_selected("generator")); selected.dispatch=fields.dispatch.value
	var failure: Dictionary=selected.duplicate(true)
	if _selected("failure_type")=="line": failure.outage_line=int(_selected("failure_line"))
	if _selected("failure_type")=="facility": failure.outage_facility=int(_selected("failure_facility"))
	_start_calculation([{},selected,failure])

func _display_comparison(result: Dictionary) -> void:
	if not result.ok: _perform(result); return
	_result_stale=false
	var lines: Array[String]=[]
	for i in result.plans.size():
		var p: Dictionary=result.plans[i]
		lines.append("%s：失供 %.1f MWh · 现金 ¥%+.0f · 负载 %.0f%% · 电压 %.3f pu" % [_comparison_titles[i],p.unserved_mwh,p.net_cash,float(p.max_loading)*100,p.min_voltage])
	details.text="\n".join(lines)
	chart.set_rows(result.plans[0].rows)
	delta_view.set_results(result.plans,_comparison_titles)
	var assumptions: Array=[]
	for plan in result.plans:
		for assumption in plan.assumptions:
			if assumption not in assumptions: assumptions.append(assumption)
	status.text="未来24小时三方案 · 相同起点与时段 · %s\n%s" % [" / ".join(_comparison_titles),"\n".join(assumptions)]
	message.text="三方案已计算；结果为所列假设下的参考。"

func _watch_world() -> void:
	if _world==game.sim: return
	if _world!=null and _world.changed.is_connected(_world_changed): _world.changed.disconnect(_world_changed)
	_world=game.sim
	_world.changed.connect(_world_changed)
	_revision+=1

func _world_changed() -> void:
	_revision+=1
	_mark_result_stale("运行状态已变化")

func _calculation_controls(busy: bool) -> void:
	for key in ["forecast","compare"]:
		if actions.has(key): actions[key].disabled=busy
	if mode!="planning": return
	for input in fields.values():
		if input is SpinBox or input is LineEdit: input.editable=not busy
		if input is OptionButton: input.disabled=busy

func _start_calculation(plans: Array) -> void:
	if calculating: return
	_watch_world()
	# Capture immutable evidence on the UI thread. The worker owns its own
	# RefCounted world and never reads live UI or the live simulation.
	var source: RefCounted=game.sim.get_script().new()
	var restored: Dictionary=source.restore_snapshot(game.sim.snapshot())
	if not restored.ok: _perform(restored); return
	var captured_plans: Array=plans.duplicate(true)
	_comparison=not plans.is_empty()
	_calculation_world=game.sim
	_calculation_revision=_revision
	calculating=true
	_mark_result_stale("正在重新计算")
	_calculation_controls(true)
	message.text="后台推演中；可返回电网继续操作，当前世界未被推进。"
	_worker=Thread.new()
	var error:=_worker.start(func() -> Dictionary:
		return source.compare_operating_plans(captured_plans) if not captured_plans.is_empty() else source.planning_forecast()
	)
	if error!=OK:
		_worker=null
		calculating=false
		_calculation_controls(false)
		message.text="无法启动推演，请重试。"
	set_process(true)

func _process(_delta: float) -> void:
	if _worker==null or _worker.is_alive(): return
	var output: Variant=_worker.wait_to_finish()
	_worker=null
	calculating=false
	_calculation_controls(false)
	set_process(false)
	if not output is Dictionary:
		message.text="推演未完成，请重新计算。"
		return
	if _calculation_world!=game.sim or _calculation_revision!=_revision:
		message.text="运行状态或进度已变化，旧推演结果已丢弃；请按当前状态重新计算。"
		return
	if _comparison: _display_comparison(output)
	else: _display_forecast(output)

func _exit_tree() -> void:
	# Join the isolated worker before its owning UI is released.
	if _worker!=null:
		_worker.wait_to_finish()
		_worker=null

func _build_economy() -> void:
	var report:=_section("经营结果与停电复盘")
	status=_label(report,"")
	details=_label(report,"")
	_pick(report,"outage_id","查看停电恢复曲线")
	fields.outage_id.item_selected.connect(func(_i: int): _signature=""; refresh())
	recovery_chart=RecoveryChart.new()
	report.add_child(recovery_chart)
	var setup_box:=_section("长期经营投运")
	_label(setup_box,"研究区域负荷规划后投运。大型工程、日前实物购电、融资及情景规则按需采用。")
	_button(setup_box,"enable","投运长期投资与市场经营",func(): _perform(game.sim.commission_expansion("strategy")))
	var build_box:=_section("提前建设 · 工程费用包含场地准备，地块按工期预留")
	_pick(build_box,"project_kind","设施类型")
	_spin(build_box,"x","地块 X",1,46,11)
	_spin(build_box,"y","地块 Y",1,46,11)
	_button(build_box,"project","提交设施工程",func(): _perform(game.sim.strategy.start_project(game.sim,str(_selected("project_kind")),Vector2i(int(fields.x.value),int(fields.y.value)))))
	_pick(build_box,"line_a","骨干线路起点")
	_pick(build_box,"line_b","骨干线路终点")
	_button(build_box,"line_project","提交线路工程",func(): _perform(game.sim.strategy.start_line_project(game.sim,int(_selected("line_a")),int(_selected("line_b")))))
	_pick(build_box,"project_id","在建工程")
	_button(build_box,"cancel_project","取消所选工程（按已完成进度结算退款）",func(): _perform(game.sim.strategy.cancel_project(game.sim,int(_selected("project_id")))))
	var finance:=_section("融资 · 日利率0.5%，逾期翻倍，可提前偿还")
	_spin(finance,"loan_amount","贷款本金 ¥",1000,500000,50000,1000)
	_spin(finance,"loan_hours","期限（游戏小时）",24,720,72)
	_button(finance,"loan","申请工程贷款",func(): _perform(game.sim.strategy.take_loan(game.sim,fields.loan_amount.value,fields.loan_hours.value)))
	_pick(finance,"loan_id","待还贷款")
	_spin(finance,"repayment","偿还本金 ¥",1,1000000,10000,1)
	_button(finance,"repay","偿还所选贷款",func(): _perform(game.sim.strategy.repay_loan(game.sim,int(_selected("loan_id")),fields.repayment.value)))
	var trade:=_section("日前承诺与备用服务")
	_line(trade,"schedule","下一整小时起逐小时 MW，用英文逗号分隔（1—24项）","4,4,4,4,4,4,4,4,4,4,4,4")
	_label(trade,"提交后不能覆盖：约定电量按锁价付费，未交付仍付款；实际偏差另收现货价5%的履约费。")
	_button(trade,"day_ahead","提交逐小时实物购电承诺",_day_ahead)
	_pick(trade,"reserve_target","备用提供方")
	_spin(trade,"reserve_mw","保留备用 MW",.1,1000,2,.1)
	_spin(trade,"reserve_hours","备用时长 h",.25,24,4,.25)
	_button(trade,"reserve","承诺备用（保留功率，按实际履约结算）",func(): _perform(game.sim.strategy.reserve(game.sim,int(_selected("reserve_target")),fields.reserve_mw.value,fields.reserve_hours.value)))
	_pick(trade,"auction","区域市场规则",[["reference","参考价格"],["auction","区域供应报价统一出清"]])
	_spin(trade,"markup","区域供应报价系数",.5,2,1,.05)
	_button(trade,"auction_apply","应用市场情景",func(): _perform(game.sim.strategy.configure_market(game.sim,str(_selected("auction")),fields.markup.value),"auction"))
	_draft_controls(trade,"auction")
	_draft_controls(trade,"schedule")
	var policy:=_section("情景规则 · 政策与长期经营目标")
	_spin(policy,"carbon","碳价 ¥/吨",0,1000,0,5)
	_spin(policy,"subsidy","可再生生产补贴 ¥/MWh",0,500,0,5)
	_spin(policy,"cap","零售价格上限 ¥/MWh",20,500,500,5)
	_spin(policy,"reliability","供电目标比例",.5,1,.98,.01)
	_spin(policy,"penalty","不足供电附加罚款 ¥/MWh",0,500,0,5)
	_button(policy,"policy","应用情景政策",func(): _perform(game.sim.strategy.configure_policy(game.sim,{"carbon_price":fields.carbon.value,"production_subsidy":fields.subsidy.value,"tariff_cap":fields.cap.value,"reliability_target":fields.reliability.value,"reliability_penalty":fields.penalty.value}),"policy"))
	_draft_controls(policy,"policy")
	_pick(policy,"goal","连续24小时目标",[["reliable","可靠供电"],["affordable","可负担电价"],["sustainable","清洁供电"],["resilient","灾后韧性"],["solvent","财务稳健"]])
	_button(policy,"goal_apply","采用长期目标",func(): _perform(game.sim.strategy.set_goal(game.sim,str(_selected("goal")))))
	var hazards:=_section("区域韧性演练 · 将改变真实运行状态")
	_pick(hazards,"hazard","事件",[["heatwave","热浪"],["flood","洪水"],["fuel","燃料供应中断"]])
	_spin(hazards,"hazard_x","中心 X",0,47,8)
	_spin(hazards,"hazard_y","中心 Y",0,47,8)
	_spin(hazards,"radius","影响半径",1,48,6)
	_spin(hazards,"hazard_hours","持续小时",.25,48,4,.25)
	_button(hazards,"hazard_start","开始所选区域演练",func(): _perform(game.sim.strategy.trigger_hazard(game.sim,str(_selected("hazard")),Vector2i(int(fields.hazard_x.value),int(fields.hazard_y.value)),fields.radius.value,fields.hazard_hours.value)))

func _day_ahead() -> void:
	var schedule: Array=[]
	for raw in fields.schedule.text.split(","):
		if not raw.strip_edges().is_valid_float(): _perform({"ok":false,"message":"请输入用英文逗号分隔的逐小时MW。"}); return
		schedule.append(float(raw))
	_perform(game.sim.strategy.submit_day_ahead(game.sim,schedule),"schedule")

func _value(key: String) -> Variant:
	var input: Control=fields[key]
	if input is SpinBox: return input.value
	if input is OptionButton: return _selected(key)
	return input.text
func _write(key: String, value: Variant) -> void:
	var input: Control=fields[key]
	if input is SpinBox: input.value=float(value)
	elif input is OptionButton:
		for i in input.item_count:
			if typeof(input.get_item_metadata(i))==typeof(value) and input.get_item_metadata(i)==value: input.select(i); return
		if input.item_count>0: input.select(0)
	else: input.text=str(value)
func _read_group(section_name: String) -> Dictionary:
	var values: Dictionary={}
	for key in DRAFT_GROUPS[section_name]:
		if fields.has(key): values[key]=_value(key)
	return values
func _load_effective() -> void:
	if mode!="economy": return
	var policy: Dictionary=game.sim.strategy.state.policy
	for pair in [["carbon","carbon_price"],["subsidy","production_subsidy"],["cap","tariff_cap"],["reliability","reliability_target"],["penalty","reliability_penalty"]]: _write(pair[0],policy[pair[1]])
	_write("auction",game.sim.strategy.state.market_mode)
	_write("markup",game.sim.strategy.state.bid_markup)
func _draft_controls(parent: Node, section_name: String) -> void:
	draft_labels[section_name]=_label(parent,"")
	_button(parent,"reset_"+section_name,"重置本区草案",func():
		for key in _baselines.get(section_name,{}): _write(key,_baselines[section_name][key])
		message.text="本区草案已重置；其他修改保留。"
	)
func capture_drafts(store: RefCounted) -> void:
	if mode!="economy": return
	for section_name in DRAFT_GROUPS:
		if not _baselines.has(section_name): continue
		store.retain("long_"+section_name,_baselines[section_name],_read_group(section_name))
		draft_labels[section_name].text="未应用草案" if store.dirty("long_"+section_name) else "✓ 本区没有未提交修改"

func _fill(key: String, items: Array) -> void:
	if not fields.has(key): return
	var input: OptionButton=fields[key]
	var selected: Variant=_selected(key)
	var signature:=str(items)
	if input.get_meta("items","")==signature: return
	input.set_meta("items",signature)
	input.clear()
	for item in items:
		input.add_item(str(item[1])); input.set_item_metadata(input.item_count-1,item[0])
		if typeof(item[0])==typeof(selected) and item[0]==selected: input.select(input.item_count-1)

func reset_session() -> void:
	_signature=""
	if game!=null: _watch_world()
	_revision+=1
	for key in _defaults: _write(key,_defaults[key])
	_load_effective()
	for section_name in DRAFT_GROUPS: _baselines[section_name]=_read_group(section_name)
	if chart!=null: chart.set_rows([])
	if delta_view!=null: delta_view.set_results([])
	_result_stale=false
	if mode=="planning":
		status.text="尚未计算。"; details.text="选择运行方案后计算。"
	refresh()

func refresh() -> void:
	if game==null: return
	if _world!=game.sim:
		_watch_world()
		_signature=""
		for key in _defaults: _write(key,_defaults[key])
		_load_effective()
		for section_name in DRAFT_GROUPS: _baselines[section_name]=_read_group(section_name)
		if chart!=null: chart.set_rows([])
		if delta_view!=null: delta_view.set_results([])
		_result_stale=false
		if mode=="planning": status.text="尚未计算。"; details.text="选择运行方案后计算。"
		message.text="参数编辑为草案；点击操作才生效。"
	var facilities: Array=[]
	var generators: Array=[]
	var providers: Array=[]
	var circuits: Array=[]
	for b in game.sim.buildings:
		var item:=[int(b.id),"#%d %s" % [b.id,b.name]]
		facilities.append(item)
		if game.sim.evolution.is_generator(str(b.kind)): generators.append(item)
		if game.sim.evolution.is_generator(str(b.kind)) or game.sim.evolution.is_storage(str(b.kind)): providers.append(item)
	for l in game.sim.lines: circuits.append([int(l.id),"线路 #%d · %d → %d" % [l.id,l.a,l.b]])
	for key in ["line_a","line_b","failure_facility","maintenance_facility"]: _fill(key,facilities)
	_fill("generator",generators); _fill("reserve_target",providers); _fill("failure_line",circuits); _fill("maintenance_line",circuits)
	if mode=="planning":
		_adapt_comparison_controls()
		var asset_mode: bool=_selected("comparison_mode")=="asset"
		actions.target_controls.disabled=int(_selected("maintenance_line" if _selected("maintenance_target_type")=="line" else "maintenance_facility"))<=0 if asset_mode else int(_selected("generator"))<=0
		return
	var kinds: Array=[]
	for kind in game.sim.catalog:
		if game.sim.can_build(kind).ok: kinds.append([kind,str(game.sim.catalog[kind].name)])
	_fill("project_kind",kinds)
	var report: Dictionary=game.sim.operating_report()
	var outages: Array=[]
	for event in report.events: outages.append([int(event.id),"#%d %s · %.2f小时" % [event.id,event.name,event.duration]])
	_fill("outage_id",outages)
	var selected_event: Dictionary={}
	for event in report.events:
		if int(event.id)==int(_selected("outage_id")): selected_event=event; break
	recovery_chart.set_event(selected_event)
	var strategic: Dictionary=game.sim.strategy.report(game.sim)
	actions.enable.disabled=game.sim.strategy.enabled
	var projects: Array=[]
	for p in strategic.projects:
		if p.status=="building": projects.append([int(p.id),"工程 #%d · 剩余 %.1f h" % [p.id,p.remaining]])
	_fill("project_id",projects)
	var loans: Array=[]
	for l in strategic.loans: loans.append([int(l.id),"贷款 #%d · 本金 ¥%.0f" % [l.id,l.principal]])
	_fill("loan_id",loans)
	status.text="可靠供电 %.1f%% · 零售 ¥%.0f/MWh · 清洁供电 %.1f%%\n停电记录 %d · 关键负荷失供 %.2f h · 已恢复事件平均 %.2f h\n现金 ¥%.0f · 贷款本金 ¥%.0f · 长期目标 %s %.1f/24 h" % [float(game.sim.totals.reliability_lifetime)*100,float(game.sim.market.state.retail_price),float(game.sim.totals.renewable_supply_share)*100,report.events.size(),report.critical_hours,report.mean_recovery_hours,float(game.sim.cash),strategic.debt,GOAL_LABELS.get(str(strategic.goal),"尚未选择"),strategic.goal_hours]
	var signature:=str([game.sim.elapsed_hours,game.sim.cash,report.events.size(),report.cash_entries.size()])
	if signature==_signature: return
	_signature=signature
	var lines: Array[String]=["现金分类（收入为正、支出为负）："]
	for key in report.cash_categories: lines.append("%s：¥%+.0f" % [CASH_LABELS.get(key,"其他经营收支"),float(report.cash_categories[key])])
	lines.append("近期停电与恢复：")
	for event in report.events.slice(maxi(0,report.events.size()-6)):
		lines.append("%s · %s · %.2f h · 失供 %.2f MWh · %s" % [event.name,"处理中" if float(event.end)<0 else "已恢复",event.duration,event.unserved_mwh,event.cause])
	lines.append("近期现金流水：")
	for entry in report.cash_entries.slice(maxi(0,report.cash_entries.size()-8)):
		lines.append("%.2f h · %s · ¥%+.0f · 余额 ¥%.0f" % [entry.hour,entry.description,entry.amount,entry.balance])
	var rates: Dictionary=strategic.rates
	lines.append("当前附加结算 ¥/h：日前 %.0f · 偏差 %.0f · 利息 %.0f · 碳费 %.0f · 补贴 %.0f · 备用收入 %.0f/违约 %.0f" % [rates.day_ahead_cost,rates.imbalance_cost,rates.interest_cost,rates.carbon_cost,rates.subsidy_income,rates.reserve_income,rates.reserve_penalty])
	details.text="\n".join(lines)
