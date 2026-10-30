extends VBoxContainer
## One persistent map workspace. Presentation reads never execute simulation commands.
const UI = preload("res://scripts/ui/ui_kit.gd")
const Presenter = preload("res://scripts/ui/grid_presenter.gd")
const DepartmentDesk = preload("res://scripts/ui/department_desk.gd")
var game: Node
var host_hud: Control
var tabs: TabBar
var scroll: ScrollContainer
var body: VBoxContainer
var search: LineEdit
var filter: OptionButton
var category: OptionButton
var opened := false
var pinned := false
var page := "object"
var watched: Array[int] = []
var _signature := ""
var _expanded_evidence: Dictionary={}
var _show_all_causes := false
var department_desk: Control

func setup(owner_game: Node, owner_hud: Control) -> void:
	game = owner_game
	host_hud = owner_hud
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs = TabBar.new()
	for title in ["对象", "诊断", "关注", "队列", "部门"]: tabs.add_tab(title)
	tabs.tab_changed.connect(func(index: int): show_page(["object","diagnosis","watch","jobs","department"][index]))
	add_child(tabs)
	var controls := UI.row(self,4)
	search = LineEdit.new()
	search.placeholder_text = "检索设施 / 城市  Ctrl+F"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(_value: String): _signature=""; refresh())
	controls.add_child(search)
	filter = OptionButton.new()
	for title in ["全部", "可信", "待核实", "异常"]: filter.add_item(title)
	filter.item_selected.connect(func(_index: int): _signature=""; refresh())
	controls.add_child(filter)
	category = OptionButton.new()
	for title in ["各类","发电","输电","储能","城市","数字"]: category.add_item(title)
	category.item_selected.connect(func(_index: int): _signature=""; refresh())
	controls.add_child(category)
	controls.name = "SearchControls"
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	body = UI.column(scroll,8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	department_desk=DepartmentDesk.new()
	add_child(department_desk)
	department_desk.setup(game,host_hud)
	_sync_visibility()

func show_page(value: String) -> void:
	opened = true
	page = value
	if value not in ["object","diagnosis","watch","jobs","department"]: page="object"
	var index: int = ["object","diagnosis","watch","jobs","department"].find(page)
	if tabs.current_tab != index: tabs.current_tab = index
	_signature = ""
	_sync_visibility()
	refresh()
	host_hud.refresh_context()

func close() -> void:
	opened = false
	pinned = false
	page = "object"
	_sync_visibility()

func reset_session() -> void:
	close()
	if department_desk: department_desk.reset_session()
	watched.clear()
	search.text = ""
	filter.select(0)
	category.select(0)
	_signature = ""
	_expanded_evidence.clear()
	_show_all_causes=false

func _sync_visibility() -> void:
	if scroll == null: return
	scroll.visible = page not in ["object","department"]
	if department_desk: department_desk.visible=page=="department"
	get_node("SearchControls").visible = page == "watch"
	host_hud.inspector_scroll.visible = page == "object"
	size_flags_vertical = Control.SIZE_EXPAND_FILL if page != "object" else Control.SIZE_SHRINK_BEGIN

func open_search() -> void:
	show_page("watch")
	search.grab_focus()

func watch(id: int) -> void:
	if watched.has(id): watched.erase(id)
	elif not game.sim.get_building(id).is_empty(): watched.append(id)
	_signature = ""
	refresh()

func _text(text: String, color: Color=UI.TEXT) -> Label:
	var label := UI.label(body,text,14,color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _focus(kind: String, id: int) -> void:
	game.focus_target(kind,id)

func _target_button(parent: Node, title: String, kind: String, id: int) -> Button:
	var button := UI.button(parent,title,func(): _focus(kind,id))
	button.set_meta("action_key","focus:%s:%d" % [kind,id])
	return button

func refresh() -> void:
	if not opened or page == "object": return
	if page=="department":
		department_desk.refresh()
		return
	var data: Variant
	match page:
		"diagnosis": data = Presenter.diagnosis(game.sim)
		"jobs": data = Presenter.jobs(game.sim)
		"watch": data = Presenter.facilities(game.sim,search.text,["all","trusted","unknown","issues"][filter.selected])
	if page=="watch" and category.selected>0:
		var chosen: String = ["all","power","grid","storage","city","digital"][category.selected]
		data = data.filter(func(row: Dictionary): return row.category==chosen)
	var signature := str([page,data,watched,game.sim.totals.get("storm_in",99) if page=="diagnosis" else 0])
	if signature == _signature: return
	_signature = signature
	var scroll_position: int = scroll.scroll_vertical
	var live: VBoxContainer=body
	var draft := VBoxContainer.new()
	body=draft
	match page:
		"diagnosis": _diagnosis(data)
		"jobs": _jobs(data)
		"watch": _facilities(data)
	body=live
	if _shape(live)==_shape(draft):
		_sync_values(live,draft)
	else:
		var focus: Control=get_viewport().gui_get_focus_owner()
		var focus_key: String=str(focus.get_meta("action_key","")) if focus!=null else ""
		for child in live.get_children(): live.remove_child(child); child.queue_free()
		for child in draft.get_children(): draft.remove_child(child); live.add_child(child)
		if not focus_key.is_empty(): _restore_focus(live,focus_key)
	draft.free()
	scroll.set_deferred("scroll_vertical",scroll_position)

func _shape(node: Node) -> String:
	var result: String=node.get_class()+str(node.get_meta("action_key",""))
	for child in node.get_children(): result+="("+_shape(child)+")"
	return result

func _sync_values(live: Node, draft: Node) -> void:
	if live.has_method("sync_from"): live.sync_from(draft)
	if live is Label or live is Button:
		live.text=draft.text
		live.add_theme_color_override("font_color",draft.get_theme_color("font_color"))
	for index in live.get_child_count(): _sync_values(live.get_child(index),draft.get_child(index))

func _restore_focus(node: Node, key: String) -> void:
	if node is Button and str(node.get_meta("action_key",""))==key:
		node.grab_focus.call_deferred()
		return
	for child in node.get_children(): _restore_focus(child,key)

func _diagnosis(data: Dictionary) -> void:
	var deficit: float=float(data.get("deficit",0))
	var compact: bool=game.root_ui.size.y<780
	if not compact:
		UI.label(body,"缺口 %.1f MW" % deficit if deficit>.01 else "当前供电充足",26,UI.RED if deficit>.01 else UI.TEAL)
		var gauge: Control=UI.metric(body,"已供 / 需求",float(data.get("served",0)),maxf(.001,float(data.get("demand",0))),"MW",UI.TEAL,true,"当前需求 %.1f MW" % float(data.get("demand",0)))
		gauge.hatch_remainder=true
		_text("按已知证据处置",UI.MUTED)
	var causes: Array=data.get("causes",[])
	for index in causes.size():
		if index>=3 and not _show_all_causes: break
		var cause: Dictionary=causes[index]
		var accent: Color=UI.RED if cause.get("severity","")=="critical" else UI.AMBER
		var card: VBoxContainer=UI.card(body,Color(accent,.5),10)
		var title := UI.label(card,str(cause.get("title","待核实")),17,UI.TEXT)
		title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		UI.badge(card,str(cause.get("source","已知证据")),accent)
		if int(cause.get("target_id",-1))>=0:
			var action: String=str({"connect":"开始接线","repair":"定位并安排抢修","inspect":"定位并检查","observe":"核实运行状态"}.get(cause.get("action",""),"定位对象"))
			var button := UI.action(UI.button(card,action,func(): _act_on_cause(cause)))
			button.set_meta("action_key","cause:"+str(cause.id))
		var evidence_key: String=str(cause.get("id",index))
		var expand := UI.button(card,"收起证据 ▴" if _expanded_evidence.get(evidence_key,false) else "证据与说明 ▾",func():
			_expanded_evidence[evidence_key]=not _expanded_evidence.get(evidence_key,false)
			_signature=""
			refresh(),Vector2(0,30))
		expand.set_meta("action_key","evidence:"+evidence_key)
		if _expanded_evidence.get(evidence_key,false):
			var detail := UI.label(card,str(cause.get("detail","")),14,UI.MUTED)
			detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if causes.size()>3:
		UI.button(body,"收起其他证据" if _show_all_causes else "查看其余 %d 项证据" % (causes.size()-3),func(): _show_all_causes=not _show_all_causes; _signature=""; refresh())
	var storm: float = float(game.sim.totals.get("storm_in",99))
	if storm < 99: _text("△ 风暴预报 · %.1f 游戏小时" % storm,UI.AMBER)
	if int(data.get("unknown_count",0))>0: _text("? 未知设备状态保持待核实",UI.MUTED)

func _act_on_cause(cause: Dictionary) -> void:
	_focus(str(cause.get("target_type","building")),int(cause.target_id))
	if cause.get("action","")=="connect":
		game._set_tool("line")
		game.connection_start=int(cause.target_id)
		game._update_hud()

func _jobs(rows: Array) -> void:
	_text("草案 → 提交 → 执行 → 生效 / 拒绝",UI.MUTED)
	var field_jobs: Array=rows.filter(func(job: Dictionary): return bool(job.get("crew_active",job.get("method","")=="field" and job.get("phase","")=="pending")))
	var displayed: Array[String]=[]
	for index in 2:
		var card: VBoxContainer=UI.card(body,Color("36515b"),10)
		var heading := UI.row(card,6)
		UI.label(heading,"▣ 队伍 %d" % (index+1),16)
		UI.spacer(heading)
		UI.badge(heading,"执行中" if index<field_jobs.size() else "空闲",UI.AMBER if index<field_jobs.size() else UI.TEAL)
		if index<field_jobs.size():
			displayed.append(str(field_jobs[index].get("key","")))
			_job_body(card,field_jobs[index])
	if rows.is_empty(): _text("没有在途命令或近期回执。",UI.MUTED)
	for job in rows:
		var phase: String = str(job.get("phase","pending"))
		if bool(job.get("crew_active",false)) and str(job.get("key","")) in displayed: continue
		var failed: bool = phase in ["failed","rejected"]
		var card: VBoxContainer=UI.card(body,UI.RED if failed else Color("36515b"),10)
		var caption: String=str({"pending":"◷ 远程在途" if job.get("method","")=="remote" else "◷ 现场执行","queued":"◷ 等待现场队","executed":"✓ 已执行","rejected":"× 已拒绝","cancelled":"已取消","reported":"最新回执"}.get(phase,phase))
		UI.badge(card,caption,UI.RED if failed else (UI.AMBER if phase=="queued" else UI.TEAL))
		_job_body(card,job)

func _job_body(parent: Node, job: Dictionary) -> void:
	UI.label(parent,str(job.get("title","操作")),16)
	UI.label(parent,str(job.get("source","操作工单")),12,UI.MUTED)
	var remaining: float=float(job.get("remaining",0))
	if job.get("phase","")=="pending":
		var duration: float=float(job.get("duration",0))
		var stage: String=str({"travel":"赶赴现场","work":"现场作业"}.get(str(job.get("work_stage","")),"在途")) if job.get("method","")=="field" else "远程在途"
		var caption: String="%s · 预计剩余 %.0f 游戏分钟 · 尚未生效" % [stage,remaining*60]
		if duration>0:
			var progress: Control=UI.metric(parent,"预计剩余",maxf(0,duration-remaining),duration,"",UI.AMBER,true,caption)
			progress.show_value=false
		else:
			var pending_label:=UI.label(parent,caption,14,UI.AMBER)
			pending_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	elif job.get("phase","")=="queued":
		var queued:=UI.label(parent,"等待空闲现场队 · 出发时间未定\n出发后预计还需 %.0f 游戏分钟；尚未生效" % (remaining*60),14,UI.AMBER)
		queued.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	else:
		var message := UI.label(parent,str(job.get("message","请核对实际生效值")),14,UI.MUTED)
		message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if job.has("travel_remaining") and job.has("work_remaining"):
		var stages:=UI.label(parent,"路程剩余 %.0f 分钟 · 作业剩余 %.0f 分钟" % [float(job.travel_remaining)*60,float(job.work_remaining)*60],12,UI.MUTED)
		stages.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if int(job.get("target_id",-1))>=0: _target_button(parent,"查看目标",str(job.get("target_type","building")),int(job.target_id))

func _facilities(rows: Array) -> void:
	if search.text.is_empty() and filter.selected == 0 and not watched.is_empty():
		_text("固定关注",UI.TEAL)
		for id in watched.duplicate():
			var building: Dictionary = game.sim.get_building(id)
			if building.is_empty(): watched.erase(id); continue
			_target_button(body,"★ %02d · %s" % [id,building.name],"building",id)
			for item in rows:
				if int(item.id)==id: _facility_gauge(item); break
		body.add_child(HSeparator.new())
	# Cities are public feedback, rather than device telemetry.
	for city in game.sim.region.cities:
		var name: String = str(city.get("name","城市"))
		if not search.text.is_empty() and not search.text.to_lower() in name.to_lower(): continue
		var anchor: Vector2i = city.get("anchor",Vector2i.ZERO)
		UI.button(body,"⌂ "+name,func(): game.focus_cell(anchor)).set_meta("action_key","city:"+name)
	_text("设施 %d · ★ 可固定关注" % rows.size(),UI.MUTED)
	for row in rows:
		var id: int = int(row.id)
		var line := UI.row(body,5)
		var button := _target_button(line,"%02d · %s" % [id,row.get("name","")],"building",id)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UI.button(line,"★" if watched.has(id) else "☆",func(): watch(id),Vector2(34,34)).set_meta("action_key","watch:%d" % id)
		_text(str(row.get("status","待核实")),UI.TEAL if row.get("trusted",false) else UI.AMBER)
		_facility_gauge(row)
	if rows.is_empty(): _text("没有匹配设施；试试名称、类型或编号。",UI.MUTED)

func _facility_gauge(row: Dictionary) -> void:
	var known: bool=bool(row.get("trusted",false))
	var category_name: String=str(row.get("category",""))
	var value: float=0.0
	var maximum: float=maxf(.001,float(row.get("capacity",1)))
	var title := "实际输出"
	var unit := "MW"
	if category_name=="storage":
		title="储存电量"
		unit="MWh"
		maximum=maxf(.001,float(row.get("energy_capacity",0)))
		value=float(row.get("energy",0)) if known else 0.0
	elif category_name=="city":
		title="实际供电"
		maximum=maxf(.001,float(row.get("demand",.001))) if known else maximum
		value=float(row.get("served",0)) if known else 0.0
	elif category_name=="power": value=float(row.get("output",0)) if known else 0.0
	else: return
	var gauge: Control=UI.metric(body,title,value,maximum,unit,UI.TEAL,known)
	gauge.compact=true
	gauge.custom_minimum_size.y=44
