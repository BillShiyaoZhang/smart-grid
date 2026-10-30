extends SceneTree
## Render every department and the important drilldowns at six accessible layouts.
## Captures are real Godot scenes and stay under the ignored .godot QA directory.
const Matrix = preload("res://scripts/ui/department_chart.gd")
const ReliabilityChart = preload("res://scripts/ui/reliability_chart.gd")
var game: Node
var destination := ""
var captures := 0
var failures := 0
var geometry: Array[Dictionary] = []
var hospital_id := -1
var comparison_ready := false
var operating_plans: Array = []
var maintenance_plans: Array = []

func _initialize() -> void:
	_run.call_deferred()

func settle(frames: int = 6) -> void:
	for _i in frames: await process_frame

func desk() -> Control:
	return game.hud.operator_dock.department_desk

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

func trend_in(parent: Node) -> Control:
	if parent.get_script() == ReliabilityChart: return parent
	for child in parent.get_children():
		var found := trend_in(child)
		if found != null: return found
	return null

func rect(control: Control) -> Array:
	var area := control.get_global_rect()
	return [snappedf(area.position.x,.1),snappedf(area.position.y,.1),snappedf(area.size.x,.1),snappedf(area.size.y,.1)]

func visible_fraction(control: Control) -> float:
	var original := control.get_global_rect()
	var visible: Rect2 = original.intersection(Rect2(Vector2.ZERO,root.get_visible_rect().size))
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents: visible = visible.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	return visible.get_area()/maxf(.001,original.get_area())

func clean() -> void:
	for modal in [game.welcome,game.pause_menu,game.help_modal,game.end_modal,game.confirmation,game.settings_panel,game.market_panel,game.digital_panel,game.planning_panel,game.campaign_panel]: modal.hide()
	game.hud.close_popups()
	game.hud.close_tray()
	game.hud.operator_dock.close()
	game.selected_id = -1
	game.selected_line = -1
	game.selected_comm_line = -1
	game._set_tool("select")
	game._update_inspector()
	game._update_hud()

func capture(caption: String) -> void:
	game.notice_label.hide()
	game.tooltip_label.hide()
	await settle()
	await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	var result: Error = rendered.save_png(destination.path_join(caption+".png"))
	if result != OK:
		failures += 1
		push_error("Could not save department capture: " + caption)
	var row: Dictionary = {"layout":destination.get_file(),"state":caption,"viewport":[root.size.x,root.size.y],"scale":game.preferences.ui_scale,"lens":game.hud.lens,"depth":game.preferences.information_depth,"modal":game._modal_open()}
	var viewport := Rect2(Vector2.ZERO,root.get_visible_rect().size)
	for pair in [["lens_bar",game.hud.lens_panel],["lens_buttons",game.hud.lens_flow],["lens_picker",game.hud.lens_picker],["depth_picker",game.hud.depth_picker],["workspace",game.hud.inspector],["dock",game.hud.dock_panel],["status",game.hud.status_panel]]:
		var control: Control = pair[1]
		if control.is_visible_in_tree():
			row[str(pair[0])] = rect(control)
			if not game._modal_open() and not viewport.encloses(control.get_global_rect()):
				failures += 1
				push_error("Capture control outside viewport: %s / %s / %s" % [caption,pair[0],destination.get_file()])
	if desk().is_visible_in_tree():
		row.drawer_clip = rect(desk().scroll)
		row.drawer_scroll = desk().scroll.scroll_vertical
		row.drawer_content_height = desk().body.size.y
		row.drawer_view_height = desk().scroll.size.y
		row.risks = desk().snapshot.get("risks",[]).size()
		row.unknown_assets = desk().snapshot.get("assets",[]).filter(func(asset: Dictionary): return asset.get("health")==null).size()
	if caption.begins_with("14-") or caption.begins_with("16-") or caption.begins_with("15-") or caption.begins_with("17-"):
		var delta: Control = game.planning_panel.decision_workbench.delta_view
		var table_state: bool = caption.begins_with("14-") or caption.begins_with("16-")
		var group: Control = delta.table if table_state else delta.charts
		if group == null or group.get_child_count()==0:
			failures += 1
			push_error("Missing real comparison content for " + caption)
		else:
			var first: Control = group.get_child(0)
			row.comparison_target = rect(first)
			row.comparison_visible_fraction = visible_fraction(first)
			if float(row.comparison_visible_fraction)<.95:
				failures += 1
				push_error("Comparison header/chart is clipped: %s / %s / %.3f visible" % [caption,destination.get_file(),float(row.comparison_visible_fraction)])
	geometry.append(row)
	captures += 1

func ensure_visible(control: Control) -> void:
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer and ancestor.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			ancestor.ensure_control_visible(control)
			return
		ancestor = ancestor.get_parent()

func prepare_fixture() -> void:
	game.sim.record_cash_change(420000.0,"test_setup","部门界面验收情景")
	# A render fixture still obeys the same save/forecast prerequisite graph.
	for technology in ["ac_systems","protection","regional_planning","scada"]:
		if technology not in game.sim.evolution.unlocked: game.sim.evolution.unlocked.append(technology)
	game.sim.research_level = 2
	game.sim.next_storm_at = 10000.0
	game.sim.digital.next_attack_at = 10000.0
	game.sim.connect_buildings(2,6)
	for building in game.sim.buildings:
		if building.kind == "hospital": hospital_id = int(building.id); break
	# Accumulate genuine multi-hour samples before and during the interruption.
	# Field orders are submitted afterwards so the queue remains active in shots.
	game.sim.step(2.0)
	for line in game.sim.lines:
		if hospital_id in [int(line.a),int(line.b)]: line.closed = false; line.fault = true
	game.sim._refresh()
	game.sim.step(1.0)
	game.sim.digital.commission_initial(game.sim,10)
	game.sim._refresh()
	game.sim.digital.sample_verified(game.sim)
	game.sim.get_building(1).health = 42.0
	game.sim.digital._sample_facility(game.sim,game.sim.get_building(1),"field")
	game.sim.get_building(9).health = 58.0
	game.sim.digital._sample_facility(game.sim,game.sim.get_building(9),"field")
	game.sim.digital.facility_observations.erase(8)
	game.sim.set_dispatch(1,.8,"field")
	game.sim.commission_expansion("lifecycle")
	game.sim.lifecycle.maintenance(game.sim,"facility",2,"inspect",1)
	game.sim.lifecycle.maintenance(game.sim,"facility",hospital_id,"inspect",2)
	game._sync_world(true)
	game._update_hud()
	game._focus_working_area()

func prepare_comparison() -> void:
	game.planning_panel.open()
	game.planning_panel.tabs.current_tab = 3
	var workbench: Node = game.planning_panel.decision_workbench
	workbench.fields.dispatch.value = .6
	workbench.fields.reserve.value = .4
	workbench.fields.failure_type.select(1)
	workbench.actions.compare.pressed.emit()
	comparison_ready = await wait_comparison(workbench,"运行方案")
	if comparison_ready: operating_plans = workbench.delta_view.plans.duplicate(true)
	if workbench.preview_maintenance_target("facility",9):
		workbench.actions.compare.pressed.emit()
		if await wait_comparison(workbench,"资产检修"):
			maintenance_plans = workbench.delta_view.plans.duplicate(true)
	game.planning_panel.hide()

func wait_comparison(workbench: Node, caption: String) -> bool:
	var deadline := Time.get_ticks_msec() + 60000
	while workbench.calculating and Time.get_ticks_msec()<deadline: await process_frame
	var ready: bool = not workbench.calculating and workbench.chart.rows.size()==24 and workbench.delta_view.plans.size()==3 and not workbench._result_stale
	if not ready:
		failures += 1
		push_error("Department capture %s comparison did not complete: calculating=%s; message=%s; status=%s" % [caption,str(workbench.calculating),str(workbench.message.text),str(workbench.status.text)])
	return ready

func show_comparison(asset_mode: bool = false) -> void:
	# Both datasets came from the real UI worker above. The real world remains
	# unchanged throughout the layout matrix; reuse those exact results per size.
	var workbench: Node = game.planning_panel.decision_workbench
	var plans: Array = maintenance_plans if asset_mode else operating_plans
	if plans.is_empty(): return
	workbench._write("comparison_mode","asset" if asset_mode else "operation")
	workbench._adapt_comparison_controls()
	workbench._comparison_titles.assign(["继续运行","计划保养","设备更换"] if asset_mode else ["当前","计划","退出情景"])
	workbench._display_comparison({"ok":true,"plans":plans})

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("render_departments.gd requires a graphical Godot renderer")
		quit(1)
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game._activate_session()
	game.speed = 0
	game.onboarding = false
	game.onboarding_skipped = true
	game.hud.onboarding_panel.hide()
	game.preferences.storage_path = "res://.godot/department-qa/preferences.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/department-qa"))
	game.preferences.information_depth = "engineer"
	game.preferences.reduced_motion = true
	game.preferences.max_fps = 0
	prepare_fixture()
	await prepare_comparison()
	for resolution in [Vector2i(1280,720),Vector2i(1440,900)]:
		for ratio in [1.0,1.25,1.5]:
			DisplayServer.window_set_size(resolution)
			root.size = resolution
			game.preferences.window_resolution = resolution
			game.preferences.ui_scale = ratio
			game._apply_preferences()
			destination = "res://.godot/department-qa/%dx%d_%d" % [resolution.x,resolution.y,int(ratio*100)]
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
			clean()
			game.hud.set_lens("operations",false)
			game.hud.operator_dock.close()
			game.hud.refresh_context()
			await capture("01-main")
			var index := 2
			for lens in game.hud.LENSES:
				clean()
				game.hud.set_lens(lens)
				desk().expanded.clear()
				desk()._signature = ""
				desk().refresh()
				desk().scroll.scroll_vertical = 0
				await capture("%02d-%s" % [index,lens])
				index += 1
			clean()
			game.hud.set_lens("assets")
			desk().expanded.asset_list = true
			desk()._signature = ""
			desk().refresh()
			await settle()
			var matrix: Control = chart_in(desk())
			if matrix != null: ensure_visible(matrix)
			await capture("09-asset-matrix")
			clean()
			game.hud.set_lens("customers")
			desk().expanded.reliability = true
			var incidents: Array = game.sim.reliability_metrics.report(game.sim).incidents
			var incident_id := -1
			for incident in incidents:
				if int(incident.facility_id) == hospital_id: incident_id = int(incident.id); break
			if incident_id>=0: desk().expanded["incident:"+str(incident_id)] = true
			desk()._signature = ""
			desk().refresh()
			await settle()
			var trend: Control = trend_in(desk())
			if trend != null: ensure_visible(trend)
			await capture("10-reliability-trend")
			var contribution := keyed(desk(),"contribution:"+str(incident_id))
			if contribution != null: ensure_visible(contribution)
			await capture("11-saidi-contribution")
			var incident_control := keyed(desk(),"expand:incident:"+str(incident_id))
			if incident_control != null: ensure_visible(incident_control)
			await capture("12-incident-evidence")
			clean()
			game.hud.operator_dock.show_page("jobs")
			await capture("13-unified-queue")
			clean()
			game.planning_panel.open()
			game.planning_panel.tabs.current_tab = 3
			show_comparison(false)
			await settle()
			var delta: Control = game.planning_panel.decision_workbench.get("delta_view")
			if delta != null and delta.visible:
				if delta.get("table") != null and delta.table.get_child_count()>0: ensure_visible(delta.table.get_child(0))
				else: ensure_visible(delta)
			await capture("14-comparison-delta-table")
			if delta != null and delta.visible and delta.get("charts") != null and delta.charts.get_child_count()>0: ensure_visible(delta.charts.get_child(0))
			await capture("15-comparison-common-scale-charts")
			show_comparison(true)
			await settle()
			if delta != null and delta.visible and delta.get("table") != null and delta.table.get_child_count()>0: ensure_visible(delta.table.get_child(0))
			await capture("16-asset-maintenance-delta-table")
			if delta != null and delta.visible and delta.get("charts") != null and delta.charts.get_child_count()>0: ensure_visible(delta.charts.get_child(0))
			await capture("17-asset-maintenance-common-scale-charts")
	var report := FileAccess.open("res://.godot/department-qa/geometry.json",FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify({"captures":captures,"failures":failures,"layouts":geometry},"\t"))
	else: failures += 1
	game.queue_free()
	await settle(2)
	print("DEPARTMENT RENDER MATRIX: %d captures; %d failures" % [captures,failures])
	quit(1 if failures else 0)
