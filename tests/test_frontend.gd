extends SceneTree
## Full-scene menu lifecycle, safe continuation and real keyboard interaction.
var game: Node
var checks := 0
var failures := 0
const BASE := "user://test_frontend/"
const FILES := ["sandbox.json", "sandbox_auto.json", "campaign.json", "campaign_auto.json", "backup.json", "profile.json", "preferences.cfg", "blocked.pending"]

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, caption: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + caption)
	else: print("PASS: " + caption)

func settle() -> void:
	for frame in range(4): await process_frame

func press(code: int, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.shift_pressed = shift
	root.push_input(event)
	var released := event.duplicate() as InputEventKey
	released.pressed = false
	root.push_input(released)

func button(node: Node, caption: String) -> Button:
	if node is Button and caption in node.text: return node
	for child in node.get_children():
		var found := button(child, caption)
		if found != null: return found
	return null

func write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func remove(path: String) -> void:
	if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func clean_files() -> void:
	for filename in FILES:
		remove(BASE + filename)
		remove(BASE + filename + ".pending")

func close_modals() -> void:
	for panel in [game.welcome,game.pause_menu,game.settings_panel,game.confirmation,game.campaign_panel,game.help_modal,game.end_modal,game.market_panel,game.digital_panel,game.planning_panel]: panel.hide()
	game.hud.close_popups()
	game.hud.close_tray()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE))
	clean_files()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game.sandbox_save_path = BASE + "sandbox.json"
	game.sandbox_autosave_path = BASE + "sandbox_auto.json"
	game.campaign_save_path = BASE + "campaign.json"
	game.campaign_autosave_path = BASE + "campaign_auto.json"
	game.campaign_backup_path = BASE + "backup.json"
	game.campaign_panel.profile_path = BASE + "profile.json"
	game.campaign_panel.load_profile()
	game.preferences.storage_path = BASE + "preferences.cfg"
	game._refresh_title()
	await settle()
	check(game.welcome.visible and not game.session_started, "launch opens the real title without starting a player session")
	check(not game.hud.visible and not game.operator_map.visible, "title does not expose the in-game HUD")
	check(not game.welcome.buttons.resume.visible and game.welcome.buttons.campaign.has_focus(), "first-run title gives keyboard priority to the teaching campaign")
	var opening: Dictionary = game.sim.snapshot()
	game._process(95.1)
	check(game.sim.snapshot() == opening and game.autosave_clock == 0, "95 seconds on title neither advances the simulation nor starts the autosave clock")
	check(not FileAccess.file_exists(game.sandbox_save_path) and not FileAccess.file_exists(game.sandbox_autosave_path) and not FileAccess.file_exists(game.campaign_save_path), "title cannot create or overwrite any gameplay save")
	press(KEY_ESCAPE)
	await settle()
	check(game.welcome.visible and not game.session_started, "Escape cannot bypass the title into the display fixture")
	game.welcome.buttons.campaign.grab_focus()
	press(KEY_ENTER)
	await settle()
	check(game.campaign_panel.visible and game.campaign_panel.chapter_buttons.size() == 15, "keyboard activation opens all fifteen campaign chapters")
	press(KEY_ESCAPE)
	await settle()
	check(game.welcome.visible and not game.campaign_panel.visible and not game.session_started, "closing the title chapter directory returns to title")
	game.welcome.buttons.settings.grab_focus()
	press(KEY_ENTER)
	await settle()
	check(game.settings_panel.visible and game._settings_origin == "title", "title opens the shared settings with a recorded return origin")
	press(KEY_ESCAPE)
	await settle()
	check(game.welcome.visible and not game.settings_panel.visible and game.welcome.buttons.settings.has_focus(), "settings Escape restores title and its settings focus")
	game._begin_free_sandbox()
	game.hud.close_popups()
	game.speed = 3
	game.previous_speed = 3
	var elapsed: float = game.sim.elapsed_hours
	game._open_pause()
	game._process(2.0)
	check(game.pause_menu.visible and game.sim.elapsed_hours == elapsed and game.speed == 3, "pause menu halts simulation without changing the selected speed")
	game.pause_menu.buttons.settings.pressed.emit()
	await settle()
	check(game._settings_origin == "paused" and game.settings_panel.visible, "pause settings retain their source menu")
	press(KEY_ESCAPE)
	await settle()
	check(game.pause_menu.visible and not game.settings_panel.visible, "closing settings returns to pause")
	game._open_campaign_directory()
	press(KEY_ESCAPE)
	await settle()
	check(game.pause_menu.visible and not game.campaign_panel.visible, "closing the pause chapter directory returns to pause")
	press(KEY_ESCAPE)
	await settle()
	check(not game.pause_menu.visible and game.speed == 3, "resuming preserves the original 3x multiplier")
	game.speed = 0
	game._open_pause()
	press(KEY_ESCAPE)
	await settle()
	check(game.speed == 0 and not game.pause_menu.visible, "resuming a manually paused game preserves zero speed")
	game.sim.cash = 123456.0
	check(game._atomic_save(game.sandbox_save_path).ok, "manual fixture is saved through the real atomic path")
	game._finish_leave(false)
	check(game.welcome.buttons.resume.visible and "自由沙盘" in game.welcome.summary.text, "title shows valid manual progress and mode summary")
	game.sim.cash = 1.0
	game.welcome.buttons.resume.grab_focus()
	press(KEY_ENTER)
	await settle()
	check(game.session_started and not game.welcome.visible and is_equal_approx(game.sim.cash,123456.0), "title Continue restores the actual saved manual progress")
	remove(game.sandbox_save_path)
	game.sim.cash = 234567.0
	check(game._atomic_save(game.sandbox_autosave_path).ok, "independent automatic fixture is written")
	game._finish_leave(false)
	check(game.title_catalog.latest.path == game.sandbox_autosave_path and game.welcome.buttons.resume.visible, "autosave-only progress enables Continue")
	game.sim.cash = 2.0
	game.welcome.buttons.resume.pressed.emit()
	check(game.session_started and is_equal_approx(game.sim.cash,234567.0), "autosave-only Continue restores automatic progress")
	write(game.sandbox_save_path,"{\"schema_version\":7,\"broken\":true}")
	var broken_text := FileAccess.get_file_as_string(game.sandbox_save_path)
	game._finish_leave(false)
	check(game.title_catalog.invalid.has(game.sandbox_save_path) and game.title_catalog.latest.path == game.sandbox_autosave_path, "a corrupt newer manual file falls back to valid automatic progress")
	check(game.welcome.warning.visible and FileAccess.get_file_as_string(game.sandbox_save_path) == broken_text, "bad-save warning preserves the original invalid file")
	game.welcome.buttons.resume.pressed.emit()
	check(is_equal_approx(game.sim.cash,234567.0), "fallback Continue does not load the broken file into the active session")
	game._finish_leave(false)
	var before_cancel: Dictionary = game.sim.snapshot()
	game._request_new_mode("management")
	check(game.confirmation.visible, "starting a new shared-slot mode describes overwrite before proceeding")
	press(KEY_ESCAPE)
	await settle()
	check(not game.confirmation.visible and game.welcome.visible and not game.session_started and game.sim.snapshot() == before_cancel, "cancelling overwrite preserves the current title and model")
	check(FileAccess.get_file_as_string(game.sandbox_save_path) == broken_text, "cancelling overwrite never deletes prior save files")
	game._request_new_mode("management")
	button(game.confirmation,"确认开启新进度").pressed.emit()
	check(game.session_started and game.sim.management.state.active and FileAccess.file_exists(game.sandbox_save_path), "confirmed new management progress saves before replacing the shared slot")
	check(not FileAccess.file_exists(game.sandbox_autosave_path), "successfully replacing a shared slot removes the older automatic member")
	# Verify the historical slot can resume using only its automatic member.
	remove(game.sandbox_save_path)
	remove(game.sandbox_autosave_path)
	game.sim.start_campaign(1)
	game._rebuild_session(true)
	close_modals()
	game.sim.cash = 98765.0
	check(game._atomic_save(game.campaign_autosave_path).ok, "historical automatic fixture saves independently")
	remove(game.campaign_save_path)
	game._finish_leave(false)
	check(game.title_catalog.latest.mode == "campaign" and game.welcome.buttons.resume.visible, "campaign-only autosave is discovered at title")
	game._open_campaign_directory()
	var campaign_resume := button(game.campaign_panel,"继续战役")
	check(campaign_resume != null and not campaign_resume.disabled, "campaign directory also enables Continue when only its automatic save exists")
	campaign_resume.pressed.emit()
	check(game._campaign_active() and game.sim.campaign.chapter_id == 1 and is_equal_approx(game.sim.cash,98765.0), "campaign autosave restores chapter and budget")
	# Draft protection is exercised with real controls, not a mocked dirty flag.
	close_modals()
	game._begin_free_sandbox()
	game.market_panel.open()
	game.market_panel.flat_rate.value = 195
	check(game._has_unsent_drafts(), "real unsubmitted tariff control is detected as a draft")
	before_cancel = game.sim.snapshot()
	game._leave_session(false)
	check(game.confirmation.visible and game.session_started, "returning to title offers draft protection before replacing the session")
	press(KEY_ESCAPE)
	await settle()
	check(not game.confirmation.visible and game.market_panel.visible and game.market_panel.flat_rate.value == 195 and game.sim.snapshot() == before_cancel, "draft cancellation restores the exact page, entered value and model")
	game.market_panel.reset_session()
	game.market_panel.hide()
	game._open_pause()
	var correct_path: String = game.sandbox_save_path
	game.sandbox_save_path = BASE + "missing_parent/save.json"
	game._leave_session(false)
	check(game.confirmation.visible and game.session_started and game.pause_menu.visible, "save failure retains the playable session and pause source")
	check(button(game.confirmation,"重试保存") != null and button(game.confirmation,"不保存并返回主菜单") != null, "save failure exposes retry and explicit discard choices")
	button(game.confirmation,"取消，返回游戏").pressed.emit()
	check(not game.confirmation.visible and game.session_started, "cancelling save failure leaves the session intact")
	game.sandbox_save_path = correct_path
	game._open_settings()
	await settle()
	var settings: Control = game.settings_panel
	game.sandbox_save_path = BASE + "missing_parent/save.json"
	# This exercises window-close handling without ever allowing a real quit:
	# the deliberately missing parent guarantees the save-failure branch.
	game._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(game.session_started and game.confirmation.visible and not settings.visible, "window close from settings makes save failure visible above its former source")
	check(game._front_modal() == game.confirmation, "window-close error owns keyboard focus instead of hidden settings")
	press(KEY_ESCAPE)
	await settle()
	check(settings.visible and not game.confirmation.visible and game._settings_origin == "paused", "cancelling window close returns to the original settings source")
	game.sandbox_save_path = correct_path
	settings.select_section("display")
	var old_mode: String = game.preferences.window_mode
	settings._preview_display({"window_mode":"borderless"})
	check(settings.display_preview_active and settings.display_confirmation.visible, "display changes open a real confirmation with a timeout")
	for index in range(6):
		press(KEY_TAB)
		await settle()
		check(settings.display_confirmation.is_ancestor_of(root.gui_get_focus_owner()), "display-preview Tab focus stays inside its confirmation")
	press(KEY_ESCAPE)
	await settle()
	check(not settings.display_preview_active and settings.visible and game.preferences.window_mode == old_mode, "display-preview Escape restores the old mode while retaining settings")
	settings._preview_display({"window_resolution":Vector2i(1280,720)})
	press(KEY_TAB)
	press(KEY_ENTER)
	await settle()
	check(not settings.display_preview_active and game.preferences.window_resolution == Vector2i(1280,720), "display settings can be kept entirely using keyboard")
	settings._preview_display({"window_resolution":Vector2i(1920,1080)})
	settings._process(15.1)
	check(not settings.display_preview_active and game.preferences.window_resolution == Vector2i(1280,720), "unconfirmed display size reverts after fifteen seconds")
	settings._capture("repair")
	press(KEY_J)
	await settle()
	check(game.preferences.bindings.repair == KEY_J and settings.pending_action.is_empty(), "real key event rebinds an action in shared settings")
	settings._capture("repair")
	press(KEY_ESCAPE)
	await settle()
	check(settings.visible and settings.pending_action.is_empty() and game.preferences.bindings.repair == KEY_J, "Escape cancels binding capture before closing the settings")
	game.audio.reset_session(game._audio_baseline())
	settings.select_section("audio")
	button(settings,"试听警报").pressed.emit()
	check(game.audio.played_cues.any(func(row: Dictionary): return row.cue == "warning" and row.bus == "Alerts"), "sound settings preview produces a routed audible cue")
	settings.close()
	game._close_pause()
	game.sim.cash = 345678.0
	game._leave_session(false)
	check(not game.session_started and game.welcome.visible and FileAccess.file_exists(game.sandbox_save_path), "successful return to title saves and removes the active session")
	game.sim.cash = 3.0
	game.welcome.buttons.resume.pressed.emit()
	check(game.session_started and is_equal_approx(game.sim.cash,345678.0), "returning from title can continue the session that was just saved")
	game.queue_free()
	await settle()
	clean_files()
	print("FRONTEND: %d checks, %d failures" % [checks,failures])
	quit(1 if failures > 0 else 0)
