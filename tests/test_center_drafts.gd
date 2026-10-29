extends SceneTree
## Real controls verify drafts survive unrelated commits and object/context changes.
const Drafts = preload("res://scripts/ui/config_drafts.gd")
const Catalog = preload("res://scripts/sim/campaign_catalog.gd")
var checks := 0
var failures := 0
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL: "+message)

func labels(node: Node) -> String:
	var result: String=str(node.text)+"\n" if node is Label else ""
	for child in node.get_children(): result+=labels(child)
	return result

func button(node: Node, caption: String) -> Button:
	if node is Button and caption in node.text: return node
	for child in node.get_children():
		var found: Button=button(child,caption)
		if found!=null: return found
	return null

func _run() -> void:
	var store: RefCounted=Drafts.new()
	store.retain("one",{"rate":10.0})
	store.retain("one",{"rate":10.0},{"rate":20.0})
	store.retain("two",{"rate":30.0})
	store.reset("two",{"rate":40.0})
	check(store.dirty("one") and store.values.one.rate==20.0,"independent sections retain edited values")
	store.retain("one",{"rate":20.0})
	check(not store.dirty("one"),"executed settings reconcile against effective baseline")
	store.clear()
	check(store.values.is_empty() and store.baselines.is_empty(),"session reset clears runtime drafts")
	for chapter_id in range(1,16):
		for step in Catalog.steps(chapter_id):
			check(step.hints.size()==3,"each chapter step has three hint levels")
			check(step.hints[0]!=step.hints[1] and step.hints[1]!=step.hints[2] and step.hints[0]!=step.hints[2],"hint levels provide distinct information")
			check(step.instruction not in step.hints and step.why not in step.hints,"hints do not repeat task text")
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.welcome.hide()
	game.sim.next_storm_at=100000.0
	game.sim.digital.next_attack_at=100000.0
	var market: Node=game.market_panel
	market.open()
	market.flat_rate.value=195
	market.buy_limit.value=265
	market._apply_policy()
	check(market.flat_rate.value==195 and game.sim.market.state.flat_rate==145,"applying trade does not discard or apply tariff draft")
	check(game.sim.market.state.buy_limit==265,"trade section alone is applied")
	market.tabs.current_tab=1
	market.close(); market.open()
	check(market.flat_rate.value==195 and market.tabs.current_tab==1,"closing and reopening preserves tariff and page")
	market.charge_price.value=200; market.discharge_price.value=100
	market._apply_storage()
	check(market.charge_price.value==200 and market.flat_rate.value==195 and market.message_label.text.begins_with("!"),"failed submission preserves all drafts with visible reason")
	market.reset_draft("tariff")
	check(market.flat_rate.value==145 and market.charge_price.value==200,"resetting one section preserves another draft")
	market.close()
	var digital: Node=game.digital_panel
	game.selected_id=1
	digital.open()
	check(digital.selected_device==1,"digital center inherits map device")
	digital.policy_picker.select(2)
	digital._commit(game.sim.upgrade_security())
	check(digital.policy_picker.selected==2 and game.sim.digital.state.policy=="open","unrelated digital action preserves unapplied policy")
	digital._select_device(2)
	digital.tabs.current_tab=2
	digital.close(); digital.open()
	check(digital.selected_device==2 and digital.tabs.current_tab==2 and digital.policy_picker.selected==2,"digital center retains its own selection and draft on reopen")
	digital._apply_policy()
	check(game.sim.digital.state.policy=="zero_trust" and not digital.drafts.dirty("security"),"applying security reconciles only its own draft")
	digital.policy_picker.select(1); digital.reset_policy_draft()
	check(digital.policy_picker.selected==2,"security reset returns effective strategy")
	digital.close()
	var planning: Node=game.planning_panel
	planning.open(); planning.select_facility(1)
	planning.dispatch_input.value=65
	planning.facility_method.select(1)
	planning.select_facility(9)
	planning.reserve_input.value=45
	planning.refresh(true)
	planning.close(); planning.open()
	check(planning.selected_facility==9 and planning.reserve_input.value==45,"facility selection and draft survive center reopen")
	planning.select_facility(1)
	check(planning.dispatch_input.value==65 and planning.facility_method.selected==1,"switching facilities restores each independent draft")
	planning._apply_facility()
	check(game.sim.get_building(1).dispatch==1.0 and "尚未应用" in planning.facility_execution.text,"queue acceptance is visibly distinct from effective dispatch")
	planning.select_facility(9)
	check(planning.reserve_input.value==45,"submitting one facility does not reset another")
	game.sim.step(.35)
	planning.select_facility(1)
	check(is_equal_approx(float(game.sim.get_building(1).dispatch),.65) and "已生效" in planning.facility_execution.text,"executed facility command is acknowledged from receipt")
	digital.refresh(false)
	check("已执行" in labels(digital.jobs_box),"digital receipt list retains finished commands")
	game.sim.research(); game.sim.research(); game.sim.step(.05)
	planning.select_facility(1)
	planning.dispatch_input.value=100; planning.facility_method.select(0)
	planning._apply_facility()
	check(game.sim.digital.pending_commands.size()==1,"remote facility setting enters real pending queue")
	game.sim.isolate_device(1,true); game.sim.step(.25); planning.refresh(false); digital.refresh(false)
	check(is_equal_approx(float(game.sim.get_building(1).dispatch),.65) and "未生效" in planning.facility_execution.text,"arrival rejection remains visible beside unchanged facility setting")
	check("已拒绝" in labels(digital.jobs_box),"digital queue shows rejected terminal receipt and reason")
	planning._toggle_comparison("battery"); planning._toggle_comparison("pumped_storage"); planning._toggle_comparison("hydrogen"); planning._toggle_comparison("wind")
	check(planning.comparison_kinds.size()==3 and "往返效率" in planning.comparison_label.text,"comparison limits to three and exposes actual storage tradeoffs")
	root.size=Vector2i(1440,900); game.preferences.ui_scale=1.0; game._apply_preferences()
	planning.tabs.current_tab=1; planning.facility_modes.current_tab=1
	for frame in range(5): await process_frame
	check(planning.comparison_grid.columns==3 and planning.comparison_grid.get_child_count()==3,"wide comparison shows three facility cards in three columns")
	var battery_card: Control=planning.comparison_cards.battery
	var pumped_card: Control=planning.comparison_cards.pumped_storage
	check(pumped_card.get_global_rect().position.x>battery_card.get_global_rect().end.x,"wide cards render side by side rather than sequential prose")
	check("基础维护" in labels(battery_card) and "88%" in labels(battery_card) and "180 MWh" in labels(pumped_card),"comparison exposes uniform maintenance efficiency and energy metrics")
	root.size=Vector2i(1280,720); game.preferences.ui_scale=1.5; game._apply_preferences()
	for frame in range(5): await process_frame
	check(planning.comparison_grid.columns==1 and pumped_card.get_global_rect().position.y>battery_card.get_global_rect().position.y,"narrow logical viewport stacks the same comparison cards")
	root.size=Vector2i(1440,900); game.preferences.ui_scale=1.0; game._apply_preferences()
	market.reset_session(); market.refresh(true)
	digital.reset_session(); digital.refresh(true)
	planning.reset_session(); planning.refresh(true)
	check(market.charge_price.value==game.sim.market.state.charge_price,"session reset clears market drafts")
	check(digital.policy_picker.selected==2 and digital.tabs.current_tab==0,"session reset binds effective digital state")
	check(not planning._facility_has_drafts() and planning.comparison_kinds.is_empty(),"session reset clears per-facility drafts and comparison")
	planning.close()
	market.open(); market.flat_rate.value=200
	var before_hours: float=game.sim.elapsed_hours
	game._new_game()
	check(game.confirmation.visible and game.sim.elapsed_hours==before_hours,"new game guards pending drafts before changing simulation")
	button(game.confirm_body,"取消，继续编辑").pressed.emit()
	check(not game.confirmation.visible and market.flat_rate.value==200,"canceling progress switch preserves the current draft")
	game._new_game(false,true); market.open()
	check(market.flat_rate.value==145 and not game._has_unsent_drafts(),"confirmed progress switch clears drafts and binds new effective values")
	market.close()
	game.sim.start_campaign(3)
	game.campaign_panel.reset_session()
	var focus: Dictionary=game.campaign_panel.current_focus_target()
	check(focus.get("kind","")=="building" and int(focus.get("id",-1))==int(game.sim.campaign.roles.source),"inspection task resolves named chapter source")
	check(game.campaign_panel.chapter_focus_ids().size()>=3,"chapter framing exposes active source and customers")
	game.sim.start_campaign(13); game.sim.campaign.step_index=2
	game.sim.digital.observations.erase(int(game.sim.campaign.roles.main_feeder))
	focus=game.campaign_panel.current_focus_target()
	check(focus.get("kind","")=="building" and int(focus.get("id",-1))==int(game.sim.campaign.roles.customer),"unknown physical fault guidance focuses affected customer instead of leaking exact damaged line")
	game.queue_free()
	await process_frame
	print("CENTER DRAFTS: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)
