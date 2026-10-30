extends VBoxContainer
## Seven professional views share one map, one asset identity and one action path.
const UI=preload("res://scripts/ui/ui_kit.gd")
const Attention=preload("res://scripts/ui/attention_model.gd")
const Matrix=preload("res://scripts/ui/department_chart.gd")
const Presenter=preload("res://scripts/ui/grid_presenter.gd")
const ReliabilityChart=preload("res://scripts/ui/reliability_chart.gd")
const TITLES={"operations":"运行","planning":"规划","maintenance":"运维","market":"市场","assets":"资产","customers":"客户","digital":"数字"}
var game: Node
var hud: Control
var body: VBoxContainer
var scroll: ScrollContainer
var snapshot: Dictionary={}
var _signature:=""
var expanded: Dictionary={}
var reliability_metric:="saidi_minutes"

func setup(owner_game: Node,owner_hud: Control) -> void:
	game=owner_game; hud=owner_hud
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.follow_focus=true
	add_child(scroll)
	body=UI.column(scroll,10)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.resized.connect(_fit_charts)

func _text(parent: Node,caption: String,color: Color=UI.MUTED,large: int=14) -> Label:
	var label:=UI.label(parent,caption,large,color)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return label

func _button(parent: Node,caption: String,action: Callable,key: String) -> Button:
	var button:=UI.button(parent,caption,action)
	button.set_meta("action_key",key)
	button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return button

func _toggle(parent: Node,key: String,caption: String) -> bool:
	_button(parent,caption+(" ▴" if expanded.get(key,false) else " ▾"),func():
		expanded[key]=not expanded.get(key,false)
		_signature=""; refresh(),"expand:"+key)
	return bool(expanded.get(key,false))

func refresh() -> void:
	if game==null or not visible: return
	snapshot=Attention.snapshot(game.sim,hud.lens,game.preferences.information_depth)
	var reliability: Dictionary=game.sim.reliability_metrics.report(game.sim)
	var signature:=str([snapshot,reliability,expanded,game.preferences.information_depth])
	if _signature==signature: return
	_signature=signature
	var previous_scroll:=scroll.scroll_vertical
	var focused: Control=get_viewport().gui_get_focus_owner()
	var focus_key: String=str(focused.get_meta("action_key","")) if focused!=null and is_ancestor_of(focused) else ""
	for child in body.get_children(): body.remove_child(child); child.queue_free()
	_text(body,TITLES.get(hud.lens,"运行")+"视角",UI.TEAL,21)
	_text(body,str(snapshot.get("purpose","从结果定位证据，再比较和执行。")))
	var kpis: Array=snapshot.get("kpis",[])
	for kpi in kpis.slice(0,3): _kpi(body,kpi)
	if kpis.size()>3 and _toggle(body,"more_kpis","更多部门指标"):
		for kpi in kpis.slice(3): _kpi(body,kpi)
	if _toggle(body,"outcomes","六项系统结果"):
		for kpi in Attention.global_kpis(game.sim): _kpi(body,kpi)
	_text(body,"优先关注 · 按影响与紧迫性排序",UI.TEXT,16)
	var risks: Array=snapshot.get("risks",[])
	if risks.is_empty(): _text(body,"当前没有该视角的已知紧急事项。",UI.TEAL)
	for risk in risks: _risk(risk)
	if hud.lens=="assets": _assets()
	if hud.lens in ["operations","customers","maintenance"]: _reliability(reliability)
	if hud.lens=="customers": _customers()
	if hud.lens=="maintenance":
		_button(body,"查看现场队、待派工与执行回执",func(): hud.operator_dock.show_page("jobs"),"jobs")
	if hud.lens=="planning":
		_text(body,"比较当前、计划和单故障三种情景；预测采用声明的未知状态假设。")
		_button(body,"打开三方案比较与单故障推演",func(): open_center("planning"),"compare")
	if hud.lens=="market":
		_text(body,"低价进口仍会占用线路容量。现金收益需与拥塞、备用及客户影响一起核对。")
	for relation in snapshot.get("cross_lens",[]):
		var target: String=str(relation.get("lens",relation.get("target_lens","operations")))
		_button(body,str(relation.get("title",relation.get("label","关联视角")))+" → "+str(TITLES.get(target,"运行")),func(): hud.set_lens(target),"cross:"+target)
	_button(body,{"operations":"供电诊断与证据","planning":"发展与长期规划","maintenance":"运维处置工作台","market":"交易与结算工作台","assets":"资产维护工作台","customers":"街区与微电网协调","digital":"通信、遥测与安全工作台"}.get(hud.lens,"工作台"),func(): open_center(hud.lens),"center:"+hud.lens)
	if game.preferences.information_depth=="engineer":
		_text(body,"模型边界：有功潮流与工程压降近似；影响为公开拓扑代理，未知状态不等于正常。单故障推演不是完整 N−1 安全认证。")
	scroll.set_deferred("scroll_vertical",previous_scroll)
	if not focus_key.is_empty(): _restore_focus(body,focus_key)
	_fit_charts.call_deferred()

func _fit_charts() -> void:
	if scroll==null or scroll.size.y<=0: return
	for node in body.find_children("*","Control",true,false):
		if node.get_script()==Matrix or node.get_script()==ReliabilityChart:
			node.custom_minimum_size.y=clampf(scroll.size.y-12,120,220 if node.get_script()==Matrix else 174)

func _restore_focus(node: Node,key: String) -> void:
	if node is Button and str(node.get_meta("action_key",""))==key: node.grab_focus.call_deferred(); return
	for child in node.get_children(): _restore_focus(child,key)

func reset_session() -> void:
	expanded.clear()
	snapshot.clear()
	_signature=""
	reliability_metric="saidi_minutes"
	scroll.scroll_vertical=0

func _kpi(parent: Node,kpi: Dictionary) -> void:
	var value: Variant=kpi.get("value")
	var text: String="? 待核实" if value==null else (str(value) if value is String else "%.1f" % float(value))
	var button:=_button(parent,str(kpi.get("label","指标"))+"  "+text+" "+str(kpi.get("unit","")),func():
		if int(kpi.get("target_id",-1))>=0: game.focus_target(str(kpi.get("target_type","facility")),int(kpi.target_id))
		else:
			if str(kpi.get("id","")) in ["saidi","saifi","ens","reliability"]: expanded.reliability=true
			expanded["kpi:"+str(kpi.get("id",""))]=not expanded.get("kpi:"+str(kpi.get("id","")),false)
			_signature=""; refresh(),"kpi:"+str(kpi.get("id","")))
	button.alignment=HORIZONTAL_ALIGNMENT_LEFT
	button.tooltip_text=str(kpi.get("detail",""))+"\n证据："+str(kpi.get("source","公开运营反馈"))
	if game.preferences.information_depth!="beginner" or expanded.get("kpi:"+str(kpi.get("id","")),false):
		_text(parent,str(kpi.get("detail",""))+" · "+str(kpi.get("source","公开反馈")))

func _risk(risk: Dictionary) -> void:
	var card:=UI.card(body,UI.RED if risk.get("severity","")=="critical" else Color("82664a"),10)
	_text(card,"! "+str(risk.get("title","待核实")),UI.TEXT,16)
	_text(card,str(risk.get("consequence",risk.get("detail",""))),UI.AMBER)
	var key: String="risk:"+str(risk.get("id",""))
	if _toggle(card,key,"原因、证据与下一步"):
		_text(card,str(risk.get("detail","")))
		_text(card,"证据："+str(risk.get("source","公开反馈"))+"\n紧迫性："+str(risk.get("urgency","按当前反馈核实")))
		if int(risk.get("target_id",-1))>=0:
			_button(card,"定位对象与适用操作",func(): game.focus_target(str(risk.get("target_type","facility")),int(risk.target_id)),key+":focus")
		else: _button(card,"查看相关处置工作台",func(): open_center(str(risk.get("lens",hud.lens))),key+":open")
		var action: String=str(risk.get("action",""))
		if action=="connect" and int(risk.get("target_id",-1))>=0:
			_button(card,"开始接线",func(): game.focus_target(str(risk.get("target_type","facility")),int(risk.target_id)); game._set_tool("line"); game.connection_start=int(risk.target_id),key+":connect")

func _assets() -> void:
	_text(body,"健康 × 公开影响",UI.TEXT,17)
	var chart:=Matrix.new()
	body.add_child(chart)
	chart.set_rows(snapshot.get("assets",[]))
	chart.target_selected.connect(func(kind: String,id: int): game.focus_target(kind,id))
	_text(body,"影响依据公开连接和关键负荷；不把未知健康推断成故障概率。")
	if _toggle(body,"asset_list","资产证据与维护选择"):
		for row in snapshot.get("assets",[]):
			_text(body,str(row.get("name","资产"))+" · "+("? 健康待核实" if row.get("health")==null else ("旧巡检记录 %.0f%% · 当前未知" if row.get("confidence","")=="stale" else "健康 %.0f%%") % float(row.health)))
			_button(body,"定位检修 / 更换对象",func(): game.focus_target(str(row.get("target_type","facility")),int(row.get("target_id",row.get("id",-1)))),"asset:"+str(row.get("target_type","facility"))+":"+str(row.get("target_id",row.get("id",-1))))

func _customers() -> void:
	if not _toggle(body,"customers","供电反馈与关键负荷"): return
	for building in game.sim.buildings:
		var feedback: Dictionary=Presenter.customer_feedback(game.sim,int(building.id))
		if feedback.is_empty(): continue
		var id: int=int(building.id)
		_button(body,("✚ " if building.kind=="hospital" else "")+str(building.name)+" · "+str(feedback.text),func(): game.focus_target("facility",id),"customer:"+str(id))

func _reliability(report: Dictionary) -> void:
	if not _toggle(body,"reliability","可靠性、事件贡献与事故复盘"): return
	var summary: Dictionary=report.get("summary",{})
	_text(body,"负荷点口径 · 每个已服务聚合街区计一点；非真实户数",UI.AMBER)
	if float(summary.get("elapsed_hours",0))<=0:
		_text(body,"尚未形成统计样本。推进真实时间后开始记录；旧档不补造历史。")
		return
	_text(body,"自 %.2f h 起 · %d 点\n平均停电 %.1f 分钟 · 平均 %.2f 次\n每次停电平均 %.1f 分钟 · 失供 %.2f MWh" % [float(summary.get("started_at",0)),int(summary.get("enrolled_points",0)),float(summary.get("saidi_minutes",0)),float(summary.get("saifi",0)),float(summary.get("caidi_minutes",0)),float(summary.get("ens_mwh",0))],UI.TEXT)
	if game.preferences.information_depth!="beginner": _text(body,"SAIDI %.2f min · SAIFI %.3f · CAIDI %.2f min\nCMI %.1f 点·分钟" % [float(summary.get("saidi_minutes",0)),float(summary.get("saifi",0)),float(summary.get("caidi_minutes",0)),float(summary.get("cmi",0))])
	var picker:=OptionButton.new()
	var metrics: Array=["saidi_minutes","saifi","cmi","ens_mwh"]
	for title in ["平均停电时长 SAIDI","平均停电次数 SAIFI","累计失供点分钟 CMI","累计失供电量 ENS"]: picker.add_item(title)
	picker.fit_to_longest_item=false
	picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	picker.select(metrics.find(reliability_metric))
	picker.set_meta("action_key","reliability_metric")
	picker.item_selected.connect(func(i: int): reliability_metric=metrics[i]; _signature=""; refresh())
	body.add_child(picker)
	var chart:=ReliabilityChart.new()
	body.add_child(chart)
	chart.set_rows(report.get("trend",[]),reliability_metric)
	_text(body,"累计纳入点数随开通增加；趋势分母取各采样时刻，最多保留96条小时记录。")
	var contributions: Array=report.get("incidents",[]).duplicate(true)
	contributions.append_array(report.get("events",[]))
	contributions.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.get("cmi",0))>float(b.get("cmi",0)))
	_text(body,"平均停电时长的事件贡献",UI.TEXT,16)
	var shown:=0.0
	for event in contributions.slice(0,3):
		var minutes: float=float(event.get("saidi_contribution_minutes",0))
		shown+=minutes
		var key: String="incident:"+str(event.get("id",0))
		_button(body,str(event.get("name","事件"))+"  +%.2f 分钟/点 →" % minutes,func(): expanded[key]=true; _signature=""; refresh(),"contribution:"+str(event.get("id",0)))
		var gauge: Control=UI.metric(body,"",minutes,maxf(.001,float(summary.get("saidi_minutes",0))),"",UI.AMBER,true)
		gauge.show_value=false; gauge.compact=true; gauge.custom_minimum_size.y=16
	_text(body,"其他及归档贡献 %.2f 分钟/点 · 归档事件 %d" % [maxf(0,float(summary.get("saidi_minutes",0))-shown),int(summary.get("archived",{}).get("interruption_count",0))])
	var events: Array=report.get("incidents",[]).duplicate(true)
	var completed: Array=report.get("events",[])
	events.append_array(completed.slice(0,6))
	for event in contributions.slice(0,3):
		if not events.any(func(row: Dictionary): return int(row.id)==int(event.id)): events.append(event)
	if events.is_empty(): _text(body,"尚无已记录的供电中断。推进时间后记录实际结果。")
	for event in events:
		var id: int=int(event.get("facility_id",-1))
		var card:=UI.card(body,UI.AMBER if float(event.get("end",-1))<0 else Color("36515b"),8)
		_text(card,("✚ " if event.get("critical",false) else "")+str(event.get("name","供电事件"))+" · "+str(event.get("outcome","")),UI.TEXT,16)
		_text(card,"%.1f 分钟 · 失供 %.2f MWh · CMI %.1f" % [float(event.get("duration_hours",0))*60,float(event.get("ens_mwh",0)),float(event.get("cmi",0))])
		if _toggle(card,"incident:"+str(event.get("id",0)),"已知事实、候选动作与结果"):
			_text(card,str(event.get("cause","用户报告失供；精确原因待核实")))
			for evidence in event.get("evidence",[]): _text(card,"✓ "+str(evidence))
			for action in event.get("actions",[]): _text(card,"→ "+str(action))
			_text(card,str(event.get("after_action","")))
			_text(card,"? 现场或可信遥测核实前，不推断精确故障。")
			if id>=0: _button(card,"定位受影响负荷",func(): game.focus_target("facility",id),"incident:focus:"+str(event.get("id",0)))

func open_center(value: String) -> void:
	if value=="operations": hud.operator_dock.show_page("diagnosis"); return
	var center: String="planning" if value=="planning" else ("market" if value=="market" else "network")
	game._open_center(center)
	if center=="planning" and game.planning_panel.visible and not game.planning_panel.tabs.is_tab_hidden(3): game.planning_panel.tabs.current_tab=3
	if center=="network" and game.digital_panel.visible:
		var tabs: TabContainer=game.digital_panel.tabs
		if value=="digital":
			tabs.current_tab=0
			return
		for i in tabs.get_tab_count():
			if not tabs.is_tab_hidden(i) and "资产" in tabs.get_tab_title(i) and value in ["assets","customers","maintenance"]:
				tabs.current_tab=i
				var operations: Node=game.digital_panel.get("grid_operations")
				if operations!=null:
					operations.section.select(2 if value=="customers" else 0)
					operations._select_section(2 if value=="customers" else 0)
					operations.inherit_selection(int(game.selected_id),int(game.selected_line))
				break
