extends SceneTree
## Semantic visual checks: values, drafts, shared scales and actual execution.
var game: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, caption: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL: "+caption)

func settle() -> void:
	for frame in range(5): await process_frame

func button(node: Node, caption: String) -> Button:
	if node is Button and caption in node.text: return node
	for child in node.get_children():
		var found:=button(child,caption)
		if found!=null: return found
	return null

func _run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game._activate_session()
	game.speed=0
	game.sim.next_storm_at=100
	game.sim.digital.next_attack_at=100
	var planning: Control=game.planning_panel
	planning.open()
	for kind in ["battery","pumped_storage","hydrogen"]: planning._toggle_comparison(kind)
	planning.tabs.current_tab=1
	planning.facility_modes.current_tab=1
	await settle()
	var comparison: Dictionary=planning.comparison_chart.snapshot
	check(comparison.items.size()==3,"comparison keeps three real alternatives")
	check(comparison.metrics[0].max==24 and comparison.metrics[1].max==20 and comparison.metrics[2].max==100,"power duration and efficiency share meaningful scales")
	check(comparison.items[0].capacity==10 and comparison.items[1].duration==7.5 and comparison.items[2].duration==20,"nominal duration comes from MWh divided by MW")
	check(is_equal_approx(comparison.items[0].efficiency,88.36) and is_equal_approx(comparison.items[2].efficiency,42.25),"round trip efficiency includes both conversions")
	check(not planning.comparison_grid.visible and planning.comparison_chart.visible,"detailed cards are collapsed behind the metric view")
	root.size=Vector2i(1280,720)
	game.preferences.ui_scale=1.5
	game._apply_preferences()
	await settle()
	check(planning.comparison_chart.size.x<=game.root_ui.size.x and planning.comparison_chart.snapshot.items.size()==3,"large text keeps alternatives together within the logical viewport")
	game.preferences.ui_scale=1
	game._apply_preferences()
	root.size=Vector2i(1440,900)
	planning.select_facility(1)
	planning.refresh()
	var rows: Array=planning.facility_chart.snapshot.rows
	check(rows.size()==3 and rows[0].value==24,"facility capacity separates rated available and actual")
	check(not rows[1].known and not rows[2].known,"unobserved output is not presented as a live zero")
	planning.close()
	var terminal: Dictionary=game.sim.build("intertie",Vector2i(4,5))
	game.sim.connect_buildings(2,int(terminal.id))
	var market: Control=game.market_panel
	market.open()
	market.tabs.current_tab=2
	var before: Dictionary=game.sim.snapshot().duplicate(true)
	market.charge_price.value=75
	market.discharge_price.value=180
	market.refresh()
	check(market.forecast_chart.is_visible_in_tree(),"storage decisions retain their price context")
	var draft_count:=0
	for line in market.forecast_chart.threshold_lines:
		if line.get("draft",false): draft_count+=1
	check(draft_count==2,"two edited thresholds remain visually distinct from effective values")
	check(game.sim.snapshot()==before,"chart refresh and threshold edits do not settle or advance")
	market.contract_mw.value=4
	market._update_commitment()
	check(market.contract_chart.snapshot.mw==4 and market.contract_chart.snapshot.hours==12,"contract area represents committed MW times twelve hours")
	check("合计约" in market.commitment_label.text,"total contractual payment remains explicit")
	market._advance()
	market.tabs.current_tab=3
	var sum_value:=0.0
	for row in market.waterfall_chart.snapshot.rows: sum_value+=float(row.value)
	check(not game.sim.market.ledger.is_empty() and is_equal_approx(sum_value,float(game.sim.market.ledger[-1].net)),"waterfall terminal amount equals actual ledger net")
	check(not market.ledger_details.visible,"wide ledger detail starts collapsed")
	market.intent_mode.select(0)
	market.intent_mode.item_selected.emit(0)
	market.export_toggle.set_pressed_no_signal(false)
	market._capture_intents()
	check(market.drafts.dirty("operating_intent") and game.sim.operating_policy().intent=="legacy_custom","new operating intent remains an explicit draft")
	market.close()
	market.open()
	check(market.intent_mode.selected==0 and market.drafts.dirty("operating_intent"),"new operating intent draft survives close and reopen")
	button(market,"应用经营目标").pressed.emit()
	check(game.sim.operating_policy().intent=="economic" and not game.sim.operating_policy().allow_export,"new economic action keeps export permission separate")
	market.storage_intent.select(0)
	market.storage_intent.item_selected.emit(0)
	market.intent_reserve.value=35
	button(market,"应用全网储能方案").pressed.emit()
	check(is_equal_approx(float(game.sim.storage_status(-1).reserve_soc),.35) and not market.drafts.dirty("storage_intent"),"global storage applies the single effective reserve and clears only its own draft")
	market.close()
	# The map and development workbench share a persistent per-facility draft.
	var host:=VBoxContainer.new()
	game.root_ui.add_child(host)
	var editor: Control=planning.create_facility_editor(host,1)
	await settle()
	editor.inputs.dispatch.value=70
	check(planning.drafts.dirty("1") and float(game.sim.get_building(1).dispatch)==1,"object editing stores a draft without changing output settings")
	var fields: Dictionary=planning.drafts.values["1"].duplicate(true)
	editor.refresh()
	check(planning.drafts.values["1"]==fields and editor.inputs.dispatch.value==70,"object refresh preserves the current editable draft")
	editor.method.select(0)
	editor._submit()
	check(game.sim.digital.field_jobs.size()==1 and float(game.sim.get_building(1).dispatch)==1,"object submission uses the actual delayed field queue")
	game.sim.step(.5)
	editor.refresh()
	check(is_equal_approx(float(game.sim.get_building(1).dispatch),.7),"object setting changes only after real execution")
	var storage_editor: Control=planning.create_facility_editor(host,9)
	check(storage_editor.inputs.intent.selected==3 and is_equal_approx(storage_editor.inputs.reserve.value,35),"storage editor shows inherited global policy and effective reserve")
	storage_editor.inputs.intent.select(2)
	storage_editor.inputs.intent.item_selected.emit(2)
	storage_editor.method.select(0)
	storage_editor._submit()
	check(game.sim.storage_status(9).inherited,"per-device storage override remains inactive while queued")
	game.sim.step(.5)
	storage_editor.refresh()
	check(game.sim.storage_status(9).intent=="arbitrage" and not game.sim.storage_status(9).inherited,"per-device storage override becomes real after the field task")
	storage_editor.inputs.intent.select(3)
	storage_editor.inputs.intent.item_selected.emit(3)
	storage_editor._submit()
	check(not game.sim.storage_status(9).inherited,"return to inheritance also waits for actual execution")
	game.sim.step(.5)
	storage_editor.refresh()
	check(game.sim.storage_status(9).inherited,"per-device override can return to global inheritance")
	game.sim.set_storage_intent("supply",.4)
	storage_editor.refresh()
	check(game.sim.storage_status(9).inherited and is_equal_approx(float(game.sim.storage_status(9).reserve_soc),.4) and storage_editor.inputs.reserve.value==40,"subsequent global changes reach the inheriting device and its editor")
	host.queue_free()
	game.digital_panel.open()
	var steps: Array=game.digital_panel.readiness_chart.snapshot.steps
	check(steps.size()==5 and steps[1].label=="通信路径" and steps[3].label=="新鲜观测","readiness uses conditions for one selected device rather than incomparable coverage denominators")
	game.digital_panel.close()
	game.sim.start_campaign(15)
	game._rebuild_session(true)
	game.sim.campaign.step_index=3
	game.mission_snapshot=""
	game._update_hud()
	check(game.campaign_panel.condition_gauges.has("supply") and game.campaign_panel.condition_gauges.has("clean") and game.campaign_panel.condition_gauges.has("net"),"combined assessment exposes each real success condition")
	# Professional controls preserve a new inherited policy when changing only
	# device permission, even before legacy reserve research has been purchased.
	game.sim.start_management_game(42)
	game._rebuild_session(true)
	game.speed=0
	planning.open()
	planning.select_facility(9)
	check(not game.sim.evolution.has_technology("regional_planning") and planning.storage_intent_input.selected==0 and planning.reserve_input.value==20,"new management professional controls show inherited effective reserve without legacy research")
	var legacy_reserve: float=float(game.sim.get_building(9).reserve_soc)
	planning.enabled_input.set_pressed_no_signal(false)
	planning.facility_method.select(1)
	planning._apply_facility()
	check(game.sim.digital.field_jobs.size()==1 and game.sim.get_building(9).enabled,"professional permission-only change is accepted into real field work")
	var pending: Dictionary=game.sim.digital.field_jobs[0].settings if not game.sim.digital.field_jobs.is_empty() else {}
	check(not pending.has("reserve_soc") and not pending.has("storage_mode") and not pending.has("storage_intent"),"permission-only payload contains no legacy reserve mode or scope changes")
	game.sim.step(.4)
	planning.refresh()
	check(not game.sim.get_building(9).enabled and game.sim.get_building(9).storage_intent=="inherit" and game.sim.storage_status(9).intent=="supply","permission change executes while preserving inherited supply intent")
	check(is_equal_approx(float(game.sim.get_building(9).reserve_soc),legacy_reserve),"permission change leaves the original legacy reserve untouched")
	planning.enabled_input.set_pressed_no_signal(true)
	planning._apply_facility()
	game.sim.step(.4)
	planning.refresh()
	check(game.sim.get_building(9).enabled and game.sim.storage_status(9).inherited,"professional re-enable preserves global inheritance")
	planning.reserve_input.value=35
	planning._apply_facility()
	check(game.sim.digital.field_jobs.size()==1 and game.sim.storage_status(9).inherited,"effective reserve edit waits for its actual execution before overriding")
	if not game.sim.digital.field_jobs.is_empty():
		var reserve_job: Dictionary=game.sim.digital.field_jobs[0].settings
		check(reserve_job.get("storage_intent","")=="supply" and reserve_job.get("storage_reserve",0)==.35 and not reserve_job.has("reserve_soc"),"effective reserve edit submits a new explicit per-device reserve")
	game.sim.step(.4)
	planning.refresh()
	check(not game.sim.storage_status(9).inherited and game.sim.storage_status(9).intent=="supply" and is_equal_approx(float(game.sim.storage_status(9).reserve_soc),.35),"effective reserve becomes an explicit supply override after field work")
	check(is_equal_approx(float(game.sim.get_building(9).reserve_soc),legacy_reserve) and planning.storage_intent_input.selected==1,"new override keeps legacy fields intact and displays its actual scope")
	planning.storage_intent_input.select(4)
	planning.storage_intent_input.item_selected.emit(4)
	check(planning.reserve_input.value==legacy_reserve*100 and planning.controls["储能运行策略"].visible,"explicit legacy selection imports raw legacy fields rather than effective reserve")
	planning._apply_facility()
	game.sim.step(.4)
	planning.refresh()
	check(game.sim.get_building(9).storage_intent=="legacy_custom" and game.sim.storage_status(9).legacy_custom,"legacy conversion occurs only after explicit selection and real execution")
	game.queue_free()
	await settle()
	print("VISUAL CENTERS: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)
