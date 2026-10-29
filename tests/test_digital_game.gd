extends SceneTree
## Real scene integration: communications, observed information and delayed control.
var game: Node
var desk: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool,message: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)

func button_in(parent: Node,caption: String) -> Button:
	if parent is Button and caption in parent.text:
		return parent
	for child in parent.get_children():
		var found := button_in(child,caption)
		if found != null:
			return found
	return null

func press(parent: Node,caption: String) -> void:
	var button := button_in(parent,caption)
	check(button != null,"action exists: " + caption)
	if button != null:
		button.pressed.emit()

func labels(parent: Node) -> String:
	var result := str(parent.text) + "\n" if parent is Label or parent is RichTextLabel else ""
	for child in parent.get_children():
		result += labels(child)
	return result

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_input(event)

func choose(picker: OptionButton,id: int) -> void:
	for i in picker.item_count:
		if picker.get_item_id(i) == id:
			picker.select(i)
			picker.item_selected.emit(i)
			return
	check(false,"picker contains id %d" % id)

func advance(steps: int=1) -> void:
	for i in steps:
		desk._advance()

func research_path() -> void:
	game._research()
	game.sim.step(0.05)
	game._sync_world(true)
	desk.refresh(true)

func same_values(a: Variant,b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for field in a:
			if not b.has(field) or not same_values(a[field],b[field]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not same_values(a[i],b[i]):
				return false
		return true
	return a == b

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game._activate_session()
	desk = game.digital_panel
	check(desk != null and not desk.visible,"digital operations desk is created and initially hidden")
	key(KEY_N)
	check(desk.visible and game._modal_open(),"N opens digital operations modal")
	var before: float = game.sim.elapsed_hours
	game._process(1.0)
	check(is_equal_approx(float(game.sim.elapsed_hours),before),"digital planning pauses automatic simulation")
	press(desk,"推进 15 分钟")
	check(is_equal_approx(float(game.sim.elapsed_hours),before+0.25),"explicit advance executes fifteen game minutes inside modal")
	key(KEY_ESCAPE)
	check(not desk.visible and not game._modal_open(),"Escape closes digital operations modal")
	game.hud.center_buttons.network.pressed.emit()
	check(desk.visible and desk.tabs.get_tab_count() == 4 and desk.cards.has("observed") and desk.cards.has("trusted"),"navigation opens four digital tabs with distinct path and observation indicators")
	var pure_snapshot: Dictionary = game.sim.snapshot().duplicate(true)
	for i in 4:
		desk.tabs.current_tab = i
		desk.refresh(i%2 == 0)
	check(same_values(game.sim.snapshot(),pure_snapshot),"digital queries and tab refresh do not advance observations queues or costs")
	choose(desk.drill_target,2)
	check(desk.selected_device==2 and desk.device_picker.get_selected_id()==2,"security target directly selects the shared device without visiting topology")
	choose(desk.device_picker,10)
	check(desk.drill_target.get_selected_id()==10,"topology selection keeps the explicit security target synchronized")
	desk.policy_picker.select(1)
	desk.refresh()
	check(desk.policy_picker.selected==1 and game.sim.digital.state.policy=="open","routine refresh preserves an unapplied security policy draft")
	desk.refresh(true)
	desk.tabs.current_tab=0
	var construction_toggle := button_in(desk,"＋ 新建通信连接")
	construction_toggle.button_pressed=true
	check(desk.link_quote.is_visible_in_tree(),"link construction details open on demand")
	construction_toggle.button_pressed=false
	check(not desk.link_quote.is_visible_in_tree(),"link construction details collapse without changing the simulation")

	# Build a real relay, then prove communication does not supply electrical power.
	press(desk,"通信中继")
	check(not desk.visible and game.tool == "build" and game.build_kind == "relay","digital build action returns to relay placement")
	var relay_cell := Vector2i(4,6)
	game._handle_map_click(relay_cell)
	var relay_id: int = game._building_at(relay_cell)
	check(relay_id > 0 and game.sim.get_building(relay_id).kind == "relay","relay placement creates a digital facility")
	var electrical_count: int = game.sim.lines.size()
	var comm_count: int = game.sim.digital.links.size()
	desk.open()
	choose(desk.link_from,10)
	choose(desk.link_to,relay_id)
	desk.link_kind.select(1)
	press(desk,"新建通信链路")
	check(game.sim.digital.links.size() == comm_count+1 and game.sim.digital.links.back().kind == "wireless","network form creates an independent wireless link")
	check(game.sim.lines.size() == electrical_count and not game.sim.get_building(relay_id).powered,"communications construction does not energise an unconnected facility")
	check(game.sim.communication_status(relay_id).reachable,"unpowered relay can communicate temporarily on UPS")
	desk.link_kind.select(0)
	press(desk,"在地图布设通信线")
	check(not desk.visible and game.tool == "datalink" and game.communication_kind == "fiber","map action chooses fibre data-link tool")
	game._handle_map_click(relay_cell)
	game._handle_map_click(game.sim.get_building(2).cell)
	check(game.sim.digital.links.size() == comm_count+2 and game.sim.lines.size() == electrical_count,"two map endpoints add communication without a power branch")
	check(game.communication_root.visible and not game.cable_root.visible,"communication overlay distinguishes the two networks")
	game._set_tool("line")
	game._handle_map_click(relay_cell)
	game._handle_map_click(game.sim.get_building(2).cell)
	check(game.sim.get_building(relay_id).powered,"separate electrical connection supplies relay power")
	key(KEY_4)
	check(game.tool == "datalink","4 selects communication construction tool")
	game.overlay = "normal"
	game._set_tool("select")

	# Remote switching requires real trusted endpoints and a timed fresh sample.
	research_path()
	desk.open()
	choose(desk.circuit_picker,1)
	check(game.sim.line_observation(1).visibility == "verified","research and available communication produce verified telemetry after a sample")
	var was_closed: bool = game.sim.get_line(1).closed
	press(desk,"发送远程开关指令")
	check(game.sim.digital.pending_commands.size() == 1 and game.sim.get_line(1).closed == was_closed,"remote button queues a command without an instant physical switch")
	desk._remote()
	check(game.sim.digital.pending_commands.size() == 1,"duplicate remote action cannot create a second in-flight command")
	advance()
	check(game.sim.digital.pending_commands.is_empty() and game.sim.get_line(1).closed != was_closed,"trusted command arrives and changes electrical topology after delay")
	press(desk,"发送远程开关指令")
	advance()
	check(game.sim.get_line(1).closed == was_closed,"a subsequent remote command can restore the branch")
	press(desk,"发送远程开关指令")
	choose(desk.device_picker,1)
	press(desk,"隔离所选设备")
	var rejected_before: int = game.sim.digital.state.remote_rejected
	advance()
	check(game.sim.get_line(1).closed == was_closed and game.sim.digital.pending_commands.is_empty(),"loss of trusted endpoint cancels a command before execution")
	check(int(game.sim.digital.state.remote_rejected) > rejected_before,"cancelled command produces a rejection receipt")
	press(desk,"派现场开关队")
	check(not game.sim.digital.field_jobs.is_empty() and game.sim.get_line(1).closed == was_closed,"field fallback queues an offline job rather than bypassing time")
	advance(2)
	check(game.sim.get_line(1).closed != was_closed,"field crew can switch while communication endpoint remains isolated")
	press(desk,"派现场开关队")
	advance(2)
	check(game.sim.get_line(1).closed == was_closed,"field crew can restore power without remote trust")

	# Hidden fault fixture: all public UI must use observations instead of truth.
	desk.close()
	game.sim.isolate_device(2,true)
	game.sim.isolate_device(5,true)
	game.sim.digital.observations.erase(4)
	var hidden_line: Dictionary = game.sim.get_line(4)
	hidden_line.fault = true
	hidden_line.closed = false
	hidden_line.health = 37.0
	game.sim._refresh()
	game.sim.step(1.05)
	check(game.sim.line_observation(1).visibility == "stale","disconnected previous field records become explicitly stale after their freshness window")
	game.selected_id = -1
	game.selected_line = 4
	game._update_inspector()
	game._sync_world(true)
	var observation: Dictionary = game.sim.line_observation(4)
	check(observation.visibility == "unknown" and observation.flow == null,"disconnected unobserved fault has no public flow or exact fault sample")
	var cable: Node3D = game.cable_visuals[4]
	check(cable.get_meta("observation_visibility","") == "unknown" and not cable.get_meta("fault_marker",true),"map does not mark unknown physical fault as a located red fault")
	check(cable.get_node_or_null("EnergyDot") == null,"unknown line does not animate true hidden power flow")
	var inspector_text := labels(game.inspector_box)
	check("未观测" in inspector_text and not "故障已定位" in inspector_text and not "37%" in inspector_text,"line inspector hides unknown fault and sentinel health")
	var storm_messages: Array[String] = []
	var capture_log := func(entry: Dictionary): storm_messages.append(str(entry.get("text","")))
	game.sim.event_logged.connect(capture_log)
	game.sim.trigger_storm()
	game.sim.event_logged.disconnect(capture_log)
	var concealed := true
	for line in game.sim.lines:
		if game.sim.line_observation(int(line.id)).visibility != "unknown":
			continue
		for message in storm_messages:
			if "线路 #%d" % int(line.id) in message:
				concealed = false
	check(concealed,"storm log cannot disclose exact identifiers for unobserved faulted lines")
	desk.open()
	choose(desk.circuit_picker,4)
	check("未观测" in desk.circuit_info.text and "不可用" in desk.circuit_info.text and desk.remote_button.disabled,"digital circuit inspector also hides unknown measurements and disables remote action")
	press(desk,"巡检定位")
	check(game.sim.line_observation(4).visibility == "unknown","patrol dispatch does not instantly reveal the fault")
	advance(2)
	check(game.sim.line_observation(4).visibility == "patrol" and game.sim.line_observation(4).fault,"completed patrol supplies a dated confirmed fault record")
	check(game.cable_visuals[4].get_meta("fault_marker",false),"map fault marker appears only after actual observation")

	# Drills affect availability or trust, and undiscovered incidents remain hidden.
	game._new_game(false,true)
	research_path()
	desk.open()
	choose(desk.device_picker,2)
	desk.attack_kind.select(0)
	var physical_before: bool = game.sim.get_line(1).closed
	press(desk,"启动网络安全演练")
	check(not game.sim.communication_status(2).reachable and game.sim.get_line(1).closed == physical_before,"DoS drill interrupts communication without directly opening a power breaker")
	check(not game.sim.digital.incidents.back().detected and "当前没有已确认" in labels(desk.incidents_box),"unconfirmed incident details are absent from public alert UI")
	advance(3)
	check(game.sim.digital.incidents.back().detected and "设备 02" in labels(desk.incidents_box),"time and detection make the incident target available to the player")
	var detected_id: int=game.sim.digital.incidents.back().id
	var incident_label: Label=desk.incident_labels[detected_id]
	desk.refresh()
	check(desk.incident_labels[detected_id]==incident_label and is_instance_valid(incident_label),"routine event refresh retains the existing detail control and its reading position")
	press(desk,"恢复 / 修补设备")
	check(float(game.sim.digital.devices[2].recover_remaining) > 0.0,"recovery button starts a timed patch job")
	advance(3)
	check(game.sim.communication_status(2).trusted,"patch completion restores verified communication")
	desk.attack_kind.select(1)
	var true_flow: float = game.sim.get_line(1).flow
	press(desk,"启动网络安全演练")
	check(game.sim.communication_status(2).reachable and not game.sim.communication_status(2).compromised,"spoof remains reachable without prematurely revealing its unconfirmed compromised target")
	check(game.sim.line_observation(1).visibility == "suspect" and is_equal_approx(float(game.sim.get_line(1).flow),true_flow),"spoof changes observation quality without modifying physical flow")
	choose(desk.circuit_picker,1)
	check(desk.remote_button.disabled and "可疑" in desk.circuit_info.text,"suspect telemetry blocks remote-control UI")
	press(desk,"恢复 / 修补设备")
	advance(3)
	check(not game.sim.digital.devices[2].compromised,"target patch clears the compromised endpoint")
	# Open interconnection propagated the drill to the neighboring dispatch root.
	choose(desk.device_picker,10)
	press(desk,"恢复 / 修补设备")
	advance(3)
	check(game.sim.communication_status(2).trusted,"patching the affected root restores the complete trusted path")
	choose(desk.device_picker,2)
	var cost_before: float = game.sim.cash
	press(desk,"升级安全防护")
	check(game.sim.digital.state.security_level == 1 and is_equal_approx(float(game.sim.cash),cost_before-10000.0),"security upgrade consumes its published capital cost")
	desk.policy_picker.select(2)
	press(desk,"应用安全策略")
	check(game.sim.digital.state.policy == "zero_trust" and float(game.sim.totals.security_cost) > 0.0,"zero-trust policy applies with an operating cost")
	desk.attack_kind.select(2)
	physical_before = game.sim.get_line(1).closed
	press(desk,"启动网络安全演练")
	check(game.sim.digital.incidents.back().status == "blocked" and game.sim.get_line(1).closed == physical_before,"hardened policy blocks an intrusion without changing physical topology")
	press(desk,"隔离所选设备")
	check(game.sim.communication_status(2).isolated and not game.sim.communication_status(2).reachable,"device isolation removes its communication path")
	press(desk,"解除设备隔离")
	check(not game.sim.communication_status(2).isolated,"device can be reintroduced for trust validation")

	# Gateway availability is a power dependency with finite UPS, not free coverage.
	game._new_game(false,true)
	game.sim.field_switch(8)
	game.sim.step(0.4)
	check(not game.sim.get_building(10).powered and game.sim.communication_status(10).reachable,"initial gateway survives an electrical disconnect on UPS")
	game.sim.step(2.1)
	check(not game.sim.communication_status(10).reachable and float(game.sim.communication_status(10).ups_remaining) <= 0.000001,"UPS exhaustion removes the dispatch root and its coverage")

	# Save queued work before its completion, then continue from the restored model.
	game._new_game(false,true)
	research_path()
	desk.open()
	choose(desk.circuit_picker,1)
	press(desk,"发送远程开关指令")
	choose(desk.circuit_picker,4)
	press(desk,"巡检定位")
	var path := "user://test_tidal_digital_ui_save.json"
	var saved_digital: Dictionary = game.sim.digital.snapshot().duplicate(true)
	check(game.sim.save_game(path).ok,"digital graph observations and pending work save successfully")
	game.sim.step(0.25)
	check(game.sim.load_game(path).ok,"digital pending-work snapshot reloads")
	desk.refresh(true)
	check(same_values(game.sim.digital.snapshot(),saved_digital),"loaded communications and observation timestamps retain in-flight work")
	check(game.sim.digital.pending_commands.size() == 1 and game.sim.digital.field_jobs.size() == 1,"reload restores both remote and field queues")
	advance()
	check(game.sim.digital.pending_commands.is_empty() and not game.sim.get_line(1).closed,"restored command executes exactly once after its remaining delay")
	# Schema 2 has no digital state; migration should supply a safe separate network.
	var legacy: Dictionary = game.sim.snapshot()
	legacy.schema_version = 2
	legacy.erase("digital")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy,"",true,true))
	file.close()
	check(game.sim.load_game(path).ok,"pre-digital schema two snapshot migrates")
	desk.refresh(true)
	check(game.sim.digital.pending_commands.is_empty() and game.sim.digital.field_jobs.is_empty() and not game.sim.digital.links.is_empty(),"legacy migration supplies communication graph without invented queued commands")
	DirAccess.remove_absolute(path)
	game._new_game(false,true)
	check(not desk.visible and game.sim.digital.state.security_level == 0 and game.sim.digital.incidents.is_empty(),"new game resets digital UI security and incidents")
	key(KEY_N)
	key(KEY_N)
	check(not desk.visible,"N toggles the digital desk closed")
	print("DIGITAL GAME TESTS: %d checks; %d failures" % [checks,failures])
	game.queue_free()
	await process_frame
	quit(1 if failures > 0 else 0)
