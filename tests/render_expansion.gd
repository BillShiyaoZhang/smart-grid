extends SceneTree
## Real GPU output only; all generated captures and geometry stay ignored.
var game: Node
var destination: String
var captures:=0
var failures:=0
var geometry: Array[Dictionary]=[]

func _initialize() -> void: _run.call_deferred()

func settle() -> void:
	for _frame in 7: await process_frame

func wait_calculation(workbench: Node) -> void:
	var deadline:=Time.get_ticks_msec()+60000
	while (workbench.calculating or (workbench.has_method("worker_active") and workbench.worker_active())) and Time.get_ticks_msec()<deadline:
		await process_frame
	if workbench.calculating:
		failures+=1
		push_error("Forecast worker timed out during GPU preparation")

func capture(host: Node,title: String,anchor: Control=null) -> void:
	game.notice_label.hide()
	game.tooltip_label.hide()
	await settle()
	var outer: ScrollContainer=host.tabs.get_parent().get_parent()
	outer.scroll_vertical=0
	if anchor!=null:
		outer.ensure_control_visible(anchor)
		await settle()
		var scale_y:=maxf(0.1,outer.get_global_transform_with_canvas().get_scale().y)
		outer.scroll_vertical+=int(maxf(0.0,anchor.get_global_rect().position.y-outer.get_global_rect().position.y)/scale_y)
	await settle()
	await RenderingServer.frame_post_draw
	var result: Error=root.get_texture().get_image().save_png(destination.path_join(title+".png"))
	if result!=OK: failures+=1
	geometry.append({"layout":destination.get_file(),"state":title,"viewport":str(root.size),"ui_scale":float(game.preferences.ui_scale),"scroll_y":outer.scroll_vertical,"horizontal_scroll":outer.scroll_horizontal,"anchor":str(anchor.get_global_rect()) if anchor!=null else "entry"})
	captures+=1

func _run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game._activate_session()
	game.speed=0
	game.preferences.storage_path="res://.godot/expansion-qa/preferences.cfg"
	for id in ["ac_systems","protection","regional_planning","scada"]: game.sim.evolution.unlocked.append(id)
	game.sim.research_level=2
	game.sim.record_cash_change(820000.0,"scenario","区域经营验收资金")
	game.sim.next_storm_at=10000
	game.sim.digital.next_attack_at=10000
	game.sim.connect_buildings(2,6)
	var terminal: Dictionary=game.sim.build("intertie",Vector2i(5,12))
	game.sim.connect_buildings(2,int(terminal.id))
	for system in ["lifecycle","engineering","customers","strategy"]: game.sim.commission_expansion(system)
	game.sim.expansion_action("customer",{"id":3,"settings":{"metered":true,"consent":true,"pv_mw":2.0,"battery_mwh":5.0,"battery_mw":2.0,"ev_mw":2.0,"ev_target_mwh":4.0,"smart":true}})
	game.sim.strategy.take_loan(game.sim,50000.0,72.0)
	game.sim.strategy.start_project(game.sim,"gas",Vector2i(11,11))
	game.sim.strategy.submit_day_ahead(game.sim,[4.0,4.0,4.0,4.0])
	game.sim.strategy.configure_policy(game.sim,{"carbon_price":15.0,"production_subsidy":5.0,"tariff_cap":180.0,"reliability_target":.98,"reliability_penalty":20.0})
	game.sim.get_line(4).closed=false
	game.sim.step(.15)
	game.sim.get_line(4).closed=true
	game.sim.step(.15)
	game._sync_world(true)
	game._update_hud()
	game.planning_panel.open()
	game.planning_panel.tabs.current_tab=3
	game.planning_panel.decision_workbench.actions.forecast.pressed.emit()
	await wait_calculation(game.planning_panel.decision_workbench)
	var forecast_rows: Array=game.planning_panel.decision_workbench.chart.rows.duplicate(true)
	var forecast_message: String=game.planning_panel.decision_workbench.message.text
	game.planning_panel.decision_workbench.actions.compare.pressed.emit()
	await wait_calculation(game.planning_panel.decision_workbench)
	var comparison_rows: Array=game.planning_panel.decision_workbench.chart.rows.duplicate(true)
	var comparison_message: String=game.planning_panel.decision_workbench.message.text
	var comparison_details: String=game.planning_panel.decision_workbench.details.text
	for layout in [[Vector2i(1280,720),1.0],[Vector2i(1280,720),1.5],[Vector2i(1440,900),1.0],[Vector2i(1920,1080),1.0]]:
		var resolution: Vector2i=layout[0]
		DisplayServer.window_set_size(resolution)
		root.size=resolution
		game.preferences.ui_scale=float(layout[1])
		game._apply_preferences()
		destination="res://.godot/expansion-qa/%dx%d_%d" % [resolution.x,resolution.y,int(float(layout[1])*100)]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
		game.planning_panel.open()
		game.planning_panel.tabs.current_tab=3
		var planning: Node=game.planning_panel.decision_workbench
		planning.chart.set_rows(forecast_rows)
		planning.message.text=forecast_message
		await capture(game.planning_panel,"forecast_24h",planning.chart)
		planning.chart.set_rows(comparison_rows)
		planning.details.text=comparison_details
		planning.message.text=comparison_message
		await capture(game.planning_panel,"plan_comparison",planning.details)
		game.planning_panel.close()
		game.market_panel.open()
		game.market_panel.tabs.current_tab=4
		var economy: Node=game.market_panel.decision_workbench
		await capture(game.market_panel,"economy_report")
		await capture(game.market_panel,"recovery_curve",economy.recovery_chart)
		await capture(game.market_panel,"economy_finance",economy.actions.loan)
		await capture(game.market_panel,"economy_policy",economy.actions.policy)
		game.market_panel.close()
		game.digital_panel.open()
		game.digital_panel.tabs.current_tab=4
		var operations: Node=game.digital_panel.grid_operations
		for index in 4:
			operations.section.select(index)
			operations.section.item_selected.emit(index)
			var anchor: Control=[operations.asset_picker,operations.line_picker,operations.customer_picker,operations.microgrid_name][index]
			await capture(game.digital_panel,"operations_%d" % index,anchor)
			if float(layout[1])==1.5:
				var detailed: Control=[operations.maintenance_buttons.inspect,operations.delay,operations.fields.ev_target_mwh,operations.microgrid_info][index]
				await capture(game.digital_panel,"operations_%d_actions" % index,detailed)
		game.digital_panel.close()
	var file:=FileAccess.open("res://.godot/expansion-qa/geometry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(geometry,"\t"))
	file.close()
	game.queue_free()
	await process_frame
	print("EXPANSION GPU: %d captures; %d failures" % [captures,failures])
	quit(1 if failures>0 else 0)
