extends Control
## Player-facing network operations. All truth-sensitive electrical data uses observations.
const NetworkMap = preload("res://scripts/ui/digital_map.gd")
const Shell = preload("res://scripts/ui/management_shell.gd")
const Drafts = preload("res://scripts/ui/config_drafts.gd")
const VisualChart = preload("res://scripts/ui/center_charts.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const TEAL := Color("77dbc0")
const BLUE := Color("81c9ee")
const CREAM := Color("f2eddb")
const MUTED := Color("95b0b6")
const ORANGE := Color("efbb7d")
const RED := Color("f38a79")
var game: Node
var cards: Dictionary = {}
var tabs: TabContainer
var network_map: Control
var device_picker: OptionButton
var drill_target: OptionButton
var link_from: OptionButton
var link_to: OptionButton
var link_kind: OptionButton
var link_picker: OptionButton
var circuit_picker: OptionButton
var attack_kind: OptionButton
var policy_picker: OptionButton
var device_info: Label
var commission_button: Button
var telemetry_button: Button
var response_button: Button
var link_info: Label
var circuit_info: Label
var security_info: Label
var cost_info: Label
var link_quote: Label
var incidents_box: VBoxContainer
var jobs_box: VBoxContainer
var policy_button: Button
var upgrade_button: Button
var remote_button: Button
var message_label: Label
var selected_device := 10
var selected_link := -1
var selected_circuit := 1
var _asset_signature := ""
var _link_signature := ""
var _circuit_signature := ""
var syncing := false
var _incidents_signature := ""
var _jobs_signature := ""
var incident_labels: Dictionary = {}
var job_labels: Dictionary = {}
var drafts: RefCounted = Drafts.new()
var policy_draft: Label
var _inputs_ready := false
var _map_selection := Vector3i(-2,-2,-2)
var readiness_chart: Control
var queue_chart: Control

func reset_session() -> void:
	drafts.clear()
	_inputs_ready=false
	_map_selection=Vector3i(-2,-2,-2)
	_asset_signature=""; _link_signature=""; _circuit_signature=""; _incidents_signature=""; _jobs_signature=""
	selected_device=10; selected_link=-1; selected_circuit=1
	if tabs!=null: tabs.current_tab=0
	if link_kind!=null: link_kind.select(0)
	if attack_kind!=null: attack_kind.select(0)
	if link_from!=null: link_from.select(-1)
	if link_to!=null: link_to.select(-1)

func inherit_selection(building_id: int=-1,line_id: int=-1,comm_line_id: int=-1) -> void:
	var selected := Vector3i(building_id,line_id,comm_line_id)
	if selected==_map_selection: return
	_map_selection=selected
	if building_id>=0 and not game.sim.get_building(building_id).is_empty(): selected_device=building_id
	if line_id>=0 and not game.sim.get_line(line_id).is_empty(): selected_circuit=line_id
	if comm_line_id>=0: selected_link=comm_line_id

func setup(owner_game: Node) -> void:
	game = owner_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	hide()
func open() -> void:
	inherit_selection(int(game.selected_id),int(game.selected_line),int(game.selected_comm_line))
	game._prepare_center(self)
	refresh(true)
	show()
func close() -> void:
	_capture_policy()
	hide()
	if drafts.dirty("security"): game._notify("安全策略草案已保留，尚未应用。")
	game._update_hud()
	game._update_inspector()
func _build() -> void:
	var body: VBoxContainer = Shell.build(self,"运维 · 数字电网", "推进 15 分钟",_advance,close)
	var stats := HFlowContainer.new()
	stats.add_theme_constant_override("h_separation",20)
	stats.add_theme_constant_override("v_separation",6)
	body.add_child(stats)
	for spec in [["coverage","通信可达","0%"],["trusted","可信路径","0%"],["observed","可靠观测","0 / 0"],["links","在线链路","0 / 0"],["incident","已检测事件","0"],["pending","操作队列","0"]]:
		var metric: HBoxContainer = game._row(stats,6)
		game._label(metric,spec[1],14,MUTED)
		cards[spec[0]] = game._label(metric,spec[2],22,BLUE)
	tabs = TabContainer.new()
	tabs.use_hidden_tabs_for_min_size=false
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size",15)
	tabs.add_theme_color_override("font_selected_color",BLUE)
	tabs.add_theme_color_override("font_unselected_color",MUTED)
	body.add_child(tabs)
	tabs.tab_changed.connect(_scroll_page_top)
	_build_network()
	_build_operations()
	_build_security()
	_build_incidents()
	message_label = _text(body,"通信与供电独立运行 · 配置修改后应用，观测刷新不推进时间。",MUTED)
func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var v: VBoxContainer = game._column(scroll,12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v
func _scroll_page_top(_index: int) -> void:
	var outer: Node=tabs.get_parent().get_parent()
	if outer is ScrollContainer: outer.scroll_vertical=0
func _box(parent: Node, width: float) -> VBoxContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",game._style(Color("192f3b"),6))
	parent.add_child(card)
	return game._column(card,9)
func _text(parent: Node, text: String, color: Color=MUTED, width: float=540, font_size: int=12) -> Label:
	var label: Label = game._label(parent,text,font_size,color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
func _select(parent: Node, label: String, width: float=250) -> OptionButton:
	var row: VBoxContainer = game._column(parent,4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game._label(row,label,14,MUTED)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(0,36)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.fit_to_longest_item = false
	picker.clip_text = true
	picker.add_theme_stylebox_override("normal",game._style(Color("102c38"),7))
	picker.add_theme_color_override("font_color",CREAM)
	picker.add_theme_font_size_override("font_size",14)
	row.add_child(picker)
	return picker

func _split(parent: Node, columns: int=2) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation",16)
	grid.add_theme_constant_override("v_separation",16)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)
	var collapse_width := 900 if columns==2 else 520
	grid.resized.connect(func(): grid.columns=1 if grid.size.x<collapse_width else columns)
	return grid

func _primary(button: Button) -> Button:
	button.add_theme_stylebox_override("normal",game._style(Color("245348"),6,TEAL.darkened(.3)))
	button.add_theme_color_override("font_color",CREAM)
	return button

func _build_network() -> void:
	var tab := _tab("通信拓扑")
	var row := _split(tab)
	var graph_box := _box(row,750)
	game._label(graph_box,"通信网络",18,CREAM)
	network_map = NetworkMap.new()
	network_map.node_selected.connect(_select_device)
	network_map.link_selected.connect(func(id: int): selected_link=id; _select_id(link_picker,id); tabs.current_tab=1; refresh())
	graph_box.add_child(network_map)
	network_map.custom_minimum_size = Vector2(0,300)
	_text(graph_box,"点击节点查看设备，点击链路进入维护。",MUTED)
	var details := _box(row,440)
	game._label(details,"所选设备",18,BLUE)
	device_picker = _select(details,"选择设备",276)
	device_picker.item_selected.connect(func(_i: int): _select_device(_picked(device_picker)))
	device_info = _text(details,"",CREAM,400,13)
	readiness_chart=VisualChart.new()
	readiness_chart.mode="conditions"
	readiness_chart.custom_minimum_size=Vector2(0,98)
	details.add_child(readiness_chart)
	telemetry_button=game._button(details,"遥测研究",func(): game._research(); refresh(),Vector2(0,36))
	commission_button = game._button(details,"投运数字网关",func():
		var building: Dictionary=game.sim.get_building(selected_device)
		_commit(game.sim.commission_device(selected_device,"root" if building.get("kind","") in ["sensor","control"] else "device"))
	,Vector2(0,36))
	game._button(details,"隔离所选设备",func(): _commit(game.sim.isolate_device(selected_device,true)),Vector2(0,34))
	game._button(details,"解除设备隔离",func(): _commit(game.sim.isolate_device(selected_device,false)),Vector2(0,34))
	_primary(game._button(details,"恢复 / 修补设备 · ¥900",func(): _commit(game.sim.recover_device(selected_device)),Vector2(0,34)))
	var build_toggle: Button = game._button(tab,"＋ 新建通信连接",func(): pass,Vector2(0,36),true)
	var construction: VBoxContainer = game._column(tab,10)
	construction.hide()
	build_toggle.toggled.connect(func(pressed: bool): construction.visible=pressed)
	var connect_row := _split(construction,3)
	link_from = _select(connect_row,"起点",250)
	link_to = _select(connect_row,"终点",250)
	link_kind = _select(connect_row,"介质",160)
	link_kind.add_item("光纤")
	link_kind.add_item("无线")
	for picker in [link_from,link_to,link_kind]:
		picker.item_selected.connect(func(_i: int): _update_quote())
	var actions := _split(construction,3)
	_primary(game._button(actions,"新建通信链路",_connect,Vector2(0,36)))
	game._button(actions,"在地图布设通信线  4",_map_link,Vector2(0,36))
	game._button(actions,"查看通信地图图层",func(): close(); game.overlay="comm"; game._sync_world(true),Vector2(0,36))
	link_quote=_text(construction,"",ORANGE)
	_text(construction,"光纤稳定但造价较高；无线有距离、时延和风暴风险。失电后 UPS 只能临时维持通信。",MUTED)
func _build_operations() -> void:
	var tab := _tab("链路与故障处置")
	var row := _split(tab)
	var link_box := _box(row,585)
	game._label(link_box,"通信链路维护",18,BLUE)
	link_picker = _select(link_box,"选择链路",380)
	link_picker.item_selected.connect(func(_i: int): selected_link=_picked(link_picker); refresh())
	link_info = _text(link_box,"",CREAM)
	game._button(link_box,"开通 / 停用通信链路",func(): _commit(game.sim.toggle_communication(selected_link)),Vector2(0,36))
	game._button(link_box,"修复通信链路 · ¥650",func(): _commit(game.sim.repair_communication(selected_link)),Vector2(0,36))
	game._button(link_box,"升级通信链路 · ¥2k",func(): _commit(game.sim.upgrade_communication(selected_link)),Vector2(0,36))
	_text(link_box,"通信中断会使遥测过时、远程指令失败、自愈停止。供电仍由本地物理设备和保护系统决定。")
	var circuit_box := _box(row,585)
	game._label(circuit_box,"电力线路处置",18,CREAM)
	circuit_picker = _select(circuit_box,"电力线路",380)
	circuit_picker.item_selected.connect(func(_i: int): selected_circuit=_picked(circuit_picker); refresh())
	circuit_info = _text(circuit_box,"",CREAM)
	response_button=game._button(circuit_box,"启动需求响应",func(): _commit(game.sim.demand_response()),Vector2(0,36))
	remote_button = _primary(game._button(circuit_box,"发送远程开关指令",_remote,Vector2(0,36)))
	game._button(circuit_box,"派现场开关队 · ¥350",func(): _commit(game.sim.field_switch(selected_circuit)),Vector2(0,36))
	game._button(circuit_box,"巡检定位 · ¥500",func(): _commit(game.sim.patrol_line(selected_circuit)),Vector2(0,36))
	_text(circuit_box,"远程命令有回执延迟，到达时会重新检查路径和权限。未知故障先巡检；可信遥测定位能省下现场查线时间。",ORANGE)
func _build_security() -> void:
	var tab := _tab("安全策略与演练")
	var row := _split(tab)
	var policy := _box(row,585)
	game._label(policy,"安全策略",18,CREAM)
	policy_picker = _select(policy,"访问策略",310)
	for text in ["开放互联","网络分区","零信任校验"]:
		policy_picker.add_item(text)
	policy_button = _primary(game._button(policy,"应用安全策略",_apply_policy,Vector2(0,36)))
	policy_draft=_text(policy,"",ORANGE)
	game._button(policy,"重置安全策略草案",reset_policy_draft,Vector2(0,34))
	security_info = _text(policy,"",BLUE)
	upgrade_button = game._button(policy,"升级安全防护",func(): _commit(game.sim.upgrade_security()),Vector2(0,36))
	cost_info = _text(policy,"",ORANGE)
	_text(policy,"分区限制事件扩散；零信任拒绝不可信控制，但会增加校验时延和运维成本。在线安全中心可以改善检测与响应。")
	var drills := _box(row,585)
	game._label(drills,"网络安全演练",18,BLUE)
	drill_target = _select(drills,"目标设备")
	drill_target.item_selected.connect(func(_i: int): _select_device(_picked(drill_target)))
	attack_kind = _select(drills,"演练类型",310)
	for text in ["DoS · 通信服务中断","遥测欺骗 · 信息不可置信","非法控制 · 恶意断路"]:
		attack_kind.add_item(text)
	_text(drills,"这是本地注入演练，可绕过外部接入路径；会真实影响已投运设备，请准备恢复方案。",ORANGE)
	var drill_button: Button=game._button(drills,"启动网络安全演练",_drill,Vector2(0,40))
	drill_button.add_theme_color_override("font_color",ORANGE)
	var builds := _split(drills,3)
	for pair in [["control","调度中心"],["relay","通信中继"],["soc","安全中心"]]:
		var kind: String = pair[0]
		game._button(builds,pair[1],func(): _build_kind(kind),Vector2(0,36))
	_text(drills,"建设设施后同时规划供电和通信。隔离可以遏制事件，也会切断设备遥测；修补恢复需要时间。",ORANGE)
func _build_incidents() -> void:
	var tab := _tab("告警与指令回执")
	var row := _split(tab)
	var alerts := _box(row,585)
	game._label(alerts,"已经检测到的事件",18,ORANGE)
	incidents_box = game._column(alerts,12)
	var jobs := _box(row,585)
	game._label(jobs,"远程指令与现场作业",18,BLUE)
	jobs_box = game._column(jobs,12)
	_text(tab,"未确认的网络异常不会透露真实攻击目标。安全设施与策略改善检测，故障恢复仍需可信观测、可达控制路径或现场作业。",MUTED,1200)
func _picked(picker: OptionButton) -> int:
	return picker.get_item_id(picker.selected) if picker.selected>=0 else -1
func _select_id(picker: OptionButton, id: int) -> void:
	for i in picker.item_count:
		if picker.get_item_id(i)==id:
			picker.select(i)
			return
func _select_device(id: int) -> void:
	selected_device=id
	_select_id(device_picker,id)
	_select_id(drill_target,id)
	refresh()
func _connect() -> void:
	_commit(game.sim.connect_communication(_picked(link_from),_picked(link_to),"fiber" if link_kind.selected==0 else "wireless"))
func _map_link() -> void:
	close()
	game.communication_kind = "fiber" if link_kind.selected==0 else "wireless"
	game._set_tool("datalink")
	game._sync_world(true)
func _remote() -> void:
	_commit(game.sim.remote_switch(selected_circuit))
func _drill() -> void:
	_commit(game.sim.trigger_cyberattack(["dos","spoof","intrusion"][attack_kind.selected],selected_device))
func _build_kind(kind: String) -> void:
	close()
	game.build_kind=kind
	game._set_build_category("digital")
	game._set_tool("build")
func _advance() -> void:
	if game.has_method("advance_management"):
		game.advance_management(.25)
		return
	game.sim.step(.25)
	game._sync_world(true)
	game._update_hud()
	game._update_inspector()
	refresh()
	message_label.text = "已推进 15 游戏分钟；链路、控制回执、巡检与费用已更新。"
	message_label.add_theme_color_override("font_color",BLUE)
func _commit(result: Dictionary) -> void:
	game._apply(result)
	game._sync_world(true)
	game._update_hud()
	game._update_inspector()
	refresh(true)
	message_label.text=("✓ " if result.get("ok",false) else "! ")+str(result.get("message","操作完成"))
	message_label.add_theme_color_override("font_color",TEAL if result.get("ok",false) else ORANGE)
func refresh(sync_inputs: bool=false) -> void:
	telemetry_button.text=game._digital_research_caption()
	telemetry_button.disabled=not game._digital_research_available()
	response_button.visible=game.sim.feature_enabled("demand_response")
	response_button.disabled=int(game.sim.research_level)<2
	if game == null or game.sim.get("digital") == null:
		return
	var sim: RefCounted=game.sim
	var state: Dictionary=sim.digital.state
	_capture_policy()
	network_map.sim=sim
	network_map.selected_id=selected_device
	network_map.queue_redraw()
	var coverage: float=sim.totals.get("comm_coverage",0)
	var trusted: float=sim.totals.get("comm_trusted",0)
	cards.coverage.text="%.0f%%" % (coverage*100 if coverage<=1 else coverage)
	cards.trusted.text="%.0f%%" % (trusted*100 if trusted<=1 else trusted)
	cards.links.text="%d / %d" % [sim.totals.get("comm_online_links",0),sim.totals.get("comm_total_links",0)]
	var observed:=0
	for line in sim.lines:
		if sim.line_observation(int(line.id)).get("visibility","") in ["verified","patrol"]:
			observed+=1
	cards.observed.text="%d / %d" % [observed,sim.lines.size()]
	var detected:=0
	for incident in sim.digital.incidents:
		if incident.get("detected",false) and incident.get("status","") not in ["resolved","blocked"]:
			detected+=1
	cards.incident.text=str(detected)
	cards.pending.text=str(sim.digital.pending_commands.size()+sim.digital.field_jobs.size())
	_refresh_pickers(sync_inputs)
	_update_quote()
	var status: Dictionary=sim.communication_status(selected_device)
	var latency: float=status.get("latency_ms",-1)
	device_info.text="%s\n可信：%s  ·  时延 %s\nUPS 剩余 %.1f 小时\n%s" % [("调度根" if status.get("root",false) else "普通网关")+" · "+("路径可达" if status.get("reachable",false) else "与调度失联"),"已校验" if status.get("trusted",false) else "未校验","%.0f ms" % latency if latency>=0 else "不可达",status.get("ups_remaining",0),status.get("reason","")]
	var building: Dictionary=sim.get_building(selected_device)
	var observation: Dictionary=sim.facility_observation(selected_device)
	var live_observation: bool=observation.get("visibility","")=="verified"
	var powered: bool=bool(status.get("reachable",false)) or float(status.get("ups_remaining",0))>0
	readiness_chart.set_snapshot({"steps":[
		{"label":"供电/UPS","ok":powered,"detail":"维持运行" if powered else "需核实","known":powered or str(status.get("reason","")).contains("UPS")},
		{"label":"通信路径","ok":status.get("reachable",false),"detail":"可达" if status.get("reachable",false) else "中断"},
		{"label":"可信校验","ok":status.get("trusted",false),"detail":"可信" if status.get("trusted",false) else "待核实"},
		{"label":"新鲜观测","ok":live_observation,"detail":"实时" if live_observation else "待更新"},
		{"label":"远控许可","ok":sim.digital.can_configure(sim,selected_device),"detail":"可执行" if sim.digital.can_configure(sim,selected_device) else "未就绪"}
	]})
	var root_capable: bool=building.get("kind","") in ["sensor","control"]
	commission_button.text="调度根已投运" if status.get("root",false) else ("投运为调度根" if root_capable else ("数字网关已投运" if status.get("commissioned",false) else "投运数字网关"))
	commission_button.disabled=(status.get("root",false) or (status.get("commissioned",false) and not root_capable)) or (sim.evolution.heritage and not sim.evolution.has_technology("scada"))
	commission_button.visible=not status.get("commissioned",false) or (root_capable and not status.get("root",false))
	commission_button.tooltip_text="智能终端和调度中心可显式设置为调度根；角色会随存档保存，不依赖建筑编号。"
	if status.get("compromised",false):
		device_info.text+="\n已确认安全异常：隔离并修补此设备。"
	_refresh_link()
	_refresh_circuit()
	var policy_values: Dictionary=drafts.retain("security",_effective_policy())
	policy_picker.select(int(policy_values.mode))
	_inputs_ready=true
	var policies: Array[String]=["开放互联","网络分区","零信任校验"]
	policy_draft.text="未应用草案 · %s → %s" % [policies[int(drafts.baselines.security.mode)],policies[policy_picker.selected]] if drafts.dirty("security") else "✓ 当前策略已生效"
	security_info.text="安全防护 L%d  ·  已阻挡 %d 次事件\n远程成功 %d 次 / 拒绝 %d 次" % [state.get("security_level",0),state.get("blocked_attacks",0),state.get("remote_success",0),state.get("remote_rejected",0)]
	var level:=int(state.get("security_level",0))
	upgrade_button.text="安全研究完成" if level>=2 else "↑ 升级安全防护 · ¥%s" % ("10k" if level==0 else "22k")
	upgrade_button.disabled=level>=2
	cost_info.text="通信 ¥%.0f/h · 安全 ¥%.0f/h\n成本已计入经营账本的运维项。" % [sim.totals.get("communication_cost",0),sim.totals.get("security_cost",0)]
	_refresh_incidents()

func _effective_policy() -> Dictionary:
	return {"mode":maxi(0,["open","segmented","zero_trust"].find(game.sim.digital.state.get("policy","open")))}

func _capture_policy() -> void:
	if _inputs_ready: drafts.retain("security",_effective_policy(),{"mode":policy_picker.selected})

func _capture_drafts() -> void:
	_capture_policy()

func reset_policy_draft() -> void:
	drafts.reset("security",_effective_policy())
	policy_picker.select(int(drafts.values.security.mode))
	refresh(false)
	message_label.text="已重置安全策略草案；其他选择保持不变。"

func _apply_policy() -> void:
	_capture_policy()
	var result: Dictionary=game.sim.set_security_policy(["open","segmented","zero_trust"][policy_picker.selected])
	if result.get("ok",false):
		drafts.reset("security",_effective_policy())
		policy_picker.select(int(drafts.values.security.mode))
	_commit(result)
func _refresh_pickers(force: bool) -> void:
	var signature:=str(game.sim.buildings.map(func(b: Dictionary): return b.id))
	if force or signature!=_asset_signature:
		var old_from:=_picked(link_from)
		var old_to:=_picked(link_to)
		for picker in [device_picker,drill_target,link_from,link_to]:
			picker.clear()
			for b in game.sim.buildings:
				picker.add_item("%02d · %s" % [b.id,b.name],int(b.id))
		_select_id(device_picker,selected_device)
		if device_picker.selected>=0:
			selected_device=_picked(device_picker)
		_select_id(drill_target,selected_device)
		_select_id(link_from,old_from if old_from>=0 else 10)
		_select_id(link_to,old_to if old_to>=0 else 2)
		_asset_signature=signature
	var linksig:=str(game.sim.digital.links.map(func(link: Dictionary): return link.id))
	if force or linksig!=_link_signature:
		link_picker.clear()
		for link in game.sim.digital.links:
			link_picker.add_item("C%02d  ·  %d ↔ %d  ·  %s" % [link.id,link.a,link.b,"光纤" if link.kind=="fiber" else "无线"],int(link.id))
		_select_id(link_picker,selected_link)
		selected_link=_picked(link_picker)
		_link_signature=linksig
	var circuitsig:=str(game.sim.lines.map(func(line: Dictionary): return line.id))
	if force or circuitsig!=_circuit_signature:
		circuit_picker.clear()
		for line in game.sim.lines:
			circuit_picker.add_item("E%02d  ·  %d ↔ %d" % [line.id,line.a,line.b],int(line.id))
		_select_id(circuit_picker,selected_circuit)
		selected_circuit=_picked(circuit_picker)
		_circuit_signature=circuitsig
func _refresh_link() -> void:
	var link: Dictionary={}
	for item in game.sim.digital.links:
		if int(item.id)==selected_link:
			link=item
	if link.is_empty():
		link_info.text="选择通信链路，查看连接与维护状态。"
		return
	link_info.text="C%02d · %s\n状态：%s  ·  时延 %.0f ms\n健康 %.0f%%  ·  维修剩余 %.2f 小时" % [link.id,"光纤" if link.kind=="fiber" else "无线","通信故障" if link.get("fault",false) else ("已开通" if link.get("online",true) else "已停用"),link.get("latency_ms",0),link.get("health",100),link.get("repair_remaining",0)]
func _update_quote() -> void:
	if link_quote==null or game==null or game.sim.get("digital")==null:
		return
	var kind: String="fiber" if link_kind.selected==0 else "wireless"
	var cost: float=game.sim.digital.link_cost(game.sim,_picked(link_from),_picked(link_to),kind)
	link_quote.text="所选链路造价 ¥%s · 每小时维护 ¥%d · 无线距离：普通网关 6 格，中继站 10 格" % [game._number(cost),8 if kind=="fiber" else 4]
func _refresh_circuit() -> void:
	var observation: Dictionary=game.sim.line_observation(selected_circuit)
	var visibility:=str(observation.get("visibility","unknown"))
	var names: Dictionary={"unknown":"未观测","stale":"缓存已过时","verified":"可信遥测","suspect":"遥测可疑","patrol":"现场核实"}
	var flow: Variant=observation.get("flow")
	circuit_info.text="观测：%s  ·  记录年龄 %.2f 小时\n%s：%s\n%s" % [names.get(visibility,visibility),observation.get("age_hours",0),"上次读数" if visibility=="stale" else "潮流","%.2f MW" % absf(float(flow)) if flow!=null else "不可用",observation.get("reason","")]
	remote_button.disabled=not game.sim.digital.can_control(game.sim,selected_circuit)
	remote_button.tooltip_text="需要一级研究、新鲜遥测，以及两端可信且不超过 250ms 的控制路径。"
func _refresh_incidents() -> void:
	var detected: Array = []
	for incident in game.sim.digital.incidents:
		if incident.get("detected",false):
			detected.append(incident)
	var signature := str(detected.map(func(incident: Dictionary): return "%d:%d" % [incident.id,incident.target_id]))
	if signature != _incidents_signature or incidents_box.get_child_count()==0:
		game._clear_children(incidents_box)
		incident_labels.clear()
		for incident in detected:
			incident_labels[incident.id] = _text(incidents_box,"",ORANGE)
			var target_id: int=incident.get("target_id",-1)
			game._button(incidents_box,"查看设备与恢复",func(): _select_device(target_id); tabs.current_tab=0,Vector2(0,34))
		if detected.is_empty():
			_text(incidents_box,"当前没有已确认的网络安全事件。",TEAL)
		_incidents_signature=signature
	for incident in detected:
		var kinds: Dictionary={"dos":"拒绝服务","spoof":"遥测欺骗","intrusion":"非法控制"}
		var states: Dictionary={"active":"待处置","blocked":"已阻挡","resolved":"已恢复"}
		var affected:=PackedStringArray()
		for id in incident.get("affected_ids",[]):
			affected.append("%02d" % int(id))
		var active: bool=incident.get("status","")=="active"
		var label: Label=incident_labels[incident.id]
		label.text="%s · 设备 %02d · %s\n%s\n已检测影响：%s\n%s" % [kinds.get(incident.get("kind",""),"异常"),incident.get("target_id",0),states.get(incident.get("status",""),"待处理"),incident.get("description",""),"、".join(affected),"建议：隔离受影响设备，修补恢复后解除隔离。" if active else "事件已结束，可检查设备与通信路径。"]
		label.add_theme_color_override("font_color",ORANGE if active else TEAL)
	var jobs: Array=[]
	jobs.append_array(game.sim.digital.pending_commands)
	jobs.append_array(game.sim.digital.field_jobs)
	var receipts: Array=[]
	if game.sim.has_method("operation_receipts"):
		for receipt in game.sim.operation_receipts():
			if receipt.get("phase","") in ["executed","rejected"]: receipts.append(receipt)
	var job_signature:=str(jobs.map(func(job: Dictionary): return job.id))+str(receipts)
	if job_signature != _jobs_signature or jobs_box.get_child_count()==0:
		game._clear_children(jobs_box)
		job_labels.clear()
		for job in jobs:
			job_labels[job.id]=_text(jobs_box,"",BLUE)
		if jobs.is_empty():
			_text(jobs_box,"没有等待中的指令或现场作业。",TEAL)
		if not receipts.is_empty():
			_text(jobs_box,"最近执行回执（排队成功不代表已生效）",CREAM)
			for index in range(receipts.size()-1,maxi(-1,receipts.size()-9),-1):
				var receipt: Dictionary=receipts[index]
				var executed: bool=receipt.get("phase","")=="executed"
				var target_kind: String="building" if receipt.get("action","")=="facility" else "line"
				var target_id: int=int(receipt.get("target_id",-1))
				_text(jobs_box,"%s · #%d · %s\n%s" % ["✓ 已执行" if executed else "! 已拒绝，未生效",int(receipt.get("command_id",-1)),("设施 " if target_kind=="building" else "线路 ")+str(target_id),str(receipt.get("message","查看所选对象与调度日志，核实最新状态。"))],TEAL if executed else ORANGE)
				game._button(jobs_box,"定位回执对象",func(): close(); game.focus_target(target_kind,target_id),Vector2(0,30))
		_jobs_signature=job_signature
	for job in jobs:
		var kinds: Dictionary={"switch":"现场开关","patrol":"巡检定位"}
		var facility: bool=job.get("kind","")=="facility"
		var field: bool=game.sim.digital.field_jobs.has(job)
		job_labels[job.id].text="在途 · 尚未生效 · %s\n%s%02d · 剩余 %.2f 小时\n%s" % [("现场设施设置" if field else "远程设施设置") if facility else kinds.get(job.get("kind",""),"远程指令"),"设施 " if facility else "E",job.get("building_id",0) if facility else job.get("line_id",0),job.get("remaining",0),"现场作业不依赖通信路径。" if field else "指令到达时再次验证通信与控制权限。"]
