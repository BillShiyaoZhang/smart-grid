extends Control
## Planning is paused; only explicit commands and Advance change simulation state.
const Evolution = preload("res://scripts/sim/grid_evolution.gd")
const RegionMap = preload("res://scripts/ui/region_map.gd")
const Shell = preload("res://scripts/ui/management_shell.gd")
const Drafts = preload("res://scripts/ui/config_drafts.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const VisualChart = preload("res://scripts/ui/center_charts.gd")
const FacilityEditor = preload("res://scripts/ui/facility_controls.gd")
const DecisionWorkbench = preload("res://scripts/ui/decision_workbench.gd")
var decision_workbench: Control
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
var facility_method: OptionButton
var facility_execution: Label
var facility_guidance: Label
var _pending_facility := ""
var enabled_input: CheckButton
var dispatch_input: SpinBox
var cooling_input: OptionButton
var storage_input: OptionButton
var storage_intent_input: OptionButton
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
var catalog_era_labels: Dictionary = {}
var catalog_grid: GridContainer
var operating_grid: GridContainer
var scenario_actions: VBoxContainer
var scenario_toggle: Button
var goal_header: HBoxContainer
var city_picker: OptionButton
var selected_city := -1
var city_cards: Dictionary = {}
var current_goal: Label
var city_heading: HBoxContainer
var region_work: BoxContainer
var drafts: RefCounted = Drafts.new()
var _displayed_facility := -1
var _inherited_building := -1
var facility_draft: Label
var comparison_kinds: Array[String] = []
var comparison_label: Label
var comparison_buttons: Dictionary = {}
var comparison_grid: GridContainer
var comparison_cards: Dictionary = {}
var comparison_chart: Control
var facility_chart: Control
var technology_map: Control
var digital_research_button: Button
var research_progress: ProgressBar
var city_chart: Control
var city_service_buttons: Dictionary = {}
var comparison_details_toggle: Button
var comparison_choice: OptionButton
var comparison_choose: Button
var catalog_header_row: HBoxContainer

func reset_session() -> void:
	if decision_workbench!=null: decision_workbench.reset_session()
	drafts.clear()
	_displayed_facility=-1
	_inherited_building=-1
	_asset_signature=""
	_city_signature=""
	_pending_facility=""
	selected_facility=1
	selected_city=-1
	comparison_kinds.clear()
	if comparison_label!=null: _refresh_comparison()
	if tabs!=null: tabs.current_tab=0
	if facility_modes!=null: facility_modes.current_tab=0

func inherit_selection(building_id: int=-1,_line_id: int=-1,_comm_line_id: int=-1) -> void:
	if building_id>=0 and building_id!=_inherited_building and not game.sim.get_building(building_id).is_empty():
		_capture_facility()
		selected_facility=building_id
	_inherited_building=building_id

func setup(owner_game: Node) -> void:
	game = owner_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	hide()

func open() -> void:
	if not game.sim.feature_enabled("research"): return
	inherit_selection(int(game.selected_id))
	game._prepare_center(self)
	refresh(true)
	show()

func close() -> void:
	_capture_facility()
	hide()
	if _facility_has_drafts(): game._notify("设施草案已保留；未提交的设置尚未生效。")
	game._update_hud()
	game._update_inspector()

func select_facility(id: int) -> void:
	_capture_facility()
	selected_facility = id
	tabs.current_tab = 1
	facility_modes.current_tab = 0
	refresh(true)

func _build() -> void:
	var body: VBoxContainer = Shell.build(self,"发展 · 科技与区域规划","推进 1 小时",_advance,close)
	var metrics: HBoxContainer = game._row(body,12)
	funds_label = _text(metrics,"",CREAM,15)
	funds_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	project_label = _text(metrics,"",TEAL,15)
	project_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs = TabContainer.new()
	tabs.use_hidden_tabs_for_min_size=false
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size",16)
	tabs.add_theme_color_override("font_selected_color",BLUE)
	tabs.add_theme_color_override("font_unselected_color",MUTED)
	tabs.add_theme_stylebox_override("panel",game._style(Color("153440"),10))
	tabs.add_theme_stylebox_override("tab_selected",game._style(Color("234954"),8))
	tabs.add_theme_stylebox_override("tab_unselected",game._style(Color("102b37"),8))
	body.add_child(tabs)
	tabs.tab_changed.connect(_scroll_page_top)
	_build_technologies()
	_build_facilities()
	_build_region()
	decision_workbench=DecisionWorkbench.new()
	_tab("预测与推演").add_child(decision_workbench)
	decision_workbench.setup(game,"planning")
	message_label = _text(body,"研究解锁能力；配套、位置与调度决定效果。",MUTED,14)
	resized.connect(_adapt_columns)
	_adapt_columns()

func _text(parent: Node, caption: String, color: Color=MUTED, font_size: int=13) -> Label:
	var result: Label = game._label(parent,caption,font_size,color)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result

func _scroll_page_top(_index: int) -> void:
	var outer: Node=tabs.get_parent().get_parent()
	if outer is ScrollContainer: outer.scroll_vertical=0

func _tab(caption: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = caption
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
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
	scenario_toggle = game._button(scenario_row,"场景选项",func(): scenario_actions.visible=not scenario_actions.visible,Vector2(96,34))
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
	technology_map=VisualChart.new()
	technology_map.mode="technology"
	technology_map.custom_minimum_size=Vector2(0,170)
	technology_map.technology_selected.connect(_select_technology)
	body.add_child(technology_map)
	var work: HBoxContainer = game._row(body,16)
	var technology_list: VBoxContainer = game._column(work,4)
	technology_list.visible=false
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
	research_progress=ProgressBar.new()
	research_progress.custom_minimum_size=Vector2(0,14)
	research_progress.show_percentage=false
	detail.add_child(research_progress)
	digital_research_button=game._button(detail,"智能化能力研究",func(): game._research(); refresh(),Vector2(0,38))
	digital_research_button.tooltip_text="遥测、远控与自动恢复统一在能力研究中查看；实际运行仍需通信与新鲜观测。"
	_select_era(0)

func _select_era(index: int) -> void:
	if game!=null and game._campaign_active() and index>=5: return
	selected_era = index
	for i in era_buttons.size():
		era_buttons[i].set_pressed_no_signal(i==selected_era)
	var era: Dictionary = Evolution.ERAS[selected_era]
	era_description.text = (str(game.sim.campaign.chapter().years)+"  ·  本关可用技术") if game._campaign_active() else str(era.years)+"  ·  "+str(era.description)
	for id in technology_cards:
		technology_cards[id].visible = int(Evolution.TECHNOLOGIES[id].era)==selected_era and _technology_allowed(id)
	if selected_technology.is_empty() or not _technology_allowed(selected_technology) or int(Evolution.TECHNOLOGIES[selected_technology].era)!=selected_era:
		for id in Evolution.TECHNOLOGIES:
			if int(Evolution.TECHNOLOGIES[id].era)==selected_era and _technology_allowed(id):
				selected_technology = id
				break
	_refresh_technology_detail()

func _select_technology(id: String) -> void:
	selected_technology = id
	_refresh_technology_detail()

func _refresh_technology_detail() -> void:
	_update_technology_map()
	if selected_technology.is_empty() or not _technology_allowed(selected_technology):
		technology_title.text="本关技术"
		technology_detail.text="选择本关开放的技术；其他能力将由后续章节介绍。"
		technology_status.text=""
		technology_action.disabled=true
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
	technology_detail.text = "%s · %s\n%s\n\n前置 · %s" % [tech.branch,str(game.sim.campaign.chapter().years) if game._campaign_active() else Evolution.ERAS[int(tech.era)].years,tech.description,"起点技术" if requirements.is_empty() else "、".join(requirements)]
	if not unlocks.is_empty():
		technology_detail.text += "\n解锁 · "+"、".join(unlocks)
	technology_action.text = "✓ 已掌握" if complete else ("研发中 · 剩余 %.1fh" % evolution.remaining_hours if str(evolution.project)==selected_technology else "研究 · ¥%s · %.1fh" % [game._number(float(tech.cost)),tech.hours])
	technology_action.disabled = complete or not prerequisites or not str(evolution.project).is_empty() or float(game.sim.cash)<float(tech.cost)
	technology_status.text = "能力已开放，仍需建设配套与调度。" if complete else ("先完成前置研究" if not prerequisites else ("已有研究正在进行" if not str(evolution.project).is_empty() else ("资金不足" if float(game.sim.cash)<float(tech.cost) else "可开展研究")))
	for id in technology_buttons:
		technology_buttons[id].set_pressed_no_signal(id==selected_technology)

func _research_selected() -> void:
	if not selected_technology.is_empty() and _technology_allowed(selected_technology):
		_commit(game.sim.research_technology(selected_technology))

func _build_facilities() -> void:
	var body := _tab("设施与精细调度")
	facility_modes = TabContainer.new()
	facility_modes.use_hidden_tabs_for_min_size = false
	facility_modes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(facility_modes)
	facility_modes.tab_changed.connect(_scroll_page_top)
	var operating_body: VBoxContainer = game._column(facility_modes,12)
	operating_body.name = "设施运行"
	_text(operating_body,"选择设施，检查额定配套与已知运行状态。参数调整后，选择远程或现场提交。",MUTED,14)
	facility_picker = OptionButton.new()
	facility_picker.custom_minimum_size = Vector2(0,38)
	facility_picker.add_theme_font_size_override("font_size",15)
	operating_body.add_child(facility_picker)
	facility_picker.item_selected.connect(func(_index: int): selected_facility=facility_picker.get_selected_id(); _refresh_facility(true))
	var operating := _card(operating_body)
	facility_info = _text(operating,"",CREAM,14)
	facility_chart=VisualChart.new()
	facility_chart.custom_minimum_size=Vector2(0,156)
	operating.add_child(facility_chart)
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
	storage_intent_input = _option_control(operating_grid,"运行方案",["继承全网默认","保供优先","高峰支援","低买高卖","旧版自定义"])
	storage_intent_input.item_selected.connect(_storage_intent_selected)
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
	facility_method = OptionButton.new()
	facility_method.add_item("远程设置 · 需要可信路径、二级研究与新鲜遥测")
	facility_method.add_item("现场设置 · ¥350 · 约21游戏分钟 · 占用一支队伍")
	facility_method.custom_minimum_size = Vector2(0,38)
	facility_method.fit_to_longest_item = false
	facility_method.clip_text = true
	operating.add_child(facility_method)
	facility_execution = _text(operating,"",ORANGE,14)
	game._button(operating,"应用设施设置",_apply_facility,Vector2(0,38))
	facility_draft=_text(operating,"",ORANGE,14)
	game._button(operating,"重置此设施草案",reset_facility_draft,Vector2(0,34))
	facility_guidance = _text(operating,"",ORANGE,14)
	var catalog_body: VBoxContainer = game._column(facility_modes,12)
	catalog_body.name = "建造目录"
	var catalog_header: HBoxContainer = game._row(catalog_body,12)
	catalog_header_row=catalog_header
	_text(catalog_header,"选择设施后，返回地图放置。",MUTED,14)
	catalog_category = OptionButton.new()
	catalog_category.custom_minimum_size = Vector2(160,38)
	for category in ["全部设施","发电设施","储能设施","输配电与配套","城市用电","数字通信"]:
		catalog_category.add_item(category)
	catalog_category.item_selected.connect(func(_index: int): _filter_catalog())
	catalog_header.add_child(catalog_category)
	comparison_label=_text(catalog_body,"对比最多三种设施：加入对比后查看额定容量、成本与约束。",MUTED,14)
	comparison_grid=GridContainer.new()
	comparison_grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	comparison_grid.add_theme_constant_override("h_separation",12)
	comparison_grid.add_theme_constant_override("v_separation",12)
	comparison_chart=VisualChart.new()
	comparison_chart.mode="comparison"
	comparison_chart.custom_minimum_size=Vector2(0,414)
	catalog_body.add_child(comparison_chart)
	comparison_chart.hide()
	var comparison_actions: HBoxContainer=game._row(catalog_body,8)
	comparison_choice=OptionButton.new()
	comparison_choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	comparison_choice.item_selected.connect(func(_index: int): _update_comparison_action())
	comparison_actions.add_child(comparison_choice)
	comparison_choose=game._button(comparison_actions,"选择并选址",func():
		if comparison_choice.selected>=0: _choose_build(str(comparison_choice.get_item_metadata(comparison_choice.selected)))
	,Vector2(140,38))
	UI.action(comparison_choose)
	comparison_actions.name="ComparisonActions"
	comparison_details_toggle=game._button(catalog_body,"详细参数",func(): comparison_grid.visible=not comparison_grid.visible,Vector2(0,32))
	catalog_body.add_child(comparison_grid)
	comparison_grid.hide()
	game._button(catalog_body,"清空设施对比",func(): comparison_kinds.clear(); _refresh_comparison(),Vector2(0,32))
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
		catalog_era_labels[kind] = _text(card,"用电侧 · 随城市发展" if kind in ["home","factory","hospital"] else "%s · %s" % [Evolution.ERAS[era_index].name,Evolution.ERAS[era_index].years],BLUE,11)
		_text(card,str(spec.description),MUTED,12)
		var design := "造价 ¥%s" % game._number(float(spec.price))
		if float(spec.capacity) > 0:
			design += " · %.0f MW" % float(spec.capacity)
		if float(spec.get("energy",0)) > 0:
			design += " / %.0f MWh" % float(spec.energy)
		_text(card,design,ORANGE,12)
		construction_buttons[kind] = game._button(card,"选择建造",func(): _choose_build(kind),Vector2(0,34))
		comparison_buttons[kind]=game._button(card,"加入对比",func(): _toggle_comparison(kind),Vector2(0,32))

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
		catalog_cards[kind].visible = (catalog_category.selected==0 or catalog_category.selected==category) and (not game._campaign_active() or game.sim.can_build(kind).ok)

func _adapt_columns() -> void:
	var narrow := size.x<1100
	if catalog_grid!=null:
		catalog_grid.columns = 1 if narrow else 2
	if operating_grid!=null:
		operating_grid.columns = 1 if narrow else 2
	if comparison_grid!=null:
		comparison_grid.columns=maxi(1,comparison_kinds.size())
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
	expand_button = game._button(body,"探索 48 × 48 区域 · 查看七座潜在城市",func(): _commit(game.sim.explore_region() if game.sim.has_method("explore_region") else game.sim.expand_region()),Vector2(0,40))
	region_info = _text(body,"",TEAL,15)
	city_chart=VisualChart.new()
	city_chart.mode="cities"
	city_chart.custom_minimum_size=Vector2(0,344)
	city_chart.item_selected.connect(func(id: int): selected_city=id; _refresh_region())
	body.add_child(city_chart)
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
	goal_header = game._row(region_details,12)
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

func _technology_allowed(id: String) -> bool:
	if not game._campaign_active(): return true
	var technology: Dictionary=Evolution.TECHNOLOGIES[id]
	if int(technology.era)>=5: return false
	if game.sim.campaign.can_research(id): return true
	if id not in game.sim.evolution.unlocked: return false
	if id=="scada": return game.sim.feature_enabled("digital")
	if id=="regional_planning": return game.sim.feature_enabled("region") or game.sim.feature_enabled("storage_control")
	if id=="protection": return int(game.sim.campaign.chapter_id)>=4
	if id=="smart_storage": return int(game.sim.campaign.chapter_id)>=15
	for kind in technology.unlocks:
		if game.sim.can_build(kind).ok: return true
	return false

func refresh(sync_inputs: bool=false) -> void:
	if game == null or game.sim.get("evolution") == null:
		return
	var campaign_active: bool=game._campaign_active()
	tabs.set_tab_hidden(3,campaign_active)
	if campaign_active and tabs.current_tab==3: tabs.current_tab=0
	decision_workbench.refresh()
	if campaign_active: era_description.text=str(game.sim.campaign.chapter().years)+"  ·  本关可用技术"
	scenario_toggle.visible=not campaign_active
	if campaign_active: scenario_actions.hide()
	tabs.set_tab_hidden(2,campaign_active and not game.sim.feature_enabled("region"))
	if campaign_active and tabs.current_tab==2 and not game.sim.feature_enabled("region"): tabs.current_tab=0
	for i in era_buttons.size():
		era_buttons[i].visible=not campaign_active or i<5
	if campaign_active and selected_era>=5: _select_era(0)
	for id in technology_cards:
		technology_cards[id].visible=int(Evolution.TECHNOLOGIES[id].era)==selected_era and _technology_allowed(id)
	_filter_catalog()
	for kind in catalog_era_labels:
		var era: int=game.sim.evolution.building_era(kind)
		catalog_era_labels[kind].text=("本关技术 · "+str(game.sim.campaign.chapter().years)) if campaign_active else ("用电侧 · 随城市发展" if kind in ["home","factory","hospital"] else "%s · %s" % [Evolution.ERAS[era].name,Evolution.ERAS[era].years])
	funds_label.text = "可用资金  ¥%s" % game._number(float(game.sim.cash))
	var evolution: RefCounted = game.sim.evolution
	digital_research_button.visible=game.sim.feature_enabled("digital")
	digital_research_button.text=game._digital_research_caption()
	digital_research_button.disabled=not game._digital_research_available()
	research_progress.visible=not str(evolution.project).is_empty()
	if research_progress.visible:
		var project: Dictionary=Evolution.TECHNOLOGIES[evolution.project]
		research_progress.value=100*(1-float(evolution.remaining_hours)/maxf(.001,float(project.hours)))
	scenario_label.text = ("本关技术与设施 · "+str(game.sim.campaign.chapter().title)) if campaign_active else ("历史开局：按技术解锁设施" if bool(evolution.get("heritage")) else "现代试点：继承基础设施，探索技术路线")
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
		var result: Dictionary = game.sim.can_build(kind)
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
	for key in drafts.values.keys():
		if game.sim.get_building(int(key)).is_empty():
			drafts.values.erase(key)
			drafts.baselines.erase(key)
	if _displayed_facility>=0 and game.sim.get_building(_displayed_facility).is_empty(): _displayed_facility=-1
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
	_capture_facility()
	var building: Dictionary = game.sim.get_building(selected_facility)
	if building.is_empty():
		facility_info.text = "选择设施以查看运行边界。"
		return
	var observation: Dictionary = game.sim.facility_observation(selected_facility)
	facility_info.text = "%s · %s\n%s" % [building.name,game.sim.catalog[building.kind].description,observation.status]
	var trusted: bool=bool(observation.get("trusted",false))
	var capacity: float=float(building.get("capacity",0))
	var rows: Array=[]
	if capacity>0:
		rows.append({"label":"额定容量","value":capacity,"max":capacity,"text":"%.1f MW" % capacity,"color":MUTED})
		rows.append({"label":"当前可用","value":float(observation.get("available",0)) if observation.get("available")!=null else 0,"max":capacity,"text":"%.1f MW" % float(observation.get("available",0)) if trusted else "?","known":trusted})
		rows.append({"label":"实际输出","value":float(observation.get("output",0)) if observation.get("output")!=null else 0,"max":capacity,"text":"%.1f MW" % float(observation.get("output",0)) if trusted else "?","known":trusted})
	facility_chart.visible=not rows.is_empty()
	facility_chart.set_snapshot({"rows":rows})
	var execution := "设置先提交队列，执行完成后才生效。"
	var pending_signature := ""
	for pair in [[game.sim.digital.pending_commands,"远程"],[game.sim.digital.field_jobs,"现场"]]:
		for command in pair[0]:
			if command.get("kind","")=="facility" and int(command.get("building_id",-1))==selected_facility:
				pending_signature="%d:%d" % [selected_facility,command.id]
				execution="%s设置执行中 · 剩余 %.2f 游戏小时（设备尚未应用）" % [pair[1],command.remaining]
	facility_execution.text=execution
	if pending_signature.is_empty() and game.sim.has_method("operation_receipts"):
		var receipts: Array=game.sim.operation_receipts()
		for index in range(receipts.size()-1,-1,-1):
			var receipt: Dictionary=receipts[index]
			if receipt.get("action","")=="facility" and int(receipt.get("target_id",-1))==selected_facility and receipt.get("phase","") in ["executed","rejected"]:
				facility_execution.text=("✓ 已生效 · " if receipt.phase=="executed" else "! 未生效 · ")+str(receipt.get("message","请检查执行回执"))
				break
	_pending_facility=pending_signature
	var storage: bool = game.sim.evolution.is_storage(str(building.kind))
	var generator: bool = game.sim.evolution.is_generator(str(building.kind)) or building.kind=="gas"
	if storage:
		facility_guidance.text="只改启停会保留现有运行方案；修改有效备用电量会建立此设施的独立覆盖。旧版自定义才使用旧版备用字段。"
	elif building.kind in ["steam","coal","ccgt","nuclear","fusion"]:
		facility_guidance.text="热机受到启停、爬坡和最低稳定负荷约束；核电还需要冷却、人才与实际厂用电。"
	else:
		facility_guidance.text="运行设置下发后，查看回执确认实际执行结果。"
	controls["出力上限 %"].visible = generator
	controls["冷却方式"].visible = building.kind=="cooling"
	controls["储能运行策略"].visible = storage
	controls["运行方案"].visible = storage
	controls["保留荷电 %"].visible = storage
	controls["削峰起点（持续4小时）"].visible = storage
	controls["水电生态下泄 %"].visible = building.kind=="hydro"
	controls["保护热裕度 %"].visible = building.kind=="substation"
	controls.flexible.visible = building.kind in ["steam","coal","ccgt"]
	controls.boost.visible = building.kind=="cooling"
	enabled_input.visible = generator or storage or building.kind in ["solar","wind","cooling","academy","condenser","hvdc","intertie","sensor","control","relay","soc"]
	flexible_input.disabled = not game.sim.evolution.has_technology("flexible_thermal")
	flexible_input.tooltip_text = "需要研究「柔性热机控制」；更快爬坡与较低最低负荷增加运维与燃料费用。"
	boost_input.visible = not game._campaign_active()
	boost_input.disabled = not game.sim.evolution.has_technology("advanced_cooling")
	boost_input.tooltip_text = "需要研究「先进热管理」；提高冷却容量，也增加耗电和维护费。"
	protection_input.editable = game.sim.evolution.has_technology("protection")
	protection_input.tooltip_text = "需要研究「继电保护协调」；低裕度更早跳闸，高裕度加速设备老化。"
	cooling_input.set_item_disabled(1,not game.sim.evolution.has_technology("dry_cooling"))
	cooling_input.tooltip_text = "干冷模式需要研究「空冷与节水运行」。"
	storage_input.set_item_disabled(2,not game.sim.evolution.has_technology("smart_storage"))
	storage_input.tooltip_text = "定时削峰需要研究「储能协同与削峰」，并为设施建立可信通信。"
	peak_input.editable = game.sim.evolution.has_technology("smart_storage")
	facility_method.set_item_disabled(0,not game.sim.feature_enabled("remote"))
	var key := str(selected_facility)
	var draft: Dictionary=drafts.retain(key,_effective_facility(building))
	_write_facility(draft)
	_refresh_storage_controls(storage)
	_displayed_facility=selected_facility
	var changes: Array[String]=[]
	var names: Dictionary={"enabled":"运行许可","dispatch":"出力上限 %","cooling":"冷却方式","storage":"储能策略","reserve":"保留荷电 %","peak":"削峰小时","release":"生态下泄 %","protection":"保护裕度 %","flexible":"柔性档","boost":"强化冷却","method":"提交方式"}
	for field in draft:
		if draft[field]!=drafts.baselines[key][field]: changes.append("%s %s → %s" % [names.get(field,field),_facility_value(field,drafts.baselines[key][field]),_facility_value(field,draft[field])])
	facility_draft.text="草案与生效值差异 · "+"；".join(changes) if not changes.is_empty() else "当前字段与生效设置一致。提交后需等待执行回执。"
	if not pending_signature.is_empty(): facility_draft.text+="\n已有设置在途；新编辑仍需另行提交。"

func _facility_value(field: String, value: Variant) -> String:
	match field:
		"enabled","flexible","boost": return "开启" if bool(value) else "关闭"
		"cooling": return "干式" if int(value)==1 else "湿式"
		"storage": return ["自动平衡","保留电量","定时削峰"][int(value)]
		"intent": return str({"supply":"保供优先","peak":"高峰支援","arbitrage":"低买高卖","inherit":"继承全网","legacy_custom":"旧版自定义"}.get(str(value),str(value)))
		"method": return "远程" if int(value)==0 else "现场"
	return "%.0f" % float(value)

func _effective_facility(building: Dictionary) -> Dictionary:
	var result := {"enabled":bool(building.get("enabled",true)),"dispatch":float(building.get("dispatch",1.0))*100,"cooling":1 if building.get("cooling_mode","wet")=="dry" else 0,"storage":maxi(0,["auto","hold","peak"].find(str(building.get("storage_mode","auto")))),"reserve":float(building.get("reserve_soc",0))*100,"peak":float(building.get("peak_hour",17)),"release":float(building.get("environmental_release",.25))*100,"protection":float(building.get("protection_margin",1.0))*100,"flexible":bool(building.get("flexible_mode",false)),"boost":bool(building.get("boost_cooling",false)),"method":0 if game.sim.feature_enabled("remote") and game.sim.digital.can_configure(game.sim,int(building.id)) else 1,"intent":"legacy_custom"}
	if game.sim.evolution.is_storage(str(building.kind)) and game.sim.has_method("storage_status"):
		var status: Dictionary=game.sim.storage_status(int(building.id))
		result.intent=("inherit" if status.get("inherited",false) else str(status.get("intent","legacy_custom"))) if not status.get("legacy_custom",true) else "legacy_custom"
		# Legacy controls edit their raw field; the new intent controls edit the
		# one effective reserve. Never feed a global effective value into reserve_soc.
		if not status.get("legacy_custom",true): result.reserve=float(status.get("reserve_soc",float(building.get("reserve_soc",0))))*100
	return result

func _read_facility() -> Dictionary:
	return {"enabled":enabled_input.button_pressed,"dispatch":dispatch_input.value,"cooling":cooling_input.selected,"storage":storage_input.selected,"reserve":reserve_input.value,"peak":peak_input.value,"release":release_input.value,"protection":protection_input.value,"flexible":flexible_input.button_pressed,"boost":boost_input.button_pressed,"method":facility_method.selected,"intent":["inherit","supply","peak","arbitrage","legacy_custom"][maxi(0,storage_intent_input.selected)]}

func _write_facility(value: Dictionary) -> void:
	enabled_input.set_pressed_no_signal(bool(value.enabled)); dispatch_input.value=float(value.dispatch)
	cooling_input.select(int(value.cooling)); storage_input.select(int(value.storage)); reserve_input.value=float(value.reserve)
	storage_intent_input.select(maxi(0,["inherit","supply","peak","arbitrage","legacy_custom"].find(str(value.get("intent","legacy_custom")))))
	peak_input.value=float(value.peak); release_input.value=float(value.release); protection_input.value=float(value.protection)
	flexible_input.set_pressed_no_signal(bool(value.flexible)); boost_input.set_pressed_no_signal(bool(value.boost)); facility_method.select(int(value.method))

func _capture_facility() -> void:
	if _displayed_facility<0 or not visible: return
	var building: Dictionary=game.sim.get_building(_displayed_facility)
	if not building.is_empty(): drafts.retain(str(_displayed_facility),_effective_facility(building),_read_facility())

func _capture_drafts() -> void:
	_capture_facility()

func _facility_has_drafts() -> bool:
	for key in drafts.values:
		if drafts.dirty(key): return true
	return false

func reset_facility_draft() -> void:
	var building: Dictionary=game.sim.get_building(selected_facility)
	if building.is_empty(): return
	drafts.reset(str(selected_facility),_effective_facility(building))
	_write_facility(drafts.values[str(selected_facility)])
	_refresh_facility(false)
	message_label.text="已恢复此设施当前生效值；其他设施草案仍保留。"

func _toggle_comparison(kind: String) -> void:
	if kind in comparison_kinds: comparison_kinds.erase(kind)
	elif comparison_kinds.size()<3: comparison_kinds.append(kind)
	else:
		message_label.text="最多对比三种设施，请先移除一项。"
		return
	_refresh_comparison()

func _refresh_comparison() -> void:
	game._clear_children(comparison_grid)
	comparison_cards.clear()
	comparison_grid.hide()
	comparison_chart.visible=not comparison_kinds.is_empty()
	comparison_choice.get_parent().visible=not comparison_kinds.is_empty()
	comparison_details_toggle.visible=not comparison_kinds.is_empty()
	catalog_header_row.visible=comparison_kinds.is_empty()
	var selected_kind: String=str(comparison_choice.get_item_metadata(comparison_choice.selected)) if comparison_choice.selected>=0 else ""
	comparison_choice.clear()
	var items: Array=[]
	var maximum_capacity:=1.0
	var maximum_energy:=1.0
	var maximum_time:=1.0
	var maximum_price:=1.0
	for kind in comparison_kinds:
		var spec: Dictionary=game.sim.catalog[kind]
		comparison_choice.add_item(str(spec.name))
		comparison_choice.set_item_metadata(comparison_choice.item_count-1,kind)
		if kind==selected_kind: comparison_choice.select(comparison_choice.item_count-1)
		var card: VBoxContainer=_card(comparison_grid)
		comparison_cards[kind]=card.get_parent()
		_text(card,str(spec.name),CREAM,16)
		var energy: float=float(spec.get("energy",0))
		var capacity: float=float(spec.get("capacity",0))
		var efficiency: float=float(Evolution.EFFICIENCY.get(kind,1.0))
		var duration: float=energy/maxf(.001,capacity)
		maximum_capacity=maxf(maximum_capacity,capacity)
		maximum_energy=maxf(maximum_energy,energy)
		maximum_time=maxf(maximum_time,duration)
		maximum_price=maxf(maximum_price,float(spec.price))
		items.append({"kind":kind,"name":spec.name,"price_text":game._number(float(spec.price)),"role":"山地选址" if kind=="pumped_storage" else ("跨日储能" if kind=="hydrogen" else "短时平衡" if energy>0 else "发电与供电"),"capacity":capacity,"capacity_text":"%.0f MW" % capacity,"energy":energy if energy>0 else null,"energy_text":"%.0f MWh" % energy,"duration":duration if energy>0 else null,"duration_text":"%.1f 小时" % duration,"efficiency":efficiency*efficiency*100 if energy>0 else null,"efficiency_text":"%.0f%%" % (efficiency*efficiency*100),"price":float(spec.price),"price_text_metric":"¥%s" % game._number(float(spec.price))})
		var fields: Array=[
			["建设费用","¥%s" % game._number(float(spec.price))],
			["额定功率","%.0f MW" % capacity],
			["储能容量","%.0f MWh" % energy if energy>0 else "不适用"],
			["额定时长","%.1f 小时" % (energy/maxf(.001,capacity)) if energy>0 else "不适用"],
			["基础维护","¥%.0f / 小时" % (9.0+float(Evolution.UPKEEP.get(kind,0)))],
			["往返效率","%.0f%%" % (efficiency*efficiency*100) if energy>0 else "不适用"],
			["启动预热","%.1f 小时" % float(Evolution.STARTUP[kind]) if Evolution.STARTUP.has(kind) else "不适用"],
			["最低稳定负荷","%.0f%%" % (float(Evolution.MINIMUM.get(kind,0))*100) if Evolution.STARTUP.has(kind) else "不适用"]
		]
		for field in fields:
			if field[0] not in ["储能容量","基础维护","往返效率"]: continue
			var row: HBoxContainer=game._row(card,8)
			var caption: Label=_text(row,str(field[0]),MUTED,14)
			caption.custom_minimum_size.x=100
			caption.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
			var value: Label=_text(row,str(field[1]),TEAL,14)
			value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
			if field[0]=="基础维护": value.tooltip_text="一级设施基础维护，不含燃料、辅机购电、线路及通信等费用。"
		card.get_parent().tooltip_text=str(spec.description)
	comparison_chart.set_snapshot({"items":items,"metrics":[{"key":"capacity","label":"瞬时功率 · MW","max":maximum_capacity,"color":TEAL},{"key":"duration","label":"标称时长 · 小时","max":maximum_time,"color":ORANGE},{"key":"efficiency","label":"往返效率 · 阴影为损耗","max":100.0,"color":TEAL}]})
	comparison_label.text="已选 %d / 3 项 · 共同标尺比较功率、标称时长、往返效率；额定参数不预测实际交付。" % comparison_kinds.size() if not comparison_kinds.is_empty() else "对比最多三种设施：选择后直接比较能力、时长和损耗。"
	_adapt_columns()
	for kind in comparison_buttons: comparison_buttons[kind].text="移出对比" if kind in comparison_kinds else "加入对比"
	_update_comparison_action()

func _refresh_region() -> void:
	var region: RefCounted = game.sim.region
	var summary: Dictionary = region.summary()
	expand_button.visible = not bool(region.active) and not game._campaign_active()
	goal_header.visible = not game._campaign_active()
	current_goal.visible = not game._campaign_active()
	if game._campaign_active(): challenge_box.hide()
	region_map.visible = bool(region.active)
	region_map.sim = game.sim
	region_map.refresh()
	city_chart.visible=bool(region.active)
	var ranked: Array=region.cities.duplicate(true)
	ranked.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.get("service",0))<float(b.get("service",0)))
	city_chart.set_snapshot({"cities":ranked})
	city_chart.custom_minimum_size.y=maxf(64,float(ranked.size())*40+10)
	region_info.text = "海湾教学区运行中。准备好备用容量和远距离输电资金，再开启区域。"
	if region.active:
		region_info.text = "%d 座城市 · %d 已服务 / %d 建设中 / %d 潜在市场 · 已服务城市供电 %.0f%%" % [summary.city_count,summary.get("serving_count",summary.city_count),summary.get("planned_count",0),summary.get("prospect_count",0),float(summary.average_service)*100]
	var signature := str(region.cities.map(func(city: Dictionary): return city.id))
	if signature != _city_signature:
		game._clear_children(city_box)
		city_labels.clear()
		city_cards.clear()
		city_service_buttons.clear()
		city_picker.clear()
		for city in region.cities:
			var card := _card(city_box)
			city_cards[city.id] = card.get_parent()
			city_labels[city.id] = _text(card,"",CREAM,13)
			var id: int = city.id
			game._button(card,"定位城市",func(): close(); game.focus_city(id),Vector2(0,32))
			city_service_buttons[id]=game._button(card,"规划接入",func():
				var live: Dictionary=game.sim.region.city_status(id)
				var phase: String=str(live.get("service_phase","active"))
				if phase=="prospect": _commit(game.sim.plan_city(id))
				elif phase=="planned": _commit(game.sim.start_city_service(id))
			,Vector2(0,36))
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
		var phase: String=str(city.get("service_phase","active"))
		city_service_buttons[city.id].visible=phase!="active" and not game._campaign_active()
		city_service_buttons[city.id].text="规划接入 · 尚未承担服务责任" if phase=="prospect" else "开通服务 · 开始计费与供电责任"
	city_picker.visible = bool(region.active)
	city_heading.visible = bool(region.active)
	region_map.selected_id = selected_city
	current_goal.text = "尚未选择长期目标。选择一个方向，持续改善你的电网。"
	for challenge in game.sim.sandbox_goals():
		if challenge_labels.has(challenge.id):
			challenge_labels[challenge.id].text = "%s · 进度 %.0f%%%s" % ["当前目标" if game.sim.sandbox_goal==challenge.id else "可选方向",float(challenge.progress)*100," · ✓ 已达成" if challenge.complete else ""]
		if game.sim.sandbox_goal==challenge.id:
			current_goal.text = "%s · %.0f%%%s\n%s" % [challenge.name,float(challenge.progress)*100," · ✓ 已达成" if challenge.complete else "",challenge.description]
			current_goal.text+="\n最佳连续 %.1f 小时" % float(challenge.get("best_hours",0))
			if not str(challenge.get("interruption","")).is_empty(): current_goal.text+="\n中断原因："+str(challenge.interruption)

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
		_storage_settings(building,settings)
	if building.kind=="hydro":
		settings.environmental_release = release_input.value/100
	if building.kind=="substation":
		settings.protection_margin = protection_input.value/100
	if building.kind in ["steam","coal","ccgt"]:
		settings.flexible_mode = flexible_input.button_pressed
	var result: Dictionary=game.sim.configure_facility(selected_facility,settings,"remote" if facility_method.selected==0 else "field")
	if result.get("ok",false) and settings.has("storage_intent"):
		# The visible draft must describe the actual submitted scope, including
		# the deliberate inherit -> per-device override caused by reserve editing.
		_capture_facility()
		var submitted: Dictionary=drafts.retain(str(selected_facility),_effective_facility(building))
		submitted.intent=str(settings.storage_intent)
		drafts.retain(str(selected_facility),_effective_facility(building),submitted)
		_write_facility(submitted)
	_commit(result,false)

func _storage_intent_selected(_index: int) -> void:
	var building: Dictionary=game.sim.get_building(selected_facility)
	if building.is_empty(): return
	if storage_intent_input.selected==4:
		# A deliberate transition to legacy imports the original legacy fields,
		# rather than silently turning an inherited effective reserve into one.
		reserve_input.value=float(building.get("reserve_soc",0))*100
		storage_input.select(maxi(0,["auto","hold","peak"].find(str(building.get("storage_mode","auto")))))
	_refresh_storage_controls(true)
	_capture_facility()

func _refresh_storage_controls(storage: bool) -> void:
	if not storage: return
	var legacy: bool=storage_intent_input.selected==4
	controls["储能运行策略"].visible=legacy
	controls["削峰起点（持续4小时）"].visible=legacy or storage_intent_input.selected==2
	reserve_input.editable=not legacy or game.sim.evolution.has_technology("regional_planning")
	reserve_input.tooltip_text="旧版设施备用需要区域负荷规划；与旧版市场备用分别约束。" if legacy else "当前有效备用电量。修改后将采用此设施的独立方案，停止继承全网备用。"
	controls["保留荷电 %"].get_child(0).text="旧版设施备用 %" if legacy else "有效备用电量 %"
	storage_intent_input.set_item_disabled(2,not game.sim.evolution.has_technology("smart_storage") or not game.sim.feature_enabled("storage_control"))
	storage_intent_input.set_item_disabled(3,not game.sim.feature_enabled("market"))

func _storage_settings(building: Dictionary, settings: Dictionary) -> void:
	var effective: Dictionary=_effective_facility(building)
	var intent: String=["inherit","supply","peak","arbitrage","legacy_custom"][maxi(0,storage_intent_input.selected)]
	var reserve_changed: bool=not is_equal_approx(reserve_input.value,float(effective.reserve))
	var mode_changed: bool=storage_input.selected!=int(effective.storage)
	var peak_changed: bool=not is_equal_approx(peak_input.value,float(effective.peak))
	if intent=="legacy_custom":
		var explicit_transition: bool=str(effective.intent)!="legacy_custom"
		if explicit_transition:
			settings.storage_intent="legacy_custom"
			settings.storage_mode=["auto","hold","peak"][storage_input.selected]
			settings.reserve_soc=reserve_input.value/100.0
		elif mode_changed or reserve_changed:
			settings.storage_intent="legacy_custom"
			if mode_changed: settings.storage_mode=["auto","hold","peak"][storage_input.selected]
			if reserve_changed: settings.reserve_soc=reserve_input.value/100.0
	else:
		var raw_intent: String=str(building.get("storage_intent","inherit"))
		if reserve_changed:
			# An effective reserve edited while inheriting becomes an explicit
			# override of the current resolved intent; keep unrelated old fields out.
			var resolved: Dictionary=game.sim.storage_status(selected_facility)
			settings.storage_intent=str(resolved.get("intent","supply")) if intent=="inherit" else intent
			settings.storage_reserve=reserve_input.value/100.0
		elif intent!=raw_intent:
			settings.storage_intent=intent
			if intent!="inherit": settings.storage_reserve=reserve_input.value/100.0
	if peak_changed: settings.peak_hour=peak_input.value

func _choose_build(kind: String) -> void:
	close()
	if not game.sim.can_build(kind).ok: return
	game.build_kind = kind
	game._set_tool("build")

func _advance() -> void:
	if game.has_method("advance_management"):
		game.advance_management(1.0)
		return
	game.sim.step(1.0)
	game._sync_world(true)
	game._update_hud()
	game._update_inspector()
	refresh()
	message_label.text = "已推进 1 游戏小时；研发、城市变化、机组启动和运营费用已结算。"

func _commit(result: Dictionary, sync_inputs: bool=true) -> void:
	game._apply(result)
	game._sync_world(true)
	game._update_hud()
	game._update_inspector()
	refresh(sync_inputs)
	message_label.text = ("✓ " if result.get("ok",false) else "! ")+str(result.get("message","操作完成"))
	message_label.add_theme_color_override("font_color",TEAL if result.get("ok",false) else ORANGE)

func create_facility_editor(parent: Node, id: int) -> Control:
	if visible: _capture_facility()
	var editor:=FacilityEditor.new()
	parent.add_child(editor)
	editor.setup(self,id)
	return editor

func _update_technology_map() -> void:
	if technology_map==null: return
	var nodes: Array=[]
	for id in Evolution.TECHNOLOGIES:
		var spec: Dictionary=Evolution.TECHNOLOGIES[id]
		if int(spec.era)!=selected_era or not _technology_allowed(id): continue
		var previous: Array[String]=[]
		for required in spec.requires:
			if int(Evolution.TECHNOLOGIES[required].era)!=selected_era: previous.append(str(Evolution.TECHNOLOGIES[required].name))
		nodes.append({"id":id,"name":spec.name,"requires":spec.requires,"previous":" / ".join(previous),"complete":id in game.sim.evolution.unlocked,"selected":id==selected_technology,"project":str(game.sim.evolution.project)==id})
	technology_map.custom_minimum_size.y=maxf(96,ceilf(float(nodes.size())/3.0)*100+12)
	technology_map.set_snapshot({"nodes":nodes})

func _update_comparison_action() -> void:
	if comparison_choice==null or comparison_choice.selected<0: return
	var kind: String=str(comparison_choice.get_item_metadata(comparison_choice.selected))
	comparison_choose.disabled=not game.sim.can_build(kind).ok or float(game.sim.cash)<float(game.sim.catalog[kind].price)
	comparison_choose.text="选择并选址" if not comparison_choose.disabled else "需要解锁或资金"
