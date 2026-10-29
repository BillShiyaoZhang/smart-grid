extends Control
## Planning is paused; only explicit commands and Advance change simulation state.
const Evolution = preload("res://scripts/sim/grid_evolution.gd")
const RegionMap = preload("res://scripts/ui/region_map.gd")
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
var technology_labels: Dictionary = {}
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

func setup(owner_game: Node) -> void:
	game = owner_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	hide()

func open() -> void:
	refresh(true)
	show()

func close() -> void:
	hide()
	game._update_hud()
	game._update_inspector()

func select_facility(id: int) -> void:
	selected_facility = id
	tabs.current_tab = 1
	refresh(true)

func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(.02,.06,.09,.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = .04
	panel.anchor_right = .96
	panel.anchor_top = .035
	panel.anchor_bottom = .965
	panel.add_theme_stylebox_override("panel",game._style(Color("102c38")))
	add_child(panel)
	var body: VBoxContainer = game._column(panel,12)
	var header: HBoxContainer = game._row(body,12)
	var titles: VBoxContainer = game._column(header,2)
	game._label(titles,"科技与区域规划  /  GRID EVOLUTION",11,BLUE)
	game._label(titles,"每一代电网，都有新的取舍。",26,CREAM)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	game._label(header,"规划中 · 时间暂停",11,MUTED)
	game._button(header,"推进 1 小时",_advance,Vector2(125,40))
	game._button(header,"返回电网  Esc",close,Vector2(125,40))
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
	message_label = _text(body,"先连通海湾，再选择你的发展路线。研究解锁能力；配套、位置与调度决定效果。",MUTED,12)

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
	scenario_label = _text(body,"",ORANGE,14)
	_text(body,"每项研究列出前置、解锁与边界，一次开展一个项目，支付费用后还需要游戏时间。历史开局从直流街区起步；现代试点继承基础设备，允许直接探索新的技术组合。",MUTED)
	game._button(body,"从爱迪生时代重新开局（自动备份当前进度）",func(): game.start_heritage_game(),Vector2(0,36))
	game._button(body,"恢复切换历史开局前的进度",func(): game._load("user://before_heritage.json"),Vector2(0,32))
	for era_index in Evolution.ERAS.size():
		var era: Dictionary = Evolution.ERAS[era_index]
		var heading: HBoxContainer = game._row(body,12)
		game._label(heading,"%02d  %s" % [era_index+1,era.name],20,TEAL)
		game._label(heading,str(era.years),13,ORANGE)
		_text(body,str(era.description),MUTED)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation",12)
		grid.add_theme_constant_override("v_separation",12)
		body.add_child(grid)
		for tech_id in Evolution.TECHNOLOGIES:
			var tech: Dictionary = Evolution.TECHNOLOGIES[tech_id]
			if int(tech.era) != era_index:
				continue
			var card := _card(grid)
			_text(card,"%s  ·  %s" % [tech.name,tech.branch],CREAM,17)
			_text(card,str(tech.description),MUTED)
			var requires: Array[String] = []
			for prerequisite in tech.requires:
				requires.append(str(Evolution.TECHNOLOGIES[prerequisite].name))
			_text(card,"前置：%s" % ("起点" if requires.is_empty() else " + ".join(requires)),BLUE,12)
			var names: Array[String] = []
			for kind in tech.unlocks:
				if game.sim.catalog.has(kind):
					names.append(str(game.sim.catalog[kind].name))
			if not names.is_empty():
				_text(card,"设施：%s" % "、".join(names),ORANGE,12)
			technology_labels[tech_id] = _text(card,"",TEAL,12)
			var id: String = tech_id
			technology_buttons[id] = game._button(card,"",func(): _commit(game.sim.research_technology(id)),Vector2(0,34))

func _build_facilities() -> void:
	var body := _tab("设施与精细调度")
	_text(body,"先选择设施检查配套和运行边界。参数为草案，点击「应用设施设置」后生效；科技树不会替你安排运行策略。",MUTED)
	facility_picker = OptionButton.new()
	facility_picker.custom_minimum_size = Vector2(0,38)
	facility_picker.add_theme_font_size_override("font_size",15)
	body.add_child(facility_picker)
	facility_picker.item_selected.connect(func(_index: int): selected_facility=facility_picker.get_selected_id(); _refresh_facility(true))
	var operating := _card(body)
	facility_info = _text(operating,"",CREAM,14)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation",28)
	grid.add_theme_constant_override("v_separation",10)
	operating.add_child(grid)
	enabled_input = CheckButton.new()
	enabled_input.text = "允许设施运行"
	grid.add_child(enabled_input)
	controls.enabled = enabled_input
	dispatch_input = _number_control(grid,"出力上限 %",0,100,5)
	cooling_input = _option_control(grid,"冷却方式",["湿式 · 更强冷却，更多用水","干式 · 节水，但降低机组上限"])
	storage_input = _option_control(grid,"储能运行策略",["自动平衡","保留电量","定时削峰"])
	reserve_input = _number_control(grid,"保留荷电 %",0,90,5)
	peak_input = _number_control(grid,"削峰起点（持续4小时）",0,23,1)
	release_input = _number_control(grid,"水电生态下泄 %",10,60,5)
	protection_input = _number_control(grid,"保护热裕度 %",80,120,5)
	flexible_input = CheckButton.new()
	flexible_input.text = "柔性热机档 · 更快爬坡，增加成本"
	grid.add_child(flexible_input)
	controls.flexible = flexible_input
	boost_input = CheckButton.new()
	boost_input.text = "强化冷却档 · 更多容量，更高辅机成本"
	grid.add_child(boost_input)
	controls.boost = boost_input
	game._button(operating,"应用设施设置",_apply_facility,Vector2(0,38))
	_text(operating,"核电需要同一电气岛内的冷却与人才配套；启动与爬坡需要时间。定时储能在峰段放电、谷段补能，保留电量会减少即时可用出力。",ORANGE,12)
	game._label(body,"设施目录 · 选择后在地图放置",20,TEAL)
	var catalog_grid := GridContainer.new()
	catalog_grid.columns = 3
	catalog_grid.add_theme_constant_override("h_separation",12)
	catalog_grid.add_theme_constant_override("v_separation",12)
	body.add_child(catalog_grid)
	for item in game.sim.catalog:
		var kind: String = item
		var spec: Dictionary = game.sim.catalog[kind]
		var card := _card(catalog_grid)
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

func _number_control(parent: Node, caption: String, minimum: float, maximum: float, increment: float) -> SpinBox:
	var row: HBoxContainer = game._row(parent,8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := _text(row,caption,MUTED,12)
	label.custom_minimum_size.x = 150
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
	input.custom_minimum_size = Vector2(270,36)
	for option in options:
		input.add_item(str(option))
	column.add_child(input)
	controls[caption] = column
	return input

func _build_region() -> void:
	var body := _tab("区域沙盘与自定目标")
	_text(body,"从一座海湾走向八城区域。城市用电获得收入，也会成长、扩张、分工或衰退；长距离输电、备用通道和不同峰谷成为新的经营问题。",MUTED)
	expand_button = game._button(body,"开启 48 × 48 区域沙盘 · 接管七座周边城市",func(): _commit(game.sim.expand_region()),Vector2(0,40))
	region_info = _text(body,"",TEAL,15)
	region_map = RegionMap.new()
	region_map.custom_minimum_size = Vector2(0,290)
	region_map.city_selected.connect(func(id: int): close(); game.focus_city(id))
	body.add_child(region_map)
	city_box = game._column(body,10)
	game._label(body,"给自己的电网设一个方向",20,TEAL)
	challenge_box = game._column(body,10)
	for challenge in game.sim.sandbox_goals():
		var card := _card(challenge_box)
		_text(card,str(challenge.name),CREAM,16)
		_text(card,str(challenge.description),MUTED,12)
		var id: String = challenge.id
		challenge_labels[id] = _text(card,"",TEAL,12)
		game._button(card,"设为当前目标",func(): _commit(game.sim.set_sandbox_goal(id)),Vector2(0,32))

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
		var button: Button = technology_buttons[id]
		button.text = "✓ 已掌握" if complete else ("研发中" if str(evolution.project)==id else "研究 · ¥%s · %.1fh" % [game._number(float(tech.cost)),tech.hours])
		button.disabled = complete or not prerequisites or not str(evolution.project).is_empty() or float(game.sim.cash)<float(tech.cost)
		technology_labels[id].text = "能力已开放，仍需建设配套与调度。" if complete else ("前置技术已满足" if prerequisites else "先研究上方列出的前置技术")
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
		for city in region.cities:
			var card := _card(city_box)
			city_labels[city.id] = _text(card,"",CREAM,13)
			var id: int = city.id
			game._button(card,"定位城市",func(): close(); game.focus_city(id),Vector2(0,32))
		_city_signature = signature
	for city in region.cities:
		city_labels[city.id].text = "%s · %s  |  人口 %.0f  |  供电 %.0f%%  |  繁荣 %.0f%%  |  每日人口 %+.1f%%\n%s" % [city.name,city.specialization,city.population,float(city.service)*100,float(city.prosperity)*100,float(city.growth)*100,city.trend]
	for challenge in game.sim.sandbox_goals():
		if challenge_labels.has(challenge.id):
			challenge_labels[challenge.id].text = "%s · 进度 %.0f%%%s" % ["当前目标" if game.sim.sandbox_goal==challenge.id else "可选方向",float(challenge.progress)*100," · ✓ 已达成" if challenge.complete else ""]

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
