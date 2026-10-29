extends SceneTree
## True keyboard events cannot activate background controls across operator modals.
const Sim = preload("res://scripts/sim/grid_sim.gd")
var game: Node
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, caption: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL: "+caption)

func button(parent: Node, caption: String) -> Button:
	if parent is Button and caption in parent.text: return parent
	for child in parent.get_children():
		var found: Button=button(child,caption)
		if found!=null: return found
	return null

func settle() -> void:
	for index in range(4): await process_frame

func press(keycode: int, shift: bool=false) -> void:
	var key:=InputEventKey.new()
	key.keycode=keycode
	key.physical_keycode=keycode
	if keycode>=KEY_SPACE and keycode<=126: key.unicode=keycode
	key.shift_pressed=shift
	key.pressed=true
	root.push_input(key)
	key=key.duplicate()
	key.pressed=false
	root.push_input(key)

func close_modals() -> void:
	for modal in [game.welcome,game.help_modal,game.end_modal,game.market_panel,game.digital_panel,game.planning_panel,game.campaign_panel,game.confirmation,game.settings_panel]:
		modal.hide()

func _test_modal(modal: Control, caption: String) -> void:
	await settle()
	var cash: float=float(game.sim.cash)
	var elapsed: float=float(game.sim.elapsed_hours)
	var level: int=int(game.sim.get_building(1).level)
	var background: Button=button(game.inspector_box,"升级")
	check(background!=null and not background.disabled,caption+" fixture has an actionable background upgrade")
	background.grab_focus()
	press(KEY_ENTER)
	await settle()
	check(is_equal_approx(float(game.sim.cash),cash) and int(game.sim.get_building(1).level)==level,caption+" Enter cannot activate background upgrade")
	check(modal.visible and modal.is_ancestor_of(root.gui_get_focus_owner()),caption+" redirects background focus into front modal")
	background.grab_focus()
	press(KEY_SPACE)
	await settle()
	check(is_equal_approx(float(game.sim.cash),cash) and is_equal_approx(float(game.sim.elapsed_hours),elapsed),caption+" Space cannot buy upgrades or advance time behind modal")
	var controls: Array[Control]=[]
	game._modal_focusables(modal,controls)
	check(not controls.is_empty(),caption+" has visible focusable controls")
	for direction in [false,true]:
		for index in range(controls.size()+2):
			press(KEY_TAB,direction)
			await process_frame
			var focused: Control=root.gui_get_focus_owner()
			check(focused!=null and modal.is_ancestor_of(focused),caption+" Tab traversal stays in front modal")
	close_modals()

func _test_draft_guards() -> void:
	game.market_panel.open()
	game.market_panel.flat_rate.value=300
	game.market_panel.close()
	check(game._has_unsent_drafts(),"real market edit remains an unsent draft")
	var actions: Array[Callable]=[
		func(): game._load("user://test_operator_focus_missing.json"),
		func(): game.start_campaign_chapter(1),
		func(): game.restart_campaign_chapter(),
		func(): game.continue_campaign(),
		func(): game.return_to_sandbox(),
		func(): game._new_game()]
	for action in actions:
		var before: String=JSON.stringify(game.sim.snapshot(),"",true,true)
		action.call()
		await settle()
		check(game.confirmation.visible,"session replacement warns about unsent drafts")
		var focused: Control=root.gui_get_focus_owner()
		check(focused is Button and "取消" in focused.text,"discard confirmation initially focuses Cancel")
		press(KEY_ESCAPE)
		await settle()
		check(not game.confirmation.visible and game._has_unsent_drafts(),"Escape preserves drafts and dismisses replacement")
		check(JSON.stringify(game.sim.snapshot(),"",true,true)==before,"cancelled replacement leaves simulation unchanged")
	var campaign: RefCounted=Sim.new()
	campaign.start_campaign(1)
	game.campaign_save_path="user://test_operator_focus_campaign.json"
	game.campaign_autosave_path="user://test_operator_focus_campaign_autosave.json"
	check(campaign.save_game(game.campaign_save_path).ok,"isolated campaign fixture saves")
	game.continue_campaign()
	await settle()
	var confirm: Button=button(game.confirm_body,"确认切换")
	check(confirm!=null and game.confirmation.visible,"resume remains pending until explicit discard confirmation")
	confirm.pressed.emit()
	await settle()
	check(game.sim.campaign.active and game.market_panel.drafts.values.is_empty(),"confirmed resume replaces session and clears previous drafts")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.campaign_save_path))
	close_modals()

func _test_directory_focus() -> void:
	game.hud.operator_dock.show_page("watch")
	await settle()
	var target: Button=button(game.hud.operator_dock.body,"01")
	check(target!=null,"facility directory exposes selectable target")
	target.grab_focus()
	game.sim.totals.storm_in=float(game.sim.totals.get("storm_in",99))-.01
	game.hud.operator_dock.refresh()
	await settle()
	check(is_instance_valid(target) and root.gui_get_focus_owner()==target,"unrelated storm countdown preserves directory controls and focus")
	game.sim.digital._sample_facility(game.sim,game.sim.get_building(1),"field")
	game.hud.operator_dock.refresh()
	await settle()
	check(is_instance_valid(target) and root.gui_get_focus_owner()==target,"updated observed values reconcile directory in place")
	game.hud.operator_dock.close()

func _test_modal_inputs() -> void:
	game.market_panel.open()
	var option: OptionButton=game.market_panel.policy_mode
	option.grab_focus()
	press(KEY_ENTER)
	await settle()
	check(option.get_popup().visible,"modal OptionButton can open through actual Enter")
	press(KEY_DOWN)
	press(KEY_ENTER)
	await settle()
	check(option.selected==2 and not option.get_popup().visible,"popup arrows and Enter select an option without modal guard interference")
	var line: LineEdit=game.market_panel.buy_limit.get_line_edit()
	line.grab_focus()
	line.text="135"
	press(KEY_ENTER)
	await settle()
	check(is_equal_approx(float(game.market_panel.buy_limit.value),135),"modal numerical LineEdit can commit with Enter")
	check(not is_equal_approx(float(game.sim.market.state.buy_limit),135),"editing a numerical field alone does not apply a strategy")
	var apply: Button=button(game.market_panel,"应用交易策略")
	apply.grab_focus()
	press(KEY_ENTER)
	await settle()
	check(is_equal_approx(float(game.sim.market.state.buy_limit),135),"Enter on an in-modal Apply button commits the visible draft")
	var advance: Button=button(game.market_panel,"推进 1 小时")
	var elapsed: float=float(game.sim.elapsed_hours)
	advance.grab_focus()
	press(KEY_ENTER)
	await settle()
	check(is_equal_approx(float(game.sim.elapsed_hours),elapsed+1.0),"Enter on an in-modal advance button advances exactly one game hour")
	game.market_panel.close()
	game.hud.operator_dock.open_search()
	var speed: int=int(game.speed)
	press(KEY_SPACE)
	await settle()
	check(int(game.speed)==speed and " " in game.hud.operator_dock.search.text,"search typing does not invoke the global pause shortcut")
	game.hud.operator_dock.search.text=""
	game.hud.operator_dock.close()

func _run() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game.preferences.storage_path="res://.godot/operator_focus_preferences.cfg"
	game.campaign_panel.profile_path="res://.godot/operator_focus_profile.json"
	game.campaign_backup_path="res://.godot/operator_focus_before_campaign.json"
	game.speed=0
	close_modals()
	game.selected_id=1
	game._update_inspector()
	await settle()
	game._request_demolition(1)
	check(root.gui_get_focus_owner() is Button and "取消" in root.gui_get_focus_owner().text,"demolition confirmation initially focuses Cancel")
	await _test_modal(game.confirmation,"confirmation")
	game.market_panel.open()
	await _test_modal(game.market_panel,"market")
	game.digital_panel.open()
	await _test_modal(game.digital_panel,"digital")
	game.planning_panel.open()
	await _test_modal(game.planning_panel,"planning")
	game.campaign_panel.open_directory()
	await _test_modal(game.campaign_panel,"campaign")
	game.help_modal.show()
	await _test_modal(game.help_modal,"manual")
	game.welcome.show()
	await _test_modal(game.welcome,"welcome")
	game._show_result(true)
	await _test_modal(game.end_modal,"report")
	game.settings_panel.open()
	await _test_modal(game.settings_panel,"settings")
	game.settings_panel.open()
	game.settings_panel._capture("market")
	press(KEY_ESCAPE)
	await settle()
	check(game.settings_panel.visible and game.settings_panel.pending_action.is_empty(),"Escape cancels key capture before closing modal")
	press(KEY_ESCAPE)
	await settle()
	check(not game.settings_panel.visible,"second Escape closes settings")
	await _test_modal_inputs()
	await _test_directory_focus()
	await _test_draft_guards()
	game.queue_free()
	await settle()
	print("OPERATOR FOCUS: %d checks; %d failures" % [checks,failures])
	quit(1 if failures else 0)
