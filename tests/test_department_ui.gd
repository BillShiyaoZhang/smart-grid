extends SceneTree
## Real scene controls verify shared-map roles, evidence drilldown and accessibility.
const Preferences = preload("res://scripts/ui/operator_preferences.gd")
const Matrix = preload("res://scripts/ui/department_chart.gd")
const ReliabilityChart = preload("res://scripts/ui/reliability_chart.gd")
var game: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, caption: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + caption)

func settle(frames: int = 5) -> void:
	for _i in frames: await process_frame

func keyed(parent: Node, key: String) -> Button:
	if parent is Button and str(parent.get_meta("action_key","")) == key: return parent
	for child in parent.get_children():
		var found := keyed(child,key)
		if found != null: return found
	return null

func chart_in(parent: Node) -> Control:
	if parent.get_script() == Matrix: return parent
	for child in parent.get_children():
		var found := chart_in(child)
		if found != null: return found
	return null

func metric_picker(parent: Node) -> OptionButton:
	if parent is OptionButton and str(parent.get_meta("action_key",""))=="reliability_metric": return parent
	for child in parent.get_children():
		var found := metric_picker(child)
		if found != null: return found
	return null

func reliability_chart(parent: Node) -> Control:
	if parent.get_script() == ReliabilityChart: return parent
	for child in parent.get_children():
		var found := reliability_chart(child)
		if found != null: return found
	return null

func press_key(parent: Node, key: String) -> void:
	var control := keyed(parent,key)
	check(control != null,"actual control exists: " + key)
	if control != null: control.pressed.emit()

func click(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)

func state() -> String:
	return JSON.stringify(game.sim.snapshot(),"",true,true)

func desk() -> Control:
	return game.hud.operator_dock.department_desk

func clear_modals() -> void:
	for modal in [game.welcome,game.pause_menu,game.help_modal,game.end_modal,game.confirmation,game.settings_panel,game.market_panel,game.digital_panel,game.planning_panel,game.campaign_panel]: modal.hide()
	game.hud.close_popups()
	game.hud.close_tray()

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game._activate_session()
	game.speed = 0
	game.onboarding = false
	game.preferences.storage_path = "res://.godot/test_department_preferences.cfg"
	clear_modals()
	root.size = Vector2i(1440,900)
	game.preferences.ui_scale = 1.0
	game._apply_preferences()
	await settle()
	await _lenses()
	await _department_centers()
	await _depth_and_kpis()
	await _incidents_and_risk_focus()
	await _asset_matrix()
	await _connect_priority()
	await _responsive()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.preferences.storage_path))
	game.queue_free()
	await settle(2)
	print("DEPARTMENT UI: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _lenses() -> void:
	var before := state()
	var world: Node = game.world
	var sim: RefCounted = game.sim
	game.selected_id = 1
	game._update_inspector()
	var layers := {"operations":"power","planning":"power","maintenance":"health","market":"power","assets":"health","customers":"normal","digital":"comm"}
	for lens in game.hud.LENSES:
		var control: Button = game.hud.lens_buttons[lens]
		control.pressed.emit()
		await settle()
		check(game.hud.lens == lens and game.overlay == layers[lens],"real role control selects its map layer: " + lens)
		check(game.sim == sim and game.world == world and game.selected_id == 1,"role retains shared world, model and selected object: " + lens)
		check(game.hud.operator_dock.page == "department" and desk().is_visible_in_tree(),"role opens the shared department workspace: " + lens)
		check(state() == before,"role switch preserves simulation, money, clock and observations: " + lens)
	check(game.hud.operator_dock.tabs.tab_count == 5,"shared drawer has its fifth department tab")
	game.hud.operator_dock.tabs.current_tab = 1
	await settle()
	check(game.hud.operator_dock.page == "diagnosis" and not desk().visible,"same drawer can switch from department to diagnosis")
	game.hud.operator_dock.tabs.current_tab = 4
	await settle()
	check(game.hud.operator_dock.page == "department" and desk().visible,"fifth tab returns to retained department")

func _depth_and_kpis() -> void:
	game.hud.lens_buttons.operations.pressed.emit()
	var before := state()
	for index in 3:
		game.hud.depth_picker.select(index)
		game.hud.depth_picker.item_selected.emit(index)
		await settle()
		var expected: String = ["beginner","operator","engineer"][index]
		var reloaded: RefCounted = Preferences.new()
		reloaded.load_preferences(game.preferences.storage_path)
		check(game.preferences.information_depth == expected and reloaded.information_depth == expected,"depth selector persists personal preference: " + expected)
		check(state() == before,"display depth changes neither world rules nor difficulty: " + expected)
	press_key(desk(),"kpi:supply")
	await settle()
	check(desk().expanded.get("kpi:supply",false),"global KPI drills into its explanation without changing worlds")
	keyed(desk(),"kpi:supply").grab_focus()
	desk()._signature = ""
	desk().refresh()
	await settle()
	var focused: Control = root.gui_get_focus_owner()
	check(focused!=null and str(focused.get_meta("action_key",""))=="kpi:supply","department refresh restores keyboard focus to the same action")
	# The same renderer also supports an object-specific KPI payload.
	desk()._kpi(desk().body,{"id":"fixture_target","label":"核实机组","value":1,"unit":"台","detail":"已知目标","source":"测试对象身份","target_type":"facility","target_id":1})
	press_key(desk(),"kpi:fixture_target")
	await settle()
	check(game.selected_id == 1 and game.hud.operator_dock.page == "object","object KPI follows the common target inspection path")
	check(state() == before,"KPI expansion and object focus are read-only")

func _department_centers() -> void:
	var baseline: Dictionary = game.sim.snapshot().duplicate(true)
	for technology in ["ac_systems","protection","regional_planning","scada"]:
		if technology not in game.sim.evolution.unlocked: game.sim.evolution.unlocked.append(technology)
	game.sim._refresh()
	game.focus_target("facility",5)
	game.hud.lens_buttons.customers.pressed.emit()
	await settle()
	press_key(desk(),"center:customers")
	await settle()
	var network: Node = game.digital_panel
	var operations: Node = network.grid_operations
	check(network.visible and operations!=null and operations.section.selected==2,"customer department opens the real street-energy management section")
	check(not network.tabs.is_tab_hidden(network.tabs.current_tab),"customer department never selects a hidden advanced tab")
	if operations!=null:
		check(operations.customer_picker.get_selected_id()==5,"customer coordination keeps the selected hospital target")
		operations.fields.pv_mw.value=3.5
		operations.capture_drafts()
	clear_modals()
	game.hud.lens_buttons.digital.pressed.emit()
	await settle()
	press_key(desk(),"center:digital")
	await settle()
	check(network.visible and network.tabs.current_tab==0,"digital department resets a previously-used asset tab to actual communications/telemetry")
	clear_modals()
	game.focus_target("line",2)
	game.hud.lens_buttons.assets.pressed.emit()
	await settle()
	press_key(desk(),"center:assets")
	await settle()
	check(network.visible and operations.section.selected==0,"asset department opens maintenance rather than a stale customer section")
	check(operations.target_type.selected==1 and operations.asset_picker.get_selected_id()==2,"asset workbench retains the selected line identity")
	operations.delay.value=1.35
	operations.capture_drafts()
	clear_modals()
	game.focus_target("facility",2)
	game.hud.lens_buttons.assets.pressed.emit()
	await settle()
	press_key(desk(),"center:assets")
	await settle()
	check(operations.asset_picker.get_selected_id()==2 and operations.station_picker.get_selected_id()==2,"selected substation is inherited by both asset and transformer controls")
	operations.station_capacity.value=75.0
	operations.zone.text="保留的变电草案"
	operations.capture_drafts()
	clear_modals()
	game.focus_target("facility",5)
	game.hud.lens_buttons.customers.pressed.emit()
	await settle()
	press_key(desk(),"center:customers")
	await settle()
	check(operations.customer_picker.get_selected_id()==5 and is_equal_approx(float(operations.fields.pv_mw.value),3.5),"returning to hospital coordination retains its unsubmitted solar draft")
	clear_modals()
	game.focus_target("line",3)
	game.hud.lens_buttons.assets.pressed.emit()
	await settle()
	press_key(desk(),"center:assets")
	await settle()
	operations.delay.value=.9
	operations.capture_drafts()
	clear_modals()
	game.focus_target("line",2)
	game.hud.lens_buttons.assets.pressed.emit()
	await settle()
	press_key(desk(),"center:assets")
	await settle()
	check(operations.line_picker.get_selected_id()==2 and is_equal_approx(float(operations.delay.value),1.35),"returning to the original line restores its independent protection draft")
	check(is_equal_approx(float(operations.station_capacity.value),75.0) and operations.zone.text=="保留的变电草案","cross-department target changes also retain the separate substation draft")
	check(game.sim.customers.devices.is_empty() and game.sim.engineering.line_settings.is_empty() and game.sim.engineering.substation_settings.is_empty(),"retained center drafts never commission or apply themselves to simulation")
	clear_modals()
	game.hud.lens_buttons.planning.pressed.emit()
	await settle()
	press_key(desk(),"center:planning")
	await settle()
	check(game.planning_panel.visible and game.planning_panel.tabs.current_tab==3 and not game.planning_panel.tabs.is_tab_hidden(3),"planning department opens the actual available comparison tab")
	clear_modals()
	game.sim.start_campaign(12)
	game._rebuild_session(true)
	game.speed=0
	clear_modals()
	game.hud.lens_buttons.assets.pressed.emit()
	await settle()
	press_key(desk(),"center:assets")
	await settle()
	check(network.visible and not network.tabs.is_tab_hidden(network.tabs.current_tab),"historical department navigation skips an already-created but now-hidden advanced tab")
	clear_modals()
	game.hud.lens_buttons.planning.pressed.emit()
	await settle()
	press_key(desk(),"center:planning")
	await settle()
	check(game.planning_panel.visible and not game.planning_panel.tabs.is_tab_hidden(game.planning_panel.tabs.current_tab),"historical planning skips its unavailable comparison tab")
	game.sim.restore_snapshot(baseline)
	game._rebuild_session(true)
	game.speed=0
	clear_modals()

func _incidents_and_risk_focus() -> void:
	var hospital_id := -1
	for building in game.sim.buildings:
		if building.kind == "hospital": hospital_id = int(building.id); break
	check(hospital_id >= 0,"test city has an actual hospital load")
	if hospital_id < 0: return
	for line in game.sim.lines:
		if hospital_id in [int(line.a),int(line.b)]: line.closed = false; line.fault = true
	game.sim.next_storm_at = 10000.0
	game.sim.digital.next_attack_at = 10000.0
	game.sim._refresh()
	game.sim.step(.1)
	game._sync_world(true)
	game._update_hud()
	game.hud.lens_buttons.customers.pressed.emit()
	await settle()
	var before := state()
	var risk: Dictionary = {}
	for row in desk().snapshot.risks:
		if int(row.get("target_id",-1)) == hospital_id: risk = row; break
	check(not risk.is_empty(),"customer desk identifies public hospital impact")
	if not risk.is_empty():
		press_key(desk(),"expand:risk:" + str(risk.id))
		await settle()
		press_key(desk(),"risk:" + str(risk.id) + ":focus")
		await settle()
		check(game.selected_id == hospital_id,"risk evidence drills into the actual affected facility")
	game.hud.lens_buttons.customers.pressed.emit()
	await settle()
	press_key(desk(),"expand:reliability")
	await settle()
	var report: Dictionary = game.sim.reliability_metrics.report(game.sim)
	var incident: Dictionary = {}
	for row in report.incidents:
		if int(row.facility_id) == hospital_id: incident = row; break
	check(not incident.is_empty(),"persistent incidents include the real hospital interruption")
	if not incident.is_empty():
		for index in 4:
			var picker := metric_picker(desk())
			check(picker!=null,"reliability section exposes an actual metric selector")
			if picker==null: break
			picker.select(index)
			picker.item_selected.emit(index)
			await settle()
			var trend := reliability_chart(desk())
			check(trend!=null and trend.metric==["saidi_minutes","saifi","cmi","ens_mwh"][index] and not trend.rows.is_empty(),"reliability trend selector updates the real metric and unit")
		press_key(desk(),"contribution:"+str(incident.id))
		await settle()
		check(desk().expanded.get("incident:"+str(incident.id),false),"SAIDI contribution opens the contributing incident's evidence")
		press_key(desk(),"expand:incident:" + str(incident.id))
		await settle()
		press_key(desk(),"expand:incident:" + str(incident.id))
		await settle()
		check(desk().expanded.get("incident:" + str(incident.id),false),"nested incident exposes known facts and candidate actions")
		press_key(desk(),"incident:focus:" + str(incident.id))
		await settle()
		check(game.selected_id == hospital_id and game.hud.operator_dock.page == "object","incident locates its actual impacted load through the shared drawer")
	check(state() == before,"incident evidence and risk target navigation never execute recovery or advance time")

func _asset_matrix() -> void:
	game.sim.digital.facility_observations.clear()
	game.sim.digital.observations.clear()
	game.sim.get_building(1).health = 37.0
	game.sim.digital._sample_facility(game.sim,game.sim.get_building(1),"field")
	game.hud.lens_buttons.assets.pressed.emit()
	await settle()
	var chart: Control = chart_in(desk())
	check(chart != null,"asset department contains the actual health-impact chart")
	if chart == null: return
	desk().scroll.ensure_control_visible(chart)
	chart.queue_redraw()
	await settle()
	check(chart.rows.count({}) == 0 and chart.rows.any(func(row: Dictionary): return row.health==null),"matrix receives explicit unknown-health assets")
	check(chart.hit_regions.size() == 1,"unknown health is excluded from chart hit targets")
	if chart.hit_regions.is_empty(): return
	var before := state()
	var region: Dictionary = chart.hit_regions[0]
	var local: Vector2 = region.rect.get_center()
	click(chart.get_global_transform_with_canvas() * local)
	await settle()
	check(game.selected_id == 1,"real chart click locates its known-health facility")
	check(state() == before,"matrix click only inspects, without maintenance or costs")

func _connect_priority() -> void:
	game.sim.reset(42)
	game._rebuild_session(true)
	game.speed = 0
	clear_modals()
	game.hud.lens_buttons.operations.pressed.emit()
	game.hud.operator_dock.close()
	game.selected_id = -1
	game.hud.refresh_context()
	await settle()
	check(game.hud._focus_item.get("action","") == "connect","operations keeps the beginner's public unconnected-load priority")
	var id: int = int(game.hud._focus_item.get("target_id",-1))
	var before := state()
	game.hud.focus_action.pressed.emit()
	await settle()
	check(id>=0 and game.tool=="line" and game.connection_start==id,"priority card begins a real cable connection at that facility")
	check(state()==before,"beginning a connection does not prematurely build or pay")
	game._set_tool("select")

func _responsive() -> void:
	for resolution in [Vector2i(1280,720),Vector2i(1440,900)]:
		for ratio in [1.0,1.25,1.5]:
			root.size = resolution
			game.preferences.ui_scale = ratio
			game._apply_preferences()
			clear_modals()
			game.hud.lens_buttons.assets.pressed.emit()
			desk().expanded.outcomes = true
			desk().expanded.asset_list = true
			desk()._signature = ""
			desk().refresh()
			await settle(8)
			var caption := "%dx%d @%d%%" % [resolution.x,resolution.y,int(ratio*100)]
			var viewport := Rect2(Vector2.ZERO,root.get_visible_rect().size)
			check(viewport.encloses(game.hud.lens_panel.get_global_rect()),"role bar fits viewport with drawer open: " + caption)
			check(viewport.encloses(game.hud.inspector.get_global_rect()),"shared department drawer fits viewport: " + caption)
			check(not game.hud.lens_panel.get_global_rect().intersects(game.hud.inspector.get_global_rect()),"role bar and open workspace do not overlap: " + caption)
			for panel in [game.hud.city_panel,game.hud.navigation_panel]:
				if panel.is_visible_in_tree(): check(not game.hud.lens_panel.get_global_rect().intersects(panel.get_global_rect()),"role bar stays clear of objective and navigation: " + caption + " " + str(panel.name))
			var shown: Control = game.hud.lens_picker if game.hud.lens_picker.visible else game.hud.lens_flow
			check(game.hud.lens_panel.get_global_rect().encloses(shown.get_global_rect()),"narrow picker or seven role buttons fit their bar: " + caption)
			check(game.hud.lens_picker.visible == (game.root_ui.size.x<1120),"narrow role picker follows available logical width: " + caption)
			check(desk().body.size.x<=desk().scroll.size.x+1.0,"department content fits horizontal scroll viewport: " + caption)
			var bottom := keyed(desk(),"center:assets")
			check(bottom!=null,"bottom maintenance action is present: " + caption)
			if bottom!=null:
				desk().scroll.ensure_control_visible(bottom)
				await settle()
				var clip: Rect2 = desk().scroll.get_global_rect()
				check(desk().scroll.scroll_vertical>0 and clip.has_point(bottom.get_global_rect().get_center()),"vertical scrolling reaches the final action: " + caption)
