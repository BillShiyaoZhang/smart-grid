extends Control
## Map-first HUD. Lightweight popovers never pause or mutate the simulation.
const UI = preload("res://scripts/ui/ui_kit.gd")
const Chart = preload("res://scripts/ui/power_chart.gd")
signal tool_requested(value: String)
signal build_requested(kind: String)
signal overlay_requested(value: String)
signal center_requested(value: String)
signal action_requested(value: String)

var game: Node
var values: Dictionary = {}
var tool_buttons: Dictionary = {}
var build_buttons: Dictionary = {}
var category_buttons: Dictionary = {}
var overlay_buttons: Dictionary = {}
var popups: Dictionary = {}
var popup_order: Array[String] = []
var active_category := ""
var tray: PanelContainer
var tray_title: Label
var tray_flow: HFlowContainer
var inspector: PanelContainer
var inspector_box: VBoxContainer
var inspector_scroll: ScrollContainer
var objective: Button
var mission_box: VBoxContainer
var research_button: Button
var response_button: Button
var events_label: RichTextLabel
var alert_button: Button
var alerts_box: VBoxContainer
var time_label: Label
var weather_label: Label
var hint_label: Label
var mode_label: Label
var notice_label: Label
var tooltip_label: Label
var market_ticker: Label
var digital_ticker: Label
var chart: Control
var topology: Control
var statistics: Label
var speed_buttons: Dictionary = {}
var pause_button: Button
var advanced_open := false

func setup(owner_game: Node) -> void:
	game = owner_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

static func category_for(kind: String) -> String:
	if kind in ["battery","pumped_storage","flow_battery","community_battery","hydrogen","thermal_storage"]: return "storage"
	if kind in ["sensor","control","relay","soc"]: return "digital"
	if kind in ["home","factory","hospital","academy","cooling"]: return "city"
	if kind in ["substation","intertie","hvdc","condenser"]: return "grid"
	return "power"

func _panel(parent: Node) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel",UI.style(Color("112b35f5"),8,Color("3c5961"),10,true))
	parent.add_child(p)
	return p

func _icon(key: String) -> Texture2D:
	var paths := {
		"select":"M5 3 L18 13 L12 14 L9 21 Z",
		"line":"M4 19 L10 5 L16 19 M7 13 H18 M4 20 H20",
		"repair":"M15 3 A6 6 0 0 0 8 10 L3 17 L7 21 L14 14 A6 6 0 0 0 21 7 L17 11 L13 7 Z",
		"datalink":"M7 8 A6 6 0 0 1 10 20 M17 16 A6 6 0 0 1 14 4 M8 16 L16 8",
		"power":"M14 2 L5 13 H11 L9 22 L20 10 H13 Z",
		"grid":"M3 6 H21 M6 6 V20 M18 6 V20 M9 10 H15 V16 H9 Z",
		"storage":"M3 7 H20 V19 H3 Z M20 11 H23 V15 M11 9 V17 M7 13 H15",
		"city":"M3 21 V10 H10 V21 M10 21 V4 H20 V21 M1 21 H23 M14 8 H16 M14 12 H16 M5 14 H7",
		"digital":"M7 7 H17 V17 H7 Z M10 1 V7 M14 1 V7 M10 17 V23 M14 17 V23 M1 10 H7 M1 14 H7 M17 10 H23 M17 14 H23",
		"market":"M3 8 H20 L16 4 M21 16 H4 L8 20",
		"network":"M5 5 L19 7 L12 19 Z M2 2 H8 V8 H2 Z M16 4 H22 V10 H16 Z M9 16 H15 V22 H9 Z",
		"planning":"M4 21 V14 H9 V21 M10 21 V9 H15 V21 M16 21 V3 H21 V21",
	}
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="%s" fill="none" stroke="#d9e9e1" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>' % paths.get(key,paths.select)
	var img := Image.new()
	img.load_svg_from_string(svg)
	return ImageTexture.create_from_image(img)

func _dock_button(parent: Node, key: String, caption: String, callback: Callable) -> Button:
	var b := UI.button(parent,caption,callback,Vector2(70,46),true)
	b.icon = _icon(key)
	b.add_theme_constant_override("icon_max_width",22)
	b.add_theme_constant_override("h_separation",5)
	b.tooltip_text = caption
	return b

func _popup(key: String, title: String, width: float=344, right: bool=false) -> VBoxContainer:
	var p := _panel(self)
	p.name = key.capitalize()+"Popup"
	if right:
		p.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		p.offset_left = -width-16
		p.offset_right = -16
		p.offset_top = 68
		p.offset_bottom = 68
	else:
		p.position = Vector2(16,116)
	p.size = Vector2(width,0)
	var v := UI.column(p,10)
	var heading := UI.row(v)
	UI.label(heading,title,18)
	UI.spacer(heading)
	UI.button(heading,"×",func(): toggle_popup(key),Vector2(34,34))
	popups[key] = p
	p.hide()
	return v

func _build() -> void:
	# Small city identity and current objective; everything else is requested.
	var city := _panel(self)
	city.position = Vector2(16,16)
	var cv := UI.column(city,3)
	var heading := UI.row(cv,8)
	UI.label(heading,"ϟ",26,UI.TEAL)
	UI.label(heading,"青屿湾",20)
	UI.label(heading,"潮汐电网",14,UI.MUTED)
	objective = UI.button(cv,"当前委托",func(): toggle_popup("missions"),Vector2(292,34))
	var top := _panel(self)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.offset_left = -270
	top.offset_right = -16
	top.offset_top = 16
	top.offset_bottom = 60
	var nav := UI.row(top,6)
	alert_button = UI.button(nav,"告警 0",func(): toggle_popup("alerts"))
	UI.button(nav,"日志",func(): toggle_popup("log"))
	UI.button(nav,"菜单",func(): toggle_popup("menu"))
	var layers := _panel(self)
	layers.position = Vector2(16,156)
	var lv := UI.column(layers,6)
	UI.button(lv,"图层",func(): toggle_popup("layers"))
	UI.button(lv,"统计",func(): toggle_popup("stats"))
	# A single context drawer, above the always-visible bottom controls.
	inspector = _panel(self)
	inspector.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	inspector.offset_left = -364
	inspector.offset_right = -16
	inspector.offset_top = 72
	inspector.offset_bottom = -154
	var iv := UI.column(inspector,6)
	var ih := UI.row(iv)
	UI.label(ih,"对象详情",14,UI.MUTED)
	UI.spacer(ih)
	UI.button(ih,"×",func(): action_requested.emit("clear_selection"),Vector2(34,34))
	inspector_scroll = ScrollContainer.new()
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	iv.add_child(inspector_scroll)
	inspector_box = UI.column(inspector_scroll,8)
	inspector_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.hide()
	# Bottom tool dock.
	var dock := _panel(self)
	dock.add_theme_stylebox_override("panel",UI.style(Color("112b35f5"),8,Color("3c5961"),8))
	dock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	dock.offset_left = -540
	dock.offset_right = 540
	dock.offset_top = -124
	dock.offset_bottom = -64
	var dr := UI.row(dock,5)
	dr.alignment = BoxContainer.ALIGNMENT_CENTER
	for spec in [["select","选择"],["line","接线"],["repair","抢修"],["datalink","通信"]]:
		var key: String = spec[0]
		tool_buttons[key] = _dock_button(dr,key,spec[1],func(): tool_requested.emit(key))
		tool_buttons[key].tooltip_text = "%s  [%d]" % [spec[1],tool_buttons.size()]
	dr.add_child(VSeparator.new())
	for spec in [["power","发电"],["grid","输电"],["storage","储能"],["city","城市"],["digital","数字"]]:
		var key: String = spec[0]
		category_buttons[key] = _dock_button(dr,key,spec[1],func(): toggle_category(key))
	dr.add_child(VSeparator.new())
	for spec in [["market","市场 M"],["network","电网 N"],["planning","科技 T"]]:
		var key: String = spec[0]
		var entry := _dock_button(dr,key,spec[1],func(): center_requested.emit(key))
		entry.toggle_mode = false
	# Expandable, categorized catalog uses every facility from the simulation.
	tray = _panel(self)
	tray.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	tray.offset_left = 100
	tray.offset_right = -100
	tray.offset_top = -338
	tray.offset_bottom = -140
	var tv := UI.column(tray,8)
	var th := UI.row(tv)
	tray_title = UI.label(th,"设施目录",18)
	UI.spacer(th)
	UI.button(th,"收起 ×",func(): close_tray())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tv.add_child(scroll)
	tray_flow = HFlowContainer.new()
	tray_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tray_flow.add_theme_constant_override("h_separation",8)
	tray_flow.add_theme_constant_override("v_separation",8)
	scroll.add_child(tray_flow)
	for item in game.sim.catalog:
		var kind: String = item
		var spec: Dictionary = game.sim.catalog[kind]
		var b := UI.button(tray_flow,"%s\n¥%s" % [spec.name,game._compact(spec.price)],func(): build_requested.emit(kind),Vector2(170,64),true)
		var icon_path := "res://assets/icons/%s.png" % kind
		if ResourceLoader.exists(icon_path): b.icon = load(icon_path); b.expand_icon = true; b.add_theme_constant_override("icon_max_width",36)
		b.set_meta("category",category_for(kind))
		b.tooltip_text = spec.description
		build_buttons[kind] = b
	tray.hide()
	# Tool hint floats with the active context, rather than being permanent prose.
	var hint := _panel(self)
	hint.name = "ToolHint"
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -480
	hint.offset_right = 480
	hint.offset_top = -190
	hint.offset_bottom = -144
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hr := UI.row(hint,10)
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_label = UI.label(hr,"运行视图",14,UI.TEAL)
	hint_label = UI.label(hr,"",14)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.hide()
	# One slim status rail.
	var status := _panel(self)
	status.add_theme_stylebox_override("panel",UI.style(Color("112b35f5"),6,Color("3c5961"),8))
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_left = 0
	status.offset_right = 0
	status.offset_top = -54
	status.offset_bottom = 0
	var sr := UI.row(status,10)
	time_label = UI.label(sr,"第 1 天 08:00",14)
	weather_label = UI.label(sr,"晴朗",14,UI.MUTED)
	pause_button = UI.button(sr,"Ⅱ",func(): action_requested.emit("pause"),Vector2(34,34),true)
	for speed in [1,3,8]:
		var value: int = speed
		speed_buttons[value] = UI.button(sr,"%d×" % value,func(): action_requested.emit("speed_%d" % value),Vector2(35,34),true)
	UI.spacer(sr)
	values.cash = UI.label(sr,"¥180,000",18)
	values.balance = UI.label(sr,"+ ¥0/h",14,UI.TEAL)
	UI.spacer(sr)
	values.supply = UI.label(sr,"0 / 0 MW",14)
	values.reliability = UI.label(sr,"100%",14,UI.TEAL)
	values.supply.tooltip_text = "当前已供电 / 当前需求（MW）"
	values.reliability.tooltip_text = "当前供电可靠率"
	values.cash.tooltip_text = "可用建设与运营资金"
	values.balance.tooltip_text = "每游戏小时净收益"
	for key in ["supply","reliability","cash","balance"]: values[key].mouse_filter = Control.MOUSE_FILTER_PASS
	# Full objectives and actions are in a non-modal popover.
	var tasks := _popup("missions","运营委托",350)
	mission_box = UI.column(tasks,8)
	research_button = UI.button(tasks,"遥测研究",func(): action_requested.emit("research"))
	response_button = UI.button(tasks,"需求响应",func(): action_requested.emit("response"))
	UI.button(tasks,"风暴演练",func(): action_requested.emit("storm"))
	var log := _popup("log","调度日志",400,true)
	events_label = RichTextLabel.new()
	events_label.bbcode_enabled = true
	events_label.custom_minimum_size = Vector2(0,280)
	events_label.add_theme_font_size_override("normal_font_size",14)
	log.add_child(events_label)
	var menu := _popup("menu","游戏菜单",250,true)
	for spec in [["save","保存游戏  F5"],["load","读取游戏  F9"],["help","调度员手册  H"]]:
		var key: String = spec[0]
		UI.button(menu,spec[1],func(): close_popups(); action_requested.emit(key))
	var layer_list := _popup("layers","地图图层",260)
	for spec in [["normal","景观"],["power","功率"],["health","健康"],["comm","通信"]]:
		var key: String = spec[0]
		overlay_buttons[key] = UI.button(layer_list,spec[1],func(): overlay_requested.emit(key),Vector2(0,36),true)
	var stat := _popup("stats","电网运行概览",420)
	stat.add_theme_constant_override("separation",8)
	var stat_line := UI.row(stat)
	values.renewables = UI.label(stat_line,"",16,UI.TEAL)
	UI.spacer(stat_line)
	values.battery = UI.label(stat_line,"",16)
	statistics = UI.label(stat,"",14,UI.MUTED)
	UI.label(stat,"供需趋势  ·  青绿供给 / 琥珀需求",14)
	chart = Chart.new()
	chart.custom_minimum_size = Vector2(0,95)
	stat.add_child(chart)
	UI.label(stat,"电力拓扑",14)
	topology = Chart.new()
	topology.mode = "topology"
	topology.sim = game.sim
	topology.custom_minimum_size = Vector2(0,90)
	stat.add_child(topology)
	market_ticker = UI.label(stat,"",14,UI.MUTED)
	digital_ticker = UI.label(stat,"",14,UI.MUTED)
	var alerts := _popup("alerts","已知告警",380,true)
	var alert_scroll := ScrollContainer.new()
	alert_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	alert_scroll.custom_minimum_size = Vector2(0,250)
	alerts.add_child(alert_scroll)
	alerts_box = UI.column(alert_scroll,8)
	alerts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice_label = UI.label(self,"",14,UI.TEAL)
	notice_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	notice_label.offset_left = -300
	notice_label.offset_right = 300
	notice_label.offset_top = 22
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.add_theme_stylebox_override("normal",UI.style(Color("102833f5"),6))
	notice_label.hide()
	tooltip_label = UI.label(self,"",14)
	tooltip_label.add_theme_stylebox_override("normal",UI.style(Color("102833f5"),6))
	tooltip_label.hide()

func toggle_popup(key: String) -> void:
	var opening: bool = not popups[key].visible
	close_popups()
	if opening:
		popups[key].show()
		popup_order.append(key)

func close_popups() -> void:
	for p in popups.values(): p.hide()
	popup_order.clear()

func close_tray() -> void:
	tray.hide()
	active_category = ""
	for b in category_buttons.values(): b.button_pressed = false
	refresh_context()

func close_top() -> bool:
	if not popup_order.is_empty(): close_popups(); return true
	if tray.visible: close_tray(); return true
	return false

func toggle_category(category: String) -> void:
	if tray.visible and category == active_category:
		close_tray()
		return
	close_popups()
	active_category = category
	tray_title.text = {"power":"发电设施","grid":"输配电设施","storage":"储能设施","city":"城市与配套","digital":"数字电网设施"}.get(category,"设施目录")
	for kind in build_buttons: build_buttons[kind].visible = category_for(kind) == category
	for key in category_buttons: category_buttons[key].button_pressed = key == category
	tray.show()
	refresh_context()

func refresh_context() -> void:
	for key in tool_buttons: tool_buttons[key].button_pressed = game.tool == key
	for key in overlay_buttons: overlay_buttons[key].button_pressed = game.overlay == key
	for key in build_buttons:
		var available: Dictionary = game.sim.evolution.can_build(key)
		build_buttons[key].disabled = not available.ok or game.sim.cash < game.sim.catalog[key].price
		build_buttons[key].button_pressed = game.tool == "build" and game.build_kind == key
		build_buttons[key].tooltip_text = str(game.sim.catalog[key].description)+("\n"+str(available.get("message","")) if not available.ok else "")
	for key in speed_buttons: speed_buttons[key].button_pressed = game.speed == key
	pause_button.button_pressed = game.speed == 0
	get_node("ToolHint").visible = game.tool != "select"
	get_node("ToolHint").offset_top = -396 if tray.visible else -190
	get_node("ToolHint").offset_bottom = -348 if tray.visible else -144
	inspector.visible = not tray.visible and game.tool == "select" and (game.selected_id >= 0 or game.selected_line >= 0 or game.selected_comm_line >= 0)
	# The objective is compact; its full explanation is available in the drawer.
	var completed := 0
	var current := "全部委托完成 · 自由运营"
	for task in game.sim.objectives:
		if task.get("done",false): completed += 1
		elif current == "全部委托完成 · 自由运营": current = str(task.get("title",task.get("name","运营委托")))
	objective.text = "%d/%d  ·  %s  ›" % [completed,game.sim.objectives.size(),current]
	var totals: Dictionary = game.sim.totals
	statistics.text = "设施 %d  ·  线路 %d  ·  作业队 %d/2\n累计可靠率 %.1f%%  ·  碳排 %.1f t/h" % [game.sim.buildings.size(),game.sim.lines.size(),totals.get("crews_busy",0),float(totals.get("reliability_lifetime",1))*100,totals.get("carbon",0)]
	_refresh_alerts()

func _refresh_alerts() -> void:
	var alerts: Array[String] = []
	if float(game.sim.totals.get("reliability",1)) < .98: alerts.append("供电不足 · 检查供需与联网状态")
	if game.sim.storm_active: alerts.append("风暴持续中 · 关注已确认故障与备用线路")
	elif float(game.sim.totals.get("storm_in",99)) <= 1: alerts.append("风暴即将到来 · 检查备用容量")
	for line in game.sim.lines:
		var observation: Dictionary = game.sim.line_observation(int(line.id))
		if observation.get("visibility","") in ["verified","patrol"] and observation.get("fault_known",false) and observation.get("fault",false): alerts.append("线路 %02d · 故障已确认" % line.id)
	for incident in game.sim.digital.incidents:
		if incident.get("detected",false) and incident.get("status","") == "active": alerts.append("设备 %02d · 已检测网络事件" % incident.get("target_id",0))
	alert_button.text = "告警 %d" % alerts.size()
	alert_button.add_theme_color_override("font_color",UI.AMBER if not alerts.is_empty() else UI.MUTED)
	var signature := "\n".join(alerts)
	if alerts_box.get_meta("signature","__") == signature: return
	alerts_box.set_meta("signature",signature)
	for child in alerts_box.get_children(): child.queue_free()
	if alerts.is_empty(): UI.label(alerts_box,"当前没有已知异常",14,UI.TEAL)
	for alert in alerts:
		var l := UI.label(alerts_box,alert,14,UI.AMBER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.button(alerts_box,"查看数字电网与处置",func(): center_requested.emit("network"))
