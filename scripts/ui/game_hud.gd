extends Control
## Map-first HUD. Lightweight popovers never pause or mutate the simulation.
const UI = preload("res://scripts/ui/ui_kit.gd")
const Chart = preload("res://scripts/ui/power_chart.gd")
const OperatorDock = preload("res://scripts/ui/operator_dock.gd")
const Presenter = preload("res://scripts/ui/grid_presenter.gd")
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
var center_buttons: Dictionary = {}
var city_name: Label
var storm_button: Button
var overlay_buttons: Dictionary = {}
var popups: Dictionary = {}
var popup_titles: Dictionary = {}
var popup_order: Array[String] = []
var popup_scrolls: Dictionary = {}
var active_category := ""
var tray: PanelContainer
var tray_title: Label
var tray_flow: HFlowContainer
var inspector: PanelContainer
var inspector_box: VBoxContainer
var inspector_scroll: ScrollContainer
var objective: Button
var mission_box: VBoxContainer
var mission_scroll: ScrollContainer
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
var operator_dock: Control
var dock_panel: PanelContainer
var status_panel: PanelContainer
var time_status: Label
var workspace_title: Label
var pin_button: Button
var dock_flow: HFlowContainer
var dock_scroll: ScrollContainer
var status_flow: HFlowContainer
var onboarding_panel: PanelContainer
var onboarding_label: Label
var city_panel: PanelContainer
var navigation_panel: PanelContainer
var layer_panel: PanelContainer
var supply_column: VBoxContainer
var cash_column: VBoxContainer
var clock_column: VBoxContainer
var supply_gauge: Control
var deficit_label: Label
var focus_panel: PanelContainer
var focus_title: Label
var focus_evidence: Label
var focus_action: Button
var focus_icon: TextureRect
var build_launcher: Button
var _focus_item: Dictionary = {}

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
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	p.add_child(scroll)
	popup_scrolls[key]=scroll
	var v := UI.column(scroll,10)
	v.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var heading := UI.row(v)
	popup_titles[key] = UI.label(heading,title,18)
	UI.spacer(heading)
	UI.button(heading,"×",func(): toggle_popup(key),Vector2(34,34))
	popups[key] = p
	p.hide()
	return v

func _build() -> void:
	# Small city identity and current objective; everything else is requested.
	var city := _panel(self)
	city_panel=city
	city.position = Vector2(16,16)
	var cv := UI.column(city,3)
	var heading := UI.row(cv,8)
	UI.label(heading,"ϟ",26,UI.TEAL)
	city_name = UI.label(heading,"青屿湾",20)
	UI.label(heading,"潮汐电网",14,UI.MUTED)
	objective = UI.button(cv,"当前委托",func(): toggle_popup("missions"),Vector2(292,34))
	var top := _panel(self)
	navigation_panel=top
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
	layer_panel=layers
	layers.position = Vector2(16,156)
	var lv := UI.column(layers,6)
	UI.button(lv,"图层",func(): toggle_popup("layers"))
	UI.button(lv,"统计",func(): toggle_popup("stats"))
	UI.button(lv,"诊断",func(): operator_dock.show_page("diagnosis"))
	UI.button(lv,"检索",func(): operator_dock.open_search())
	# A single context drawer, above the always-visible bottom controls.
	inspector = _panel(self)
	inspector.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	inspector.offset_left = -364
	inspector.offset_right = -16
	inspector.offset_top = 72
	inspector.offset_bottom = -154
	var iv := UI.column(inspector,6)
	var ih := UI.row(iv)
	workspace_title=UI.label(ih,"对象详情",14,UI.MUTED)
	UI.spacer(ih)
	pin_button = UI.button(ih,"固定",func(): operator_dock.pinned=not operator_dock.pinned; operator_dock.opened=true; refresh_context(),Vector2(48,34),true)
	UI.button(ih,"×",func(): operator_dock.close(); action_requested.emit("clear_selection"),Vector2(34,34))
	inspector_scroll = ScrollContainer.new()
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	iv.add_child(inspector_scroll)
	inspector_box = UI.column(inspector_scroll,8)
	inspector_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	operator_dock = OperatorDock.new()
	iv.add_child(operator_dock)
	iv.move_child(operator_dock,1)
	operator_dock.setup(game,self)
	inspector.hide()
	# Bottom tool dock.
	var dock := _panel(self)
	dock_panel = dock
	dock.add_theme_stylebox_override("panel",UI.style(Color("112b35f5"),8,Color("3c5961"),8))
	dock.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	dock.offset_left = -540
	dock.offset_right = 540
	dock.offset_top = -124
	dock.offset_bottom = -64
	dock_scroll=ScrollContainer.new()
	dock_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	dock_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	dock_scroll.follow_focus=true
	dock.add_child(dock_scroll)
	var dr := HFlowContainer.new()
	dr.custom_minimum_size.x=1060
	dock_scroll.add_child(dr)
	dock_flow = dr
	dr.add_theme_constant_override("h_separation",5)
	dr.add_theme_constant_override("v_separation",5)
	dr.alignment = FlowContainer.ALIGNMENT_CENTER
	for spec in [["select","选择"],["line","接线"],["repair","抢修"],["datalink","通信"]]:
		var key: String = spec[0]
		tool_buttons[key] = _dock_button(dr,key,spec[1],func(): tool_requested.emit(key))
		tool_buttons[key].tooltip_text = "%s  [%d]" % [spec[1],tool_buttons.size()]
	dr.add_child(VSeparator.new())
	build_launcher=_dock_button(dr,"power","建造",func(): toggle_category(active_category if not active_category.is_empty() else "power"))
	for spec in [["power","发电"],["grid","输电"],["storage","储能"],["city","城市"],["digital","数字"]]:
		var key: String = spec[0]
		category_buttons[key] = _dock_button(dr,key,spec[1],func(): toggle_category(key))
	dr.add_child(VSeparator.new())
	for spec in [["market","经营 M"],["network","运维 N"],["planning","发展 T"]]:
		var key: String = spec[0]
		var entry := _dock_button(dr,key,spec[1],func(): center_requested.emit(key))
		entry.toggle_mode = false
		center_buttons[key] = entry
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
	var categories := HFlowContainer.new()
	categories.add_theme_constant_override("h_separation",6)
	tv.add_child(categories)
	for button in category_buttons.values(): button.reparent(categories)
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
		var ability: String = "%.0f MW" % float(spec.get("capacity",0))
		if spec.has("energy"): ability += " / %.0f MWh" % float(spec.energy)
		elif float(spec.get("demand",0))>0: ability="负荷 %.1f MW" % float(spec.demand)
		var b := UI.button(tray_flow,"%s\n¥%s · %s" % [spec.name,game._compact(spec.price),ability],func(): build_requested.emit(kind),Vector2(185,68),true)
		var icon_path := "res://assets/icons/%s.png" % kind
		if ResourceLoader.exists(icon_path): b.icon = load(icon_path); b.expand_icon = true; b.add_theme_constant_override("icon_max_width",54)
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
	# Three operating groups stay visible while the miniature city remains central.
	var status := _panel(self)
	status_panel = status
	status.add_theme_stylebox_override("panel",UI.style(Color("0d2935f5"),9,Color("4b7078"),10,true))
	status.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	status.offset_left = 16
	status.offset_right = -16
	status.offset_top = 12
	status.offset_bottom = 124
	var sr := HFlowContainer.new()
	status_flow=sr
	sr.add_theme_constant_override("h_separation",18)
	sr.add_theme_constant_override("v_separation",3)
	status.add_child(sr)
	supply_column=UI.column(sr,2)
	var supply_heading := UI.row(supply_column,10)
	values.reliability = UI.label(supply_heading,"供电 100%",30,UI.TEAL)
	values.reliability.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	deficit_label=UI.label(supply_heading,"余量充足",18,UI.TEAL)
	supply_gauge=UI.metric(supply_column,"",0,1)
	supply_gauge.custom_minimum_size.y=14
	supply_gauge.show_value=false
	supply_gauge.compact=true
	supply_gauge.hatch_remainder=true
	# The gauge's native track is moved up when used without a heading.
	supply_gauge.set_meta("headerless",true)
	values.supply = UI.button(supply_column,"已供 0 / 需求 0 MW",func(): operator_dock.show_page("diagnosis"),Vector2(0,28))
	values.supply.add_theme_stylebox_override("normal",UI.style(Color.TRANSPARENT,0,Color.TRANSPARENT,0))
	values.supply.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	values.supply.alignment=HORIZONTAL_ALIGNMENT_LEFT
	cash_column=UI.column(sr,2)
	UI.label(cash_column,"可用资金",14,UI.MUTED)
	values.cash = UI.label(cash_column,"¥180,000",26)
	values.balance = UI.label(cash_column,"+ ¥0/h",18,UI.TEAL)
	clock_column=UI.column(sr,3)
	var date := UI.row(clock_column,6)
	time_label = UI.label(date,"第 1 天 08:00",14)
	weather_label = UI.label(date,"晴朗",14,UI.MUTED)
	var time_controls := UI.row(clock_column,4)
	pause_button = UI.button(time_controls,"Ⅱ",func(): action_requested.emit("pause"),Vector2(34,34),true)
	for speed in [1,3,8]:
		var value: int = speed
		speed_buttons[value] = UI.button(time_controls,"%d×" % value,func(): action_requested.emit("speed_%d" % value),Vector2(35,34),true)
	time_status = UI.label(clock_column,"运行 1×",14,UI.MUTED)
	values.supply.tooltip_text = "当前已供电 / 当前需求（MW）"
	values.reliability.tooltip_text = "当前供电可靠率"
	values.cash.tooltip_text = "可用建设与运营资金"
	values.balance.tooltip_text = "每游戏小时净收益"
	for key in ["supply","reliability","cash","balance"]: values[key].mouse_filter = Control.MOUSE_FILTER_PASS
	_build_focus_card()
	# Full objectives and actions are in a non-modal popover.
	var tasks := _popup("missions","运营委托",350)
	mission_scroll=ScrollContainer.new()
	mission_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	mission_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	mission_scroll.custom_minimum_size=Vector2(0,250)
	tasks.add_child(mission_scroll)
	mission_box = UI.column(mission_scroll,8)
	mission_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	research_button = UI.button(tasks,"遥测研究",func(): action_requested.emit("research"))
	response_button = UI.button(tasks,"需求响应",func(): action_requested.emit("response"))
	storm_button = UI.button(tasks,"风暴演练",func(): action_requested.emit("storm"))
	var log := _popup("log","调度日志",400,true)
	events_label = RichTextLabel.new()
	events_label.bbcode_enabled = true
	events_label.custom_minimum_size = Vector2(0,280)
	events_label.add_theme_font_size_override("normal_font_size",14)
	log.add_child(events_label)
	var menu := _popup("menu","游戏菜单",250,true)
	for spec in [["save","保存游戏  F5"],["load","读取游戏  F9"],["settings","操作与显示设置"],["workspace","设施检索  Ctrl+F"],["jobs","操作队列与回执"],["working_area","镜头：工作区"],["full_map","镜头：全图"],["campaign","历史战役与章节"],["help","调度员手册  H"]]:
		var key: String = spec[0]
		UI.button(menu,spec[1],func(): close_popups(); action_requested.emit(key)).set_meta("menu_action",key)
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
	chart.custom_minimum_size = Vector2(0,155)
	stat.add_child(chart)
	UI.label(stat,"电力拓扑",14)
	topology = Chart.new()
	topology.mode = "topology"
	topology.sim = game.sim
	topology.custom_minimum_size = Vector2(0,125)
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
	onboarding_panel = _panel(self)
	onboarding_panel.position = Vector2(102,156)
	onboarding_panel.custom_minimum_size = Vector2(310,0)
	var lesson := UI.column(onboarding_panel,8)
	UI.label(lesson,"首次接网 · 可跳过",18,UI.TEAL)
	onboarding_label = UI.label(lesson,"",14)
	onboarding_label.custom_minimum_size.x=290
	onboarding_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var lesson_actions := UI.row(lesson)
	UI.button(lesson_actions,"定位变电站",func(): game.focus_target("building",2))
	UI.button(lesson_actions,"接线工具",func(): tool_requested.emit("line"))
	UI.button(lesson_actions,"跳过",func(): game.onboarding_skipped=true; onboarding_panel.hide())
	onboarding_panel.hide()
	resized.connect(layout_workspace)
	status_flow.minimum_size_changed.connect(func(): layout_workspace.call_deferred())
	layout_workspace.call_deferred()

func _build_focus_card() -> void:
	focus_panel=_panel(self)
	focus_panel.name="CurrentPriority"
	focus_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	focus_panel.offset_left=-298
	focus_panel.offset_right=-16
	focus_panel.offset_top=190
	var body := UI.column(focus_panel,8)
	UI.label(body,"◎ 当前重点",14,UI.MUTED)
	var heading := UI.row(body,8)
	focus_icon=TextureRect.new()
	focus_icon.custom_minimum_size=Vector2(54,54)
	focus_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	focus_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heading.add_child(focus_icon)
	focus_title=UI.label(heading,"检查供电与备用",18)
	focus_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	focus_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	focus_evidence=UI.label(body,"",14,UI.MUTED)
	focus_evidence.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	focus_action=UI.action(UI.button(body,"打开诊断",_act_on_focus,Vector2(0,40)))

func _act_on_focus() -> void:
	if int(_focus_item.get("target_id",-1))>=0:
		game.focus_target(str(_focus_item.get("target_type","building")),int(_focus_item.target_id))
		if _focus_item.get("action","")=="connect":
			game._set_tool("line")
			game.connection_start=int(_focus_item.target_id)
			game._update_hud()
	else: operator_dock.show_page("diagnosis")

func refresh_visuals() -> void:
	if supply_gauge==null or game.sim==null: return
	var snapshot: Dictionary=Presenter.operating_snapshot(game.sim)
	var demand: float=float(snapshot.demand)
	var served: float=float(snapshot.served)
	var deficit: float=float(snapshot.deficit)
	values.reliability.text="供电 %.0f%%" % (float(snapshot.reliability)*100) if demand>.000001 else "暂无用电需求"
	values.reliability.add_theme_color_override("font_color",UI.TEXT)
	deficit_label.text="缺口 %.1f MW" % deficit if deficit>.01 else "供电充足"
	deficit_label.add_theme_color_override("font_color",UI.RED if deficit>.01 else UI.TEAL)
	supply_gauge.configure("",served,maxf(demand,.001),"MW",UI.TEAL,true)
	supply_gauge.hatch_remainder=deficit>.01
	supply_gauge.remainder_color=Color("392d36") if deficit>.01 else Color("28434d")
	var data: Dictionary=Presenter.diagnosis(game.sim)
	var causes: Array=data.get("causes",[])
	_focus_item=causes[0] if not causes.is_empty() else {}
	if _focus_item.is_empty():
		var alerts: Array=Presenter.alerts(game.sim)
		if not alerts.is_empty(): _focus_item=alerts[0]
	focus_title.text=str(_focus_item.get("title","供电满足需求")).replace(" · 未接电力线路","未接网")
	focus_evidence.text=str(_focus_item.get("source","继续规划扩张与备用"))
	if _focus_item.get("action","")=="connect": focus_evidence.text="配电站 → 待接网设施"
	var target: Dictionary=game.sim.get_building(int(_focus_item.get("target_id",-1))) if str(_focus_item.get("target_type","")) in ["building","facility"] else {}
	var icon_path: String="res://assets/icons/%s.png" % target.get("kind","substation")
	focus_icon.texture=load(icon_path) if ResourceLoader.exists(icon_path) else null
	focus_action.text=str({"connect":"开始接线","repair":"定位并安排抢修","inspect":"定位并检查","observe":"核实运行状态","security":"检查已检测事件"}.get(str(_focus_item.get("action","")),"查看供电诊断"))
	focus_panel.visible=not game._modal_open() and not inspector.visible and not tray.visible and size.y>=620 and not _focus_item.is_empty()
	layout_workspace()

func toggle_popup(key: String) -> void:
	if key=="alerts":
		close_popups()
		operator_dock.show_page("diagnosis")
		return
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
	if inspector.visible and not operator_dock.pinned and game.tool=="select":
		operator_dock.close()
		action_requested.emit("clear_selection")
		return true
	return false

func toggle_category(category: String) -> void:
	if tray.visible and category == active_category:
		close_tray()
		return
	close_popups()
	active_category = category
	tray_title.text = {"power":"发电设施","grid":"输配电设施","storage":"储能设施","city":"城市与配套","digital":"数字电网设施"}.get(category,"设施目录")
	for kind in build_buttons: build_buttons[kind].visible = category_for(kind) == category and (not game._campaign_active() or game.sim.can_build(kind).ok)
	for key in category_buttons: category_buttons[key].button_pressed = key == category
	tray.show()
	refresh_context()

func refresh_context() -> void:
	var campaign_active: bool = game._campaign_active()
	city_name.text = str(game.sim.campaign.chapter().get("place","历史现场")) if campaign_active else "青屿湾"
	city_name.add_theme_font_size_override("font_size",16 if campaign_active else 20)
	city_name.custom_minimum_size.x = 150 if campaign_active else 80
	city_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	popup_titles.missions.text="本关任务" if campaign_active else "运营委托"
	mission_scroll.custom_minimum_size.y=350 if campaign_active else 250
	for category in category_buttons:
		var available_category := false
		for kind in build_buttons:
			if category_for(kind)==category and game.sim.can_build(kind).ok: available_category=true; break
		category_buttons[category].disabled=not available_category
	tool_buttons.datalink.disabled = not game.sim.feature_enabled("digital")
	tool_buttons.datalink.visible = game.tool=="datalink" or game.overlay=="comm"
	category_buttons.digital.disabled = not game.sim.feature_enabled("digital")
	for key in center_buttons:
		var feature: String = {"market":"market","network":"digital","planning":"research"}[key]
		center_buttons[key].disabled = not game.sim.feature_enabled(feature)
	research_button.visible = game.sim.feature_enabled("digital")
	response_button.visible = game.sim.feature_enabled("demand_response")
	storm_button.visible = game.sim.feature_enabled("storm")
	if game.sim.management.state.active and not game.sim.management.state.first_storm_prepared: storm_button.hide()
	for key in tool_buttons: tool_buttons[key].button_pressed = game.tool == key
	build_launcher.button_pressed=tray.visible
	for key in tool_buttons: tool_buttons[key].tooltip_text=str({"select":"选择","line":"电缆接线","repair":"现场抢修","datalink":"通信布线"}[key])+"  ["+game.preferences.binding_label(key)+"]"
	for key in center_buttons: center_buttons[key].text=str({"market":"经营","network":"运维","planning":"发展"}[key])+" "+game.preferences.binding_label(key)
	for button in popups.menu.find_children("*","Button",true,false):
		var action: String=str(button.get_meta("menu_action",""))
		if action in ["save","load","help"]: button.text=str({"save":"保存游戏","load":"读取游戏","help":"调度员手册"}[action])+"  "+game.preferences.binding_label(action)
	for key in overlay_buttons: overlay_buttons[key].button_pressed = game.overlay == key
	for key in build_buttons:
		var available: Dictionary = game.sim.can_build(key)
		build_buttons[key].disabled = not available.ok or game.sim.cash < game.sim.catalog[key].price
		build_buttons[key].button_pressed = game.tool == "build" and game.build_kind == key
		build_buttons[key].tooltip_text = str(game.sim.catalog[key].description)+("\n"+str(available.get("message","")) if not available.ok else "")
	for key in speed_buttons: speed_buttons[key].button_pressed = game.speed == key
	pause_button.button_pressed = game.speed == 0
	pin_button.button_pressed = operator_dock.pinned
	workspace_title.text=str({"object":"对象详情","diagnosis":"供电诊断","watch":"检索与关注","jobs":"队列与执行回执"}.get(operator_dock.page,"调度工作区"))
	get_node("ToolHint").visible = game.tool != "select"
	get_node("ToolHint").offset_top = -396 if tray.visible else -190
	get_node("ToolHint").offset_bottom = -348 if tray.visible else -144
	inspector.visible = not tray.visible and ((game.tool == "select" and (game.selected_id >= 0 or game.selected_line >= 0 or game.selected_comm_line >= 0)) or operator_dock.opened)
	operator_dock._sync_visibility()
	# The objective is compact; its full explanation is available in the drawer.
	var completed := 0
	var current := "全部委托完成 · 自由运营"
	for task in game.sim.objectives:
		if task.get("done",false): completed += 1
		elif current == "全部委托完成 · 自由运营": current = str(task.get("title",task.get("name","运营委托")))
	objective.text = "%d/%d  ·  %s  ›" % [completed,game.sim.objectives.size(),current]
	if game.sim.management.state.active:
		var stage: Dictionary=game.sim.management_status()
		objective.text="%d/5 · %s  ›" % [mini(5,int(stage.get("stage",0))+1),stage.get("title","经营路线")]
	if campaign_active:
		var step: Dictionary=game.sim.campaign.current_step()
		objective.text = "%02d  ·  %s  ›" % [game.sim.campaign.chapter_id,step.get("title","本关报告")]

	var totals: Dictionary = game.sim.totals
	statistics.text = "设施 %d  ·  线路 %d  ·  作业队 %d/2\n累计可靠率 %.1f%%  ·  碳排 %.1f t/h" % [game.sim.buildings.size(),game.sim.lines.size(),totals.get("crews_busy",0),float(totals.get("reliability_lifetime",1))*100,totals.get("carbon",0)]
	_refresh_alerts()
	refresh_visuals()
	layout_workspace()

func _refresh_alerts() -> void:
	var alerts: Array = Presenter.alerts(game.sim)
	alert_button.text = "告警 %d" % alerts.size()
	alert_button.add_theme_color_override("font_color",UI.AMBER if not alerts.is_empty() else UI.MUTED)
	var signature := str(alerts)
	if alerts_box.get_meta("signature","__") == signature: return
	alerts_box.set_meta("signature",signature)
	for child in alerts_box.get_children(): child.queue_free()
	if alerts.is_empty(): UI.label(alerts_box,"当前没有已知异常",14,UI.TEAL)
	for alert in alerts:
		var l := UI.label(alerts_box,str(alert.title),14,UI.AMBER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	operator_dock.refresh()

func layout_workspace() -> void:
	if dock_panel == null: return
	var narrow: bool = size.x < 1120
	var compact: bool=size.y<620 or size.x<1000
	var available: float=maxf(560,size.x-88)
	supply_column.custom_minimum_size.x=available*.43
	cash_column.custom_minimum_size.x=available*.21
	clock_column.custom_minimum_size.x=available*.36
	values.reliability.add_theme_font_size_override("font_size",24 if compact else 30)
	deficit_label.add_theme_font_size_override("font_size",14 if compact else 18)
	values.cash.add_theme_font_size_override("font_size",22 if compact else 26)
	values.balance.add_theme_font_size_override("font_size",14 if compact else 18)
	var rail_height: float=maxf(100,status_flow.get_combined_minimum_size().y+20)
	status_panel.offset_top=12
	status_panel.offset_bottom=12+rail_height
	city_panel.position=Vector2(16,rail_height+24)
	city_panel.custom_minimum_size.x=0
	city_panel.size.x=minf(320,size.x*.42)
	objective.custom_minimum_size.x=minf(276,size.x*.39)
	objective.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	navigation_panel.offset_top=rail_height+24
	navigation_panel.offset_bottom=rail_height+70
	navigation_panel.visible=not (compact and inspector.visible)
	layer_panel.position=Vector2(16,rail_height+128)
	layer_panel.visible=not compact
	var dock_height: float = 62 if narrow else 66
	dock_panel.offset_left=-minf(880,size.x-32)/2
	dock_panel.offset_right=minf(880,size.x-32)/2
	dock_panel.offset_bottom=-12
	dock_panel.offset_top=-12-dock_height
	dock_flow.custom_minimum_size.x=maxf(680,minf(860,size.x-52))
	for button in tool_buttons.values(): button.custom_minimum_size.x=52 if narrow else 70
	for button in category_buttons.values(): button.custom_minimum_size.x=52 if narrow else 70
	for button in center_buttons.values(): button.custom_minimum_size.x=60 if narrow else 80
	var bottom: float = dock_height+24
	inspector.offset_bottom=-bottom
	inspector.offset_top=rail_height+(24 if compact else 82)
	inspector.offset_left=-minf(364,size.x*.45)
	focus_panel.offset_top=rail_height+82
	focus_panel.offset_left=-minf(294,size.x*.32)
	focus_panel.visible=focus_panel.visible and not compact and not inspector.visible and not tray.visible
	onboarding_panel.position=Vector2(100 if not compact else 16,rail_height+128)
	onboarding_panel.custom_minimum_size.x=minf(310,size.x*.44)
	tray.offset_left=100 if not narrow else 16
	tray.offset_right=-100 if not narrow else -16
	tray.offset_bottom=-bottom
	tray.offset_top=-minf(bottom+244,size.y-20)
	var hint: Control = get_node("ToolHint")
	hint.offset_left=-minf(960,size.x-32)/2
	hint.offset_right=minf(960,size.x-32)/2
	hint.offset_top=-bottom-56 if not tray.visible else tray.offset_top-54
	hint.offset_bottom=hint.offset_top+46
	if tray.visible and size.y<650: hint.hide()
	for key in popups:
		var popup: Control=popups[key]
		popup.custom_minimum_size.x=0
		popup.size.x=minf(popup.size.x,size.x-32)
		popup.position.y=rail_height+82
		if key=="stats":
			chart.custom_minimum_size.y=110 if size.y<650 else 155
			topology.custom_minimum_size.y=100 if size.y<650 else 125
		var content: Control=popup_scrolls[key].get_child(0)
		popup.size.y=minf(content.get_combined_minimum_size().y+24,maxf(100,size.y-popup.position.y-18))
