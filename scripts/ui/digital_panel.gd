extends Control
## Player-facing network operations. All truth-sensitive electrical data uses observations.
const NetworkMap = preload("res://scripts/ui/digital_map.gd")
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
var link_from: OptionButton
var link_to: OptionButton
var link_kind: OptionButton
var link_picker: OptionButton
var circuit_picker: OptionButton
var attack_kind: OptionButton
var policy_picker: OptionButton
var device_info: Label
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
func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(.02,.06,.09,.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel: PanelContainer = game._panel(self,Vector2(144,50),Vector2(1312,900),Color("102c38"))
	var body: VBoxContainer = game._column(panel,12)
	var header: HBoxContainer = game._row(body,16)
	var title: VBoxContainer = game._column(header,1)
	game._label(title,"数字电网运行中心  /  NETWORK OPERATIONS",11,BLUE)
	game._label(title,"看得见，控得住，恢复得更快。",27,CREAM)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	game._label(header,"规划中 · 时间暂停",11,MUTED)
	game._button(header,"推进 15 分钟",_advance,Vector2(128,40))
	game._button(header,"返回电网  Esc",close,Vector2(128,40))
	var stats: HBoxContainer = game._row(body,10)
	for spec in [["coverage","通信可达","0%"],["trusted","可信路径","0%"],["observed","可靠观测","0 / 0"],["links","在线链路","0 / 0"],["incident","已检测事件","0"],["pending","操作队列","0"]]:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel",game._style(Color("1b3b48"),10))
		stats.add_child(card)
		var col: VBoxContainer = game._column(card,3)
		game._label(col,spec[1],11,MUTED)
		cards[spec[0]] = game._label(col,spec[2],23,BLUE)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(0,600)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size",15)
	tabs.add_theme_color_override("font_selected_color",BLUE)
	tabs.add_theme_color_override("font_unselected_color",MUTED)
	tabs.add_theme_stylebox_override("panel",game._style(Color("153440"),10))
	tabs.add_theme_stylebox_override("tab_selected",game._style(Color("234954"),8,BLUE*Color(1,1,1,.4)))
	tabs.add_theme_stylebox_override("tab_unselected",game._style(Color("102b37"),8))
	body.add_child(tabs)
	_build_network()
	_build_operations()
	_build_security()
	_build_incidents()
	message_label = game._label(body,"通信链路与电力线路独立建设。配置与观测刷新不推进时间。",12,MUTED)
func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var v: VBoxContainer = game._column(scroll,12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v
func _box(parent: Node, width: float) -> VBoxContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = width
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",game._style(Color("1b3c49"),10))
	parent.add_child(card)
	return game._column(card,9)
func _text(parent: Node, text: String, color: Color=MUTED, width: float=540, font_size: int=12) -> Label:
	var label: Label = game._label(parent,text,font_size,color)
	label.custom_minimum_size.x = width
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
func _select(parent: Node, label: String, width: float=250) -> OptionButton:
	var row: HBoxContainer = game._row(parent,10)
	var title: Label = game._label(row,label,13,MUTED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(width,36)
	picker.add_theme_stylebox_override("normal",game._style(Color("102c38"),7))
	picker.add_theme_color_override("font_color",CREAM)
	picker.add_theme_font_size_override("font_size",12)
	row.add_child(picker)
	return picker
func _build_network() -> void:
	var tab := _tab("通信拓扑")
	var row: HBoxContainer = game._row(tab,14)
	var graph_box := _box(row,750)
	game._label(graph_box,"两张网络，同一座城市",18,CREAM)
	network_map = NetworkMap.new()
	network_map.custom_minimum_size = Vector2(710,318)
	network_map.node_selected.connect(_select_device)
	network_map.link_selected.connect(func(id: int): selected_link=id; _select_id(link_picker,id); tabs.current_tab=1; refresh())
	graph_box.add_child(network_map)
	_text(graph_box,"光纤稳定但造价较高；无线便于扩展，却有范围、时延和风暴风险。端点断电依靠 UPS 临时维持，研究不能替代可用链路。",MUTED,710)
	var details := _box(row,440)
	game._label(details,"设备路径与可信状态",18,BLUE)
	device_picker = _select(details,"选择设备",276)
	device_picker.item_selected.connect(func(_i: int): _select_device(_picked(device_picker)))
	device_info = _text(details,"",CREAM,400,13)
	game._button(details,"隔离所选设备",func(): _commit(game.sim.isolate_device(selected_device,true)),Vector2(0,34))
	game._button(details,"解除设备隔离",func(): _commit(game.sim.isolate_device(selected_device,false)),Vector2(0,34))
	game._button(details,"恢复 / 修补设备 · ¥900",func(): _commit(game.sim.recover_device(selected_device)),Vector2(0,34))
	var connect_row: HBoxContainer = game._row(tab,10)
	link_from = _select(connect_row,"起点",250)
	link_to = _select(connect_row,"终点",250)
	link_kind = _select(connect_row,"介质",160)
	link_kind.add_item("光纤")
	link_kind.add_item("无线")
	for picker in [link_from,link_to,link_kind]:
		picker.item_selected.connect(func(_i: int): _update_quote())
	var actions: HBoxContainer = game._row(tab,10)
	game._button(actions,"新建通信链路",_connect,Vector2(205,36))
	game._button(actions,"在地图布设通信线  4",_map_link,Vector2(250,36))
	game._button(actions,"查看通信地图图层",func(): close(); game.overlay="comm"; game._sync_world(true),Vector2(250,36))
	link_quote=_text(tab,"",ORANGE,1200,11)
func _build_operations() -> void:
	var tab := _tab("链路与故障处置")
	var row: HBoxContainer = game._row(tab,14)
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
	game._label(circuit_box,"选择正确的故障处置方式",18,CREAM)
	circuit_picker = _select(circuit_box,"电力线路",380)
	circuit_picker.item_selected.connect(func(_i: int): selected_circuit=_picked(circuit_picker); refresh())
	circuit_info = _text(circuit_box,"",CREAM)
	remote_button = game._button(circuit_box,"发送远程开关指令",_remote,Vector2(0,36))
	game._button(circuit_box,"派现场开关队 · ¥350",func(): _commit(game.sim.field_switch(selected_circuit)),Vector2(0,36))
	game._button(circuit_box,"巡检定位 · ¥500",func(): _commit(game.sim.patrol_line(selected_circuit)),Vector2(0,36))
	_text(circuit_box,"远程命令有回执延迟，到达时会重新检查路径和权限。未知故障先巡检；可信遥测定位能省下现场查线时间。",ORANGE)
func _build_security() -> void:
	var tab := _tab("安全策略与演练")
	var row: HBoxContainer = game._row(tab,14)
	var policy := _box(row,585)
	game._label(policy,"用可用性换取多少信任？",18,CREAM)
	policy_picker = _select(policy,"访问策略",310)
	for text in ["开放互联","网络分区","零信任校验"]:
		policy_picker.add_item(text)
	policy_button = game._button(policy,"应用安全策略",func(): _commit(game.sim.set_security_policy(["open","segmented","zero_trust"][policy_picker.selected])),Vector2(0,36))
	security_info = _text(policy,"",BLUE)
	upgrade_button = game._button(policy,"升级安全防护",func(): _commit(game.sim.upgrade_security()),Vector2(0,36))
	cost_info = _text(policy,"",ORANGE)
	_text(policy,"分区限制事件扩散；零信任拒绝不可信控制，但会增加校验时延和运维成本。在线安全中心可以改善检测与响应。")
	var drills := _box(row,585)
	game._label(drills,"检验城市的数字韧性",18,BLUE)
	attack_kind = _select(drills,"演练类型",310)
	for text in ["DoS · 通信服务中断","遥测欺骗 · 信息不可置信","非法控制 · 恶意断路"]:
		attack_kind.add_item(text)
	_text(drills,"目标使用「通信拓扑」页的所选设备。演练是游戏事件，会真实影响城内通信与供电。")
	game._button(drills,"启动网络安全演练",_drill,Vector2(0,40))
	var builds: HBoxContainer = game._row(drills,8)
	for pair in [["control","调度中心"],["relay","通信中继"],["soc","安全中心"]]:
		var kind: String = pair[0]
		game._button(builds,pair[1],func(): _build_kind(kind),Vector2(0,36))
	_text(drills,"建设设施后同时规划供电和通信。隔离可以遏制事件，也会切断设备遥测；修补恢复需要时间。",ORANGE)
func _build_incidents() -> void:
	var tab := _tab("告警与指令回执")
	var row: HBoxContainer = game._row(tab,14)
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
	refresh()
func _connect() -> void:
	_commit(game.sim.connect_communication(_picked(link_from),_picked(link_to),"fiber" if link_kind.selected==0 else "wireless"))
func _map_link() -> void:
	close()
	game.communication_kind = "fiber" if link_kind.selected==0 else "wireless"
	game.overlay = "comm"
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
	if game == null or game.sim.get("digital") == null:
		return
	var sim: RefCounted=game.sim
	var state: Dictionary=sim.digital.state
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
	device_info.text="设备 %02d\n%s\n可信：%s  ·  时延 %s\nUPS 剩余 %.1f 小时\n%s" % [selected_device,"调度路径可达" if status.get("reachable",false) else "与调度失联","已校验" if status.get("trusted",false) else "未校验","%.0f ms" % latency if latency>=0 else "不可达",status.get("ups_remaining",0),status.get("reason","")]
	if status.get("compromised",false):
		device_info.text+="\n已确认安全异常：隔离并修补此设备。"
	_refresh_link()
	_refresh_circuit()
	if sync_inputs:
		policy_picker.select(maxi(0,["open","segmented","zero_trust"].find(state.get("policy","open"))))
	security_info.text="安全防护 L%d  ·  已阻挡 %d 次事件\n远程成功 %d 次 / 拒绝 %d 次" % [state.get("security_level",0),state.get("blocked_attacks",0),state.get("remote_success",0),state.get("remote_rejected",0)]
	var level:=int(state.get("security_level",0))
	upgrade_button.text="安全研究完成" if level>=2 else "↑ 升级安全防护 · ¥%s" % ("10k" if level==0 else "22k")
	upgrade_button.disabled=level>=2
	cost_info.text="通信 ¥%.0f/h · 安全 ¥%.0f/h\n成本已计入经营账本的运维项。" % [sim.totals.get("communication_cost",0),sim.totals.get("security_cost",0)]
	_refresh_incidents()
func _refresh_pickers(force: bool) -> void:
	var signature:=str(game.sim.buildings.map(func(b: Dictionary): return b.id))
	if force or signature!=_asset_signature:
		var old_from:=_picked(link_from)
		var old_to:=_picked(link_to)
		for picker in [device_picker,link_from,link_to]:
			picker.clear()
			for b in game.sim.buildings:
				picker.add_item("%02d · %s" % [b.id,b.name],int(b.id))
		_select_id(device_picker,selected_device)
		if device_picker.selected>=0:
			selected_device=_picked(device_picker)
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
	game._clear_children(incidents_box)
	var found:=false
	for incident in game.sim.digital.incidents:
		if not incident.get("detected",false):
			continue
		found=true
		var kinds: Dictionary={"dos":"拒绝服务","spoof":"遥测欺骗","intrusion":"非法控制"}
		var states: Dictionary={"active":"待处置","blocked":"已阻挡","resolved":"已恢复"}
		var affected:=PackedStringArray()
		for id in incident.get("affected_ids",[]):
			affected.append("%02d" % int(id))
		_text(incidents_box,"%s · 设备 %02d · %s\n%s\n检测影响设备：%s" % [kinds.get(incident.get("kind",""),"异常"),incident.get("target_id",0),states.get(incident.get("status",""),"待处理"),incident.get("description",""),"、".join(affected)],ORANGE)
		var target_id: int=incident.get("target_id",-1)
		game._button(incidents_box,"查看目标与恢复",func(): _select_device(target_id); tabs.current_tab=0,Vector2(0,30))
	if not found:
		_text(incidents_box,"当前没有已确认的网络安全事件。",TEAL)
	game._clear_children(jobs_box)
	var jobs: Array=[]
	jobs.append_array(game.sim.digital.pending_commands)
	jobs.append_array(game.sim.digital.field_jobs)
	for job in jobs:
		var kinds: Dictionary={"switch":"现场开关","patrol":"巡检定位"}
		_text(jobs_box,"%s · E%02d · 剩余 %.2f 小时" % [kinds.get(job.get("kind",""),"远程指令"),job.get("line_id",0),job.get("remaining",0)],BLUE)
	if jobs.is_empty():
		_text(jobs_box,"没有等待中的指令或现场作业。",TEAL)
