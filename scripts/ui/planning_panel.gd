extends Control
## Planning is paused; only explicit commands and Advance change simulation state.
const Evolution = preload("res://scripts/sim/grid_evolution.gd")
const RegionMap = preload("res://scripts/ui/region_map.gd")
const Shell = preload("res://scripts/ui/management_shell.gd")
const TEAL := Color("77dbc0")
const BLUE := Color("81c9ee")
const CREAM := Color("f2eddb")
const MUTED := Color("95b0b6")
const ORANGE := Color("efbb7d")

var game: Node
var tabs: TabContainer
var message_label: Label
var project_label: Label
var scenario_label: Label
var funds_label: Label
var technology_buttons: Dictionary = {}
var construction_buttons: Dictionary = {}
var facility_picker: OptionButton
var selected_facility := 1
var facility_info: Label
var enabled_input: CheckButton
var dispatch_input: SpinBox
var cooling_input: OptionButton
var storage_input: OptionButton
var reserve_input: SpinBox
var peak_input: SpinBox
var release_input: SpinBox
var protection_input: SpinBox
var flexible_input: CheckButton
var boost_input: CheckButton
var controls: Dictionary = {}
var region_map: Control
var region_info: Label
var expand_button: Button
var city_box: VBoxContainer
var city_labels: Dictionary = {}
var challenge_box: VBoxContainer
var challenge_labels: Dictionary = {}
var _asset_signature := ""
var _city_signature := ""
var selected_era := 0
var selected_technology := ""
var era_buttons: Array[Button] = []
var technology_cards: Dictionary = {}
var technology_detail: Label
var technology_title: Label
var technology_status: Label
var technology_action: Button
var era_description: Label
var facility_modes: TabContainer
var catalog_category: OptionButton
var catalog_cards: Dictionary = {}
var catalog_grid: GridContainer
var operating_grid: GridContainer
var scenario_actions: VBoxContainer
var city_picker: OptionButton
var selected_city := -1
var city_cards: Dictionary = {}
var current_goal: Label
var city_heading: HBoxContainer
var region_work: BoxContainer

func setup(owner_game: Node) -> void:
	game = owner_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	hide()

func open() -> void:
	game._prepare_center(self)
	refresh(true)
	show()

func close() -> void:
	hide()
	game._update_hud()
	game._update_inspector()

func select_facility(id: int) -> void:
	selected_facility = id
	tabs.current_tab = 1
	facility_modes.current_tab = 0
	refresh(true)

func _build() -> void:
	var body: VBoxContainer = Shell.build(self,"科技与区域规划","推进 1 小时",_advance,close)
	var metrics: HBoxContainer = game._row(body,12)
	funds_label = _text(metrics,"",CREAM,15)
	funds_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	project_label = _text(metrics,"",TEAL,15)
	project_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size",16)
	tabs.add_theme_color_override("font_selected_color",BLUE)
	tabs.add_theme_color_override("font_unselected_color",MUTED)
	tabs.add_theme_stylebox_override("panel",game._style(Color("153440"),10))
	tabs.add_theme_stylebox_override("tab_selected",game._style(Color("234954"),8))
	tabs.add_theme_stylebox_override("tab_unselected",game._style(Color("102b37"),8))
	body.add_child(tabs)
	_build_technologies()
	_build_facilities()
	_build_region()
	message_label = _text(body,"研究解锁能力；配套、位置与调度决定效果。",MUTED,14)
	resized.connect(_adapt_columns)
	_adapt_columns()

func _text(parent: Node, caption: String, color: Color=MUTED, font_size: int=13) -> Label:
	var result: Label = game._label(parent,caption,font_size,color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result

func _tab(caption: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = caption
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var body: VBoxContainer = game._column(scroll,14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return body

func _card(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",game._style(Color("1b3b48"),10))
	parent.add_child(panel)
	return game._column(panel,7)

func _build_technologies() -> void:
	var body := _tab("代际科技树")
	body.add_theme_constant_override("separation",8)
	var scenario_row: HBoxContainer = game._row(body,12)
	scenario_label = _text(scenario_row,"",MUTED,14)
	game._button(scenario_row,"场景选项",func(): scenario_actions.visible=not scenario_actions.visible,Vector2(96,34))
	scenario_actions = game._column(body,8)
	_text(scenario_actions,"切换开局将重新建立地图；当前进度会先自动备份。",ORANGE,14)
	game._button(scenario_actions,"从爱迪生时代重新开局（自动备份）",func(): game.start_heritage_game(),Vector2(0,36))
	game._button(scenario_actions,"恢复切换历史开局前的进度",func(): game._load("user://before_heritage.json"),Vector2(0,36))
	scenario_actions.hide()
	var era_navigation := HFlowContainer.new()
	era_navigation.add_theme_constant_override("h_separation",6)
	era_navigation.add_theme_constant_override("v_separation",6)
	body.add_child(era_navigation)
	for era_index in Evolution.ERAS.size():
		var era: Dictionary = Evolution.ERAS[era_index]
		var index := era_index
		var button: Button = game._button(era_navigation,"%02d  %s" % [era_index+1,era.name],func(): _select_era(index),Vector2(0,38),true)
		button.tooltip_text = str(era.years)
		era_buttons.append(button)
	era_description = _text(body,"",MUTED,14)
	var work: HBoxContainer = game._row(body,16)
	var technology_list: VBoxContainer = game._column(work,4)
	technology_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	technology_list.size_flags_stretch_ratio = 0.85
	for tech_id in Evolution.TECHNOLOGIES:
		var tech: Dictionary = Evolution.TECHNOLOGIES[tech_id]
		var id: String = tech_id
		var button: Button = game._button(technology_list,str(tech.name),func(): _select_technology(id),Vector2(0,52),true)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = str(tech.name)+" · "+str(tech.branch)
		technology_buttons[id] = button
		technology_cards[id] = button
	var detail := _card(work)
	detail.size_flags_stretch_ratio = 1.15
	detail.get_parent().size_flags_stretch_ratio = 1.15
	technology_title = _text(detail,"",CREAM,23)
	technology_status = _text(detail,"",TEAL,14)
	technology_action = game._button(detail,"开展研究",_research_selected,Vector2(0,40))
	technology_detail = _text(detail,"",MUTED,15)
	_text(detail,"一次开展一项研究。支付费用后，推进游戏时间完成研发。",MUTED,14)
	_select_era(0)

func _select_era(index: int) -> void:
	selected_era = index
	for i in era_buttons.size():
		era_buttons[i].set_pressed_no_signal(i==selected_era)
	var era: Dictionary = Evolution.ERAS[selected_era]
	era_description.text = str(era.years)+"  ·  "+str(era.description)
	for id in technology_cards:
		technology_cards[id].visible = int(Evolution.TECHNOLOGIES[id].era)==selected_era
	if selected_technology.is_empty() or int(Evolution.TECHNOLOGIES[selected_technology].era)!=selected_era:
		for id in Evolution.TECHNOLOGIES:
			if int(Evolution.TECHNOLOGIES[id].era)==selected_era:
				selected_technology = id
				break
	_refresh_technology_detail()

func _select_technology(id: String) -> void:
	selected_technology = id
	_refresh_technology_detail()

func _refresh_technology_detail() -> void:
	if selected_technology.is_empty():
		return
	var tech: Dictionary = Evolution.TECHNOLOGIES[selected_technology]
	var evolution: RefCounted = game.sim.evolution
	var complete: bool = selected_technology in evolution.unlocked
	var requirements: Array[String] = []
	var prerequisites := true
	for id in tech.requires:
		var unlocked: bool = id in evolution.unlocked
		requirements.append(("✓ " if unlocked else "○ ")+str(Evolution.TECHNOLOGIES[id].name))
		prerequisites = prerequisites and unlocked
	var unlocks: Array[String] = []
	for kind in tech.unlocks:
		if game.sim.catalog.has(kind):
			unlocks.append(str(game.sim.catalog[kind].name))
	technology_title.text = str(tech.name)
	technology_detail.text = "%s · %s\n%s\n\n前置 · %s" % [tech.branch,Evolution.ERAS[int(tech.era)].years,tech.description,"起点技术" if requirements.is_empty() else "、".join(requirements)]
	if not unlocks.is_empty():
		technology_detail.text += "\n解锁 · "+"、".join(unlocks)
	technology_action.text = "✓ 已掌握" if complete else ("研发中 · 剩余 %.1fh" % evolution.remaining_hours if str(evolution.project)==selected_technology else "研究 · ¥%s · %.1fh" % [game._number(float(tech.cost)),tech.hours])
	technology_action.disabled = complete or not prerequisites or not str(evolution.project).is_empty() or float(game.sim.cash)<float(tech.cost)
	technology_status.text = "能力已开放，仍需建设配套与调度。" if complete else ("先完成前置研究" if not prerequisites else ("已有研究正在进行" if not str(evolution.project).is_empty() else ("资金不足" if float(game.sim.cash)<float(tech.cost) else "可开展研究")))
	for id in technology_buttons:
		technology_buttons[id].set_pressed_no_signal(id==selected_technology)

func _research_selected() -> void:
	if not selected_technology.is_empty():
		_commit(game.sim.research_technology(selected_technology))

func _build_facilities() -> void:
	var body := _tab("设施与精细调度")
	facility_modes = TabContainer.new()
	facility_modes.use_hidden_tabs_for_min_size = false
	facility_modes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(facility_modes)
	var operating_body: VBoxContainer = game._column(facility_modes,12)
	operating_body.name = "设施运行"
	_text(operating_body,"选择设施，检查配套与运行边界。参数调整后，点击应用生效。",MUTED,14)
	facility_picker = OptionButton.new()
	facility_picker.custom_minimum_size = Vector2(0,38)
	facility_picker.add_theme_font_size_override("font_size",15)
	operating_body.add_child(facility_picker)
	facility_picker.item_selected.connect(func(_index: int): selected_facility=facility_picker.get_selected_id(); _refresh_facility(true))
	var operating := _card(operating_body)
	facility_info = _text(operating,"",CREAM,14)
	operating_grid = GridContainer.new()
	operating_grid.columns = 2
	operating_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	operating_grid.add_theme_constant_override("h_separation",28)
	operating_grid.add_theme_constant_override("v_separation",10)
	operating.add_child(operating_grid)
	enabled_input = CheckButton.new()
	enabled_input.text = "允许设施运行"
	operating_grid.add_child(enabled_input)
	controls.enabled = enabled_input
	dispatch_input = _number_control(operating_grid,"出力上限 %",0,100,5)
	cooling_input = _option_control(operating_grid,"冷却方式",["湿式 · 更强冷却，更多用水","干式 · 节水，但降低机组上限"])
	storage_input = _option_control(operating_grid,"储能运行策略",["自动平衡","保留电量","定时削峰"])
	reserve_input = _number_control(operating_grid,"保留荷电 %",0,90,5)
	peak_input = _number_control(operating_grid,"削峰起点（持续4小时）",0,23,1)
	release_input = _number_control(operating_grid,"水电生态下泄 %",10,60,5)
	protection_input = _number_control(operating_grid,"保护热裕度 %",80,120,5)
	flexible_input = CheckButton.new()
	flexible_input.text = "柔性热机档 · 更快爬坡，增加成本"
	operating_grid.add_child(flexible_input)
	controls.flexible = flexible_input
	boost_input = CheckButton.new()
	boost_input.text = "强化冷却档 · 更多容量，更高辅机成本"
	operating_grid.add_child(boost_input)
	controls.boost = boost_input
	game._button(operating,"应用设施设置",_apply_facility,Vector2(0,38))
	_text(operating,"核电需要同岛冷却与人才配套。启动、爬坡与储能策略需要时间及运行条件。",ORANGE,14)
	var catalog_body: VBoxContainer = game._column(facility_modes,12)
	catalog_body.name = "建造目录"
	var catalog_header: HBoxContainer = game._row(catalog_body,12)
	_text(catalog_header,"选择设施后，返回地图放置。",MUTED,14)
	catalog_category = OptionButton.new()
	catalog_category.custom_minimum_size = Vector2(160,38)
	for category in ["全部设施","发电设施","储能设施","输配电与配套","城市用电","数字通信"]:
		catalog_category.add_item(category)
	catalog_category.item_selected.connect(func(_index: int): _filter_catalog())
	catalog_header.add_child(catalog_category)
	catalog_grid = GridContainer.new()
	catalog_grid.columns = 2
	catalog_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_grid.add_theme_constant_override("h_separation",12)
	catalog_grid.add_theme_constant_override("v_separation",12)
	catalog_body.add_child(catalog_grid)
	for item in game.sim.catalog:
		var kind: String = item
		var spec: Dictionary = game.sim.catalog[kind]
		var card := _card(catalog_grid)
		catalog_cards[kind] = card.get_parent()
		_text(card,str(spec.name),CREAM,16)
		var era_index: int = game.sim.evolution.building_era(kind)
		_text(card,"用电侧 · 随城市发展" if kind in ["home","factory","hospital"] else "%s · %s" % [Evolution.ERAS[era_index].name,Evolution.ERAS[era_index].years],BLUE,11)
		_text(card,str(spec.description),MUTED,12)
		var design := "造价 ¥%s" % game._number(float(spec.price))
		if float(spec.capacity) > 0:
			design += " · %.0f MW" % float(spec.capacity)
		if float(spec.get("energy",0)) > 0:
			design += " / %.0f MWh" % float(spec.energy)
		_text(card,design,ORANGE,12)
		construction_buttons[kind] = game._button(card,"选择建造",func(): _choose_build(kind),Vector2(0,34))

func _filter_catalog() -> void:
	for kind in catalog_cards:
		var category := 3
		if kind in ["home","factory","hospital"]:
			category = 4
		elif kind in ["sensor","control","relay","soc"]:
			category = 5
		elif game.sim.evolution.is_storage(kind):
			category = 2
		elif game.sim.evolution.is_generator(kind) or kind in ["gas","solar","wind"]:
			category = 1
		catalog_cards[kind].visible = catalog_category.selected==0 or catalog_category.selected==category

func _adapt_columns() -> void:
	var narrow := size.x<1100
	if catalog_grid!=null:
		catalog_grid.columns = 1 if narrow else 2
	if operating_grid!=null:
		operating_grid.columns = 1 if narrow else 2
	if region_work!=null:
		region_work.vertical = narrow

func _number_control(parent: Node, caption: String, minimum: float, maximum: float, increment: float) -> SpinBox:
	var row: HBoxContainer = game._row(parent,8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := _text(row,caption,MUTED,12)
	label.custom_minimum_size.x = 110
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = increment
	input.custom_minimum_size = Vector2(110,36)
	row.add_child(input)
	controls[caption] = row
	return input

func _option_control(parent: Node, caption: String, options: Array) -> OptionButton:
	var column: VBoxContainer = game._column(parent,3)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text(column,caption,MUTED,12)
	var input := OptionButton.new()
	input.custom_minimum_size = Vector2(0,36)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for option in options:
		input.add_item(str(option))
	column.add_child(input)
	controls[caption] = column
	return input

func _build_region() -> void:
	var body := _tab("区域沙盘与自定目标")
	_text(body,"从一座海湾走向八城区域。供电、电价和污染影响城市成长。",MUTED,14)
	expand_button = game._button(body,"开启 48 × 48 区域沙盘 · 接管七座周边城市",func(): _commit(game.sim.expand_region()),Vector2(0,40))
	region_info = _text(body,"",TEAL,15)
	region_work = BoxContainer.new()
	region_work.add_theme_constant_override("separation",16)
	body.add_child(region_work)
	region_map = RegionMap.new()
	region_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	region_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	region_map.size_flags_stretch_ratio = 1.5
	region_map.city_selected.connect(func(id: int): close(); game.focus_city(id))
	region_work.add_child(region_map)
	var region_details: VBoxContainer = game._column(region_work,10)
	region_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	region_details.size_flags_stretch_ratio = 1.0
	city_heading = game._row(region_details,12)
	_text(city_heading,"城市档案",CREAM,18)
	city_picker = OptionButton.new()
	city_picker.custom_minimum_size = Vector2(180,38)
	city_picker.item_selected.connect(func(_index: int): selected_city=city_picker.get_selected_id(); _refresh_region())
	city_heading.add_child(city_picker)
	city_box = game._column(region_details,10)
	var goal_header: HBoxContainer = game._row(region_details,12)
	_text(goal_header,"长期运营目标",CREAM,18)
	game._button(goal_header,"选择目标",func(): challenge_box.visible=not challenge_box.visible,Vector2(96,34))
	current_goal = _text(region_details,"",TEAL,15)
	challenge_box = game._column(body,10)
	for challenge in game.sim.sandbox_goals():
		var card := _card(challenge_box)
		_text(card,str(challenge.name),CREAM,16)
		_text(card,str(challenge.description),MUTED,12)
		var id: String = challenge.id
		challenge_labels[id] = _text(card,"",TEAL,12)
		game._button(card,"设为当前目标",func(): _commit(game.sim.set_sandbox_goal(id)),Vector2(0,32))
	challenge_box.hide()

func refresh(sync_inputs: bool=false) -> void:
	if game == null or game.sim.get("evolution") == null:
		return
	funds_label.text = "可用资金  ¥%s" % game._number(float(game.sim.cash))
	var evolution: RefCounted = game.sim.evolution
	scenario_label.text = "历史开局：按技术解锁设施" if bool(evolution.get("heritage")) else "现代试点：继承基础设施，探索技术路线"
	project_label.text = "研发空闲 · 选择下一项技术"
	if not str(evolution.project).is_empty():
		var tech: Dictionary = Evolution.TECHNOLOGIES[evolution.project]
		project_label.text = "研发中：%s · 剩余 %.1f 小时" % [tech.name,evolution.remaining_hours]
	for id in technology_buttons:
		var tech: Dictionary = Evolution.TECHNOLOGIES[id]
		var complete: bool = id in evolution.unlocked
		var prerequisites := true
		for prerequisite in tech.requires:
			if prerequisite not in evolution.unlocked:
				prerequisites = false
		var status := "✓ 已掌握" if complete else ("研发中" if str(evolution.project)==id else ("可研究 · ¥%s · %.1fh" % [game._number(float(tech.cost)),tech.hours] if prerequisites else "○ 前置技术未满足"))
		technology_buttons[id].text = str(tech.name)+"\n"+status
	_refresh_technology_detail()
	for kind in construction_buttons:
		var result: Dictionary = evolution.can_build(kind)
		construction_buttons[kind].disabled = not result.get("ok",false) or float(game.sim.cash)<float(game.sim.catalog[kind].price)
		construction_buttons[kind].text = "选择建造" if result.get("ok",false) else "需要研究解锁"
		construction_buttons[kind].tooltip_text = str(result.get("message",""))
	_refresh_picker(sync_inputs)
	_refresh_facility(sync_inputs)
	_refresh_region()

func _refresh_picker(force: bool) -> void:
	var signature := str(game.sim.buildings.map(func(b: Dictionary): return b.id))
	if not force and signature==_asset_signature:
		return
	facility_picker.clear()
	for building in game.sim.buildings:
		facility_picker.add_item("#%02d · %s" % [building.id,building.name],int(building.id))
	for i in facility_picker.item_count:
		if facility_picker.get_item_id(i)==selected_facility:
			facility_picker.select(i)
	if facility_picker.item_count>0:
		selected_facility = facility_picker.get_selected_id()
	_asset_signature = signature

func _refresh_facility(sync_inputs: bool) -> void:
	var building: Dictionary = game.sim.get_building(selected_facility)
	if building.is_empty():
		facility_info.text = "选择设施以查看运行边界。"
		return
	facility_info.text = "%s · %s\n%s" % [building.name,game.sim.catalog[building.kind].description,game.sim.facility_status(selected_facility)]
	var storage: bool = game.sim.evolution.is_storage(str(building.kind))
	var generator: bool = game.sim.evolution.is_generator(str(building.kind)) or building.kind=="gas"
	controls["出力上限 %"].visible = generator
	controls["冷却方式"].visible = building.kind=="cooling"
	controls["储能运行策略"].visible = storage
	controls["保留荷电 %"].visible = storage
	controls["削峰起点（持续4小时）"].visible = storage
	controls["水电生态下泄 %"].visible = building.kind=="hydro"
	controls["保护热裕度 %"].visible = building.kind=="substation"
	controls.flexible.visible = building.kind in ["steam","coal","ccgt"]
	controls.boost.visible = building.kind=="cooling"
	enabled_input.visible = generator or storage or building.kind in ["solar","wind","cooling","academy","condenser","hvdc","intertie","sensor","control","relay","soc"]
	flexible_input.disabled = not game.sim.evolution.has_technology("flexible_thermal")
	flexible_input.tooltip_text = "需要研究「柔性热机控制」；更快爬坡与较低最低负荷增加运维与燃料费用。"
	boost_input.disabled = not game.sim.evolution.has_technology("advanced_cooling")
	boost_input.tooltip_text = "需要研究「先进热管理」；提高冷却容量，也增加耗电和维护费。"
	protection_input.editable = game.sim.evolution.has_technology("protection")
	protection_input.tooltip_text = "需要研究「继电保护协调」；低裕度更早跳闸，高裕度加速设备老化。"
	reserve_input.editable = game.sim.evolution.has_technology("regional_planning")
	reserve_input.tooltip_text = "需要研究「区域负荷规划」。"
	cooling_input.set_item_disabled(1,not game.sim.evolution.has_technology("dry_cooling"))
	cooling_input.tooltip_text = "干冷模式需要研究「空冷与节水运行」。"
	storage_input.set_item_disabled(2,not game.sim.evolution.has_technology("smart_storage"))
	storage_input.tooltip_text = "定时削峰需要研究「储能协同与削峰」，并为设施建立可信通信。"
	peak_input.editable = game.sim.evolution.has_technology("smart_storage")
	if not sync_inputs:
		return
	enabled_input.button_pressed = bool(building.get("enabled",true))
	dispatch_input.value = float(building.get("dispatch",1.0))*100
	cooling_input.select(1 if building.get("cooling_mode","wet")=="dry" else 0)
	storage_input.select(maxi(0,["auto","hold","peak"].find(str(building.get("storage_mode","auto")))))
	reserve_input.value = float(building.get("reserve_soc",0))*100
	peak_input.value = float(building.get("peak_hour",17))
	release_input.value = float(building.get("environmental_release",.25))*100
	protection_input.value = float(building.get("protection_margin",1.0))*100
	flexible_input.button_pressed = bool(building.get("flexible_mode",false))
	boost_input.button_pressed = bool(building.get("boost_cooling",false))

func _refresh_region() -> void:
	var region: RefCounted = game.sim.region
	var summary: Dictionary = region.summary()
	expand_button.visible = not bool(region.active)
	region_map.visible = bool(region.active)
	region_map.sim = game.sim
	region_map.refresh()
	region_info.text = "海湾教学区运行中。准备好备用容量和远距离输电资金，再开启区域。"
	if region.active:
		region_info.text = "%d 座城市 · 人口 %.0f · %d 城成长 / %d 城衰退 · 区域供电 %.0f%%" % [summary.city_count,summary.population,summary.growing,summary.declining,float(summary.average_service)*100]
	var signature := str(region.cities.map(func(city: Dictionary): return city.id))
	if signature != _city_signature:
		game._clear_children(city_box)
		city_labels.clear()
		city_cards.clear()
		city_picker.clear()
		for city in region.cities:
			var card := _card(city_box)
			city_cards[city.id] = card.get_parent()
			city_labels[city.id] = _text(card,"",CREAM,13)
			var id: int = city.id
			game._button(card,"定位城市",func(): close(); game.focus_city(id),Vector2(0,32))
			city_picker.add_item(str(city.name)+" · "+str(city.specialization),id)
		if not city_cards.has(selected_city) and city_picker.item_count>0:
			selected_city = city_picker.get_item_id(0)
		for index in city_picker.item_count:
			if city_picker.get_item_id(index)==selected_city:
				city_picker.select(index)
		_city_signature = signature
	for city in region.cities:
		city_cards[city.id].visible = int(city.id)==selected_city
		city_labels[city.id].text = "%s · %s\n人口 %.0f    供电 %.0f%%    繁荣 %.0f%%    每日人口 %+.1f%%\n%s" % [city.name,city.specialization,city.population,float(city.service)*100,float(city.prosperity)*100,float(city.growth)*100,city.trend]
	city_picker.visible = bool(region.active)
	city_heading.visible = bool(region.active)
	region_map.selected_id = selected_city
	current_goal.text = "尚未选择长期目标。选择一个方向，持续改善你的电网。"
	for challenge in game.sim.sandbox_goals():
		if challenge_labels.has(challenge.id):
			challenge_labels[challenge.id].text = "%s · 进度 %.0f%%%s" % ["当前目标" if game.sim.sandbox_goal==challenge.id else "可选方向",float(challenge.progress)*100," · ✓ 已达成" if challenge.complete else ""]
		if game.sim.sandbox_goal==challenge.id:
			current_goal.text = "%s · %.0f%%%s\n%s" % [challenge.name,float(challenge.progress)*100," · ✓ 已达成" if challenge.complete else "",challenge.description]

func _apply_facility() -> void:
	var building: Dictionary = game.sim.get_building(selected_facility)
	if building.is_empty():
		return
	var settings: Dictionary = {}
	if enabled_input.visible:
		settings.enabled = enabled_input.button_pressed
	if game.sim.evolution.is_generator(str(building.kind)) or building.kind=="gas":
		settings.dispatch = dispatch_input.value/100
	if building.kind=="cooling":
		settings.cooling_mode = "dry" if cooling_input.selected==1 else "wet"
		settings.boost_cooling = boost_input.button_pressed
	if game.sim.evolution.is_storage(str(building.kind)):
		settings.storage_mode = ["auto","hold","peak"][storage_input.selected]
		settings.reserve_soc = reserve_input.value/100
		settings.peak_hour = peak_input.value
	if building.kind=="hydro":
		settings.environmental_release = release_input.value/100
	if building.kind=="substation":
		settings.protection_margin = protection_input.value/100
	if building.kind in ["steam","coal","ccgt"]:
		settings.flexible_mode = flexible_input.button_pressed
	_commit(game.sim.configure_facility(selected_facility,settings))

func _choose_build(kind: String) -> void:
	close()
	game.build_kind = kind
	game._set_tool("build")

func _advance() -> void:
	game.sim.step(1.0)
	game._sync_world(true)
	game._update_hud()
	game._update_inspector()
	refresh()
	message_label.text = "已推进 1 游戏小时；研发、城市变化、机组启动和运营费用已结算。"

func _commit(result: Dictionary) -> void:
	game._apply(result)
	game._sync_world(true)
	game._update_hud()
	game._update_inspector()
	refresh(true)
	message_label.text = ("✓ " if result.get("ok",false) else "! ")+str(result.get("message","操作完成"))
	message_label.add_theme_color_override("font_color",TEAL if result.get("ok",false) else ORANGE)
