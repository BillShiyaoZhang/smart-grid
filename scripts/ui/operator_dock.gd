extends VBoxContainer
## One persistent map workspace. Presentation reads never execute simulation commands.
const UI = preload("res://scripts/ui/ui_kit.gd")
const Presenter = preload("res://scripts/ui/grid_presenter.gd")
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

func setup(owner_game: Node, owner_hud: Control) -> void:
	game = owner_game
	host_hud = owner_hud
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs = TabBar.new()
	for title in ["对象", "诊断", "关注", "队列"]: tabs.add_tab(title)
	tabs.tab_changed.connect(func(index: int): show_page(["object","diagnosis","watch","jobs"][index]))
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
	_sync_visibility()

func show_page(value: String) -> void:
	opened = true
	page = value
	var index: int = ["object","diagnosis","watch","jobs"].find(page)
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
	watched.clear()
	search.text = ""
	filter.select(0)
	category.select(0)
	_signature = ""

func _sync_visibility() -> void:
	if scroll == null: return
	scroll.visible = page != "object"
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
	_text("已供 %.1f / 需求 %.1f MW" % [data.get("served",0),data.get("demand",0)],UI.TEAL)
	_text("当前缺额 %.2f MW" % float(data.get("deficit",0)),UI.AMBER if float(data.get("deficit",0))>.01 else UI.MUTED)
	_text(str(data.get("summary","")))
	var alerts: Array = Presenter.alerts(game.sim)
	if not alerts.is_empty():
		_text("已知告警 · 定位后选择适用处置",UI.AMBER)
		for alert in alerts:
			_text(("! " if alert.severity=="critical" else "△ ")+str(alert.title),UI.RED if alert.severity=="critical" else UI.AMBER)
			_text(str(alert.detail),UI.MUTED)
			_text("依据："+str(alert.source),UI.MUTED)
			if int(alert.target_id)>=0: _target_button(body,"定位并处置  ›",str(alert.target_type),int(alert.target_id))
	_text("证据与可执行下一步",UI.MUTED)
	for cause in data.get("causes",[]):
		body.add_child(HSeparator.new())
		_text(str(cause.get("title",cause.get("reason","待核实"))),UI.AMBER)
		_text(str(cause.get("detail",cause.get("message",""))),UI.MUTED)
		if int(cause.get("target_id",-1)) >= 0:
			_target_button(body,"定位并检查  ›",str(cause.get("target_type","building")),int(cause.target_id))
		if not str(cause.get("action","")).is_empty(): _text("下一步："+str({"connect":"检查接线","repair":"安排维修或备用","inspect":"核实运行与相连线路","observe":"建立可信遥测或安排现场巡检","diagnose":"比较供给与实际交付"}.get(cause.action,cause.action)),UI.TEAL)
	var storm: float = float(game.sim.totals.get("storm_in",99))
	if storm < 99: _text("已知预报：风暴约 %.1f 游戏小时后抵达" % storm,UI.AMBER)
	_text("读数来自可信遥测、现场核实及公开供电反馈；未知原因需进一步核实。",UI.MUTED)

func _jobs(rows: Array) -> void:
	_text("操作队列与实际执行回执",UI.TEAL)
	_text("已排队尚未生效；返回运行或手动推进后执行。",UI.MUTED)
	if rows.is_empty(): _text("没有在途命令或本次会话执行回执。",UI.MUTED)
	for job in rows:
		body.add_child(HSeparator.new())
		var phase: String = str(job.get("phase","pending"))
		var terminal: bool = phase in ["executed","success","completed","failed","rejected"]
		var failed: bool = phase in ["failed","rejected"]
		_text(str(job.get("title","操作")),UI.RED if failed else UI.TEAL)
		_text(str(job.get("message",phase)),UI.MUTED)
		if not terminal: _text("预计剩余 %.0f 游戏分钟" % (float(job.get("remaining",0))*60))
		if int(job.get("target_id",-1))>=0: _target_button(body,"查看目标",str(job.get("target_type","building")),int(job.target_id))

func _facilities(rows: Array) -> void:
	if search.text.is_empty() and filter.selected == 0 and not watched.is_empty():
		_text("固定关注",UI.TEAL)
		for id in watched.duplicate():
			var building: Dictionary = game.sim.get_building(id)
			if building.is_empty(): watched.erase(id); continue
			_target_button(body,"★ %02d · %s" % [id,building.name],"building",id)
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
	if rows.is_empty(): _text("没有匹配设施；试试名称、类型或编号。",UI.MUTED)
