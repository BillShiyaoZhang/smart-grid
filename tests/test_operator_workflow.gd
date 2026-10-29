extends SceneTree
## Real map workspace integration, including safeguards and responsive presentation.
var checks:=0
var failures:=0
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks+=1
	if not condition: failures+=1; push_error("FAIL: "+message)

func settle() -> void:
	for index in range(4): await process_frame

func find_button(node: Node, caption: String) -> Button:
	if node is Button and caption in node.text: return node
	for child in node.get_children():
		var found:=find_button(child,caption)
		if found: return found
	return null

func _run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game._activate_session()
	game.speed=0
	game.preferences.storage_path="user://test_operator_workflow.cfg"
	var before: Dictionary=game.sim.snapshot().duplicate(true)
	game.hud.values.supply.pressed.emit()
	check(game.hud.operator_dock.page=="diagnosis" and game.hud.inspector.visible,"supply reading opens the one diagnostic workspace")
	check(game.sim.snapshot()==before,"opening diagnosis has no simulation side effects")
	check(game.hud.close_top() and not game.hud.inspector.visible,"Escape closes an unpinned workspace before map tools")
	game.hud.operator_dock.open_search()
	game.hud.operator_dock.search.text="燃气"
	game.hud.operator_dock.refresh()
	await settle()
	var result: Button=find_button(game.hud.operator_dock.body,"燃气")
	check(result!=null,"facility search finds name and identity")
	if result:
		result.grab_focus()
		game.sim.step(.1)
		game.hud.operator_dock.refresh()
		await settle()
		check(is_instance_valid(result) and root.gui_get_focus_owner()==result,"changing live observations preserves search controls and focus")
	game.hud.operator_dock.watch(1)
	check(1 in game.hud.operator_dock.watched,"watch list tracks chosen object")
	game.hud.operator_dock.pinned=true
	game.focus_target("building",2)
	check(game.selected_id==2 and game.hud.operator_dock.page=="watch","pinned workspace survives map navigation")
	game.hud.operator_dock.pinned=false
	game.focus_target("building",1)
	check(game.hud.operator_dock.page=="object" and game.selected_id==1,"object navigation inherits the target in the inspector")
	game.overlay="health"
	game._set_tool("line")
	check(game.overlay=="power","electrical tool activates relevant overlay")
	game._set_tool("select")
	check(game.overlay=="health","cancel restores previous overlay")
	game.focus_target("building",1)
	check(game.overlay=="health","navigation in selection mode preserves an explicitly chosen layer")
	game.overlay="normal"
	game.focus_target("building",1)
	var building_count: int=game.sim.buildings.size()
	var cash: float=game.sim.cash
	find_button(game.inspector_box,"拆除").pressed.emit()
	check(game.confirmation.visible and game.sim.buildings.size()==building_count and game.sim.cash==cash,"demolition opens review without changing the network")
	find_button(game.confirmation,"取消").pressed.emit()
	check(not game.confirmation.visible and not game.sim.get_building(1).is_empty(),"cancel leaves the asset in service")
	game._request_demolition(1)
	find_button(game.confirmation,"确认拆除并").pressed.emit()
	check(game.sim.get_building(1).is_empty() and game.selected_id==-1,"confirmation removes the asset and clears stale selection")
	game.focus_target("building",1)
	check(game.selected_id==-1 and "目标已移除" in game.inspector_box.get_child(0).text,"historical targets that were demolished cannot leave a stale inspector")
	game._new_game(false,true)
	game.onboarding=true
	game.onboarding_skipped=false
	game._update_onboarding()
	check(game.hud.onboarding_panel.visible,"sandbox offers persistent skippable first connection guidance")
	game.sim.connect_buildings(2,6)
	game._set_tool("line")
	game._handle_map_click(game.sim.get_building(2).cell)
	game._handle_map_click(game.sim.get_building(6).cell)
	check(game.connection_start==2,"rejected duplicate connection preserves the chosen start for retry")
	game._set_tool("select")
	game._update_onboarding()
	check("已连接" in game.hud.onboarding_label.text,"guidance acknowledges actual connected topology")
	game.onboarding_skipped=true
	game._update_onboarding()
	check(not game.hud.onboarding_panel.visible,"skip hides sandbox guidance")
	game.speed=8
	game.market_panel.open()
	game._update_hud()
	check("规划暂停" in game.hud.time_status.text and "8" in game.hud.time_status.text,"center explains effective pause and return speed")
	game.market_panel._advance()
	check(not game.chart.sample_hours.is_empty() and is_equal_approx(float(game.chart.sample_hours[-1]),float(game.sim.elapsed_hours)),"manual advancement records real game-time history")
	game.market_panel.close()
	check("运行 8" in game.hud.time_status.text,"return resumes explicit chosen speed")
	game.preferences.bind_action("market",KEY_B)
	game._apply_preferences()
	check("B" in game.hud.center_buttons.market.text,"center label reflects rebound key")
	check("B" in game._keyboard_guide(),"manual uses current bindings")
	game.preferences.bind_action("line",KEY_L)
	game._apply_preferences()
	check("L" in game.hud.tool_buttons.line.tooltip_text,"tool tooltip reflects rebound key")
	var event:=InputEventKey.new()
	event.keycode=KEY_B
	event.physical_keycode=KEY_B
	event.pressed=true
	game._unhandled_input(event)
	check(game.market_panel.visible,"rebound shortcut opens actual market center")
	game.market_panel.close()
	game.hud.operator_dock.close()
	game._hud_action("clear_selection")
	game.speed=0
	for resolution in [Vector2i(1280,720),Vector2i(1440,900)]:
		root.size=resolution
		for ratio in [1.0,1.25,1.5]:
			game.preferences.ui_scale=ratio
			game._apply_preferences()
			await settle()
			var bounds:=Rect2(Vector2.ZERO,game.root_ui.size)
			check(bounds.encloses(game.hud.dock_panel.get_rect()),"tool rail fits "+str(resolution)+" @"+str(ratio))
			check(bounds.encloses(game.hud.status_panel.get_rect()),"status fits "+str(resolution)+" @"+str(ratio))
			game.hud.toggle_popup("stats")
			await settle()
			check(bounds.encloses(game.hud.popups.stats.get_rect()),"statistics remains bounded and scrollable @"+str(ratio))
			game.hud.close_popups()
			game.hud.operator_dock.show_page("diagnosis")
			await settle()
			check(bounds.encloses(game.hud.inspector.get_rect()),"workspace fits @"+str(ratio))
			game.hud.operator_dock.close()
	game.preferences.reset_bindings()
	game.preferences.ui_scale=1
	game.preferences.high_contrast=false
	game.preferences.reduced_motion=false
	game._apply_preferences()
	if FileAccess.file_exists("user://test_operator_workflow.cfg"): DirAccess.remove_absolute("user://test_operator_workflow.cfg")
	game.queue_free()
	await process_frame
	print("OPERATOR WORKFLOW: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
