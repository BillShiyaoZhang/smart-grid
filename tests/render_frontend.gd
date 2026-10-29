extends SceneTree
## Actual graphical menu/settings matrix. Output stays in ignored QA storage.
var game: Node
var destination := ""
var captures := 0
var failures := 0
var geometry: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func settle() -> void:
	for frame in range(7): await process_frame

func capture(caption: String) -> void:
	game.notice_label.hide()
	game.tooltip_label.hide()
	await settle()
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	var result := rendered.save_png(destination.path_join(caption + ".png"))
	if result != OK:
		failures += 1
		push_error("Failed to capture " + caption)
	var row: Dictionary = {"state":caption,"layout":destination.get_file(),"viewport":str(root.size),"ui_size":str(game.root_ui.size)}
	if game.welcome.visible:
		row.title_scroll = str(game.welcome.scroll.get_global_rect())
		row.title_minimum = str(game.welcome.body.get_combined_minimum_size())
	if game.settings_panel.visible:
		row.settings_tab = str(game.settings_panel.tabs.get_global_rect())
		row.settings_minimum = str(game.settings_panel.tabs.get_current_tab_control().get_combined_minimum_size())
	geometry.append(row)
	captures += 1

func close_modals() -> void:
	for panel in [game.welcome,game.pause_menu,game.settings_panel,game.confirmation,game.campaign_panel,game.help_modal,game.end_modal,game.market_panel,game.digital_panel,game.planning_panel]: panel.hide()
	game.hud.close_popups()
	game.hud.close_tray()

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game.preferences.storage_path = "res://.godot/frontend-qa/preferences.cfg"
	game.sandbox_save_path = "user://render_frontend_sandbox.json"
	game.sandbox_autosave_path = "user://render_frontend_sandbox_auto.json"
	game.campaign_save_path = "user://render_frontend_campaign.json"
	game.campaign_autosave_path = "user://render_frontend_campaign_auto.json"
	game.campaign_panel.profile_path = "user://render_frontend_profile.json"
	game.campaign_panel.load_profile()
	for layout in [[Vector2i(1280,720),1.5],[Vector2i(1440,900),1.0],[Vector2i(1920,1080),1.0]]:
		var resolution: Vector2i = layout[0]
		var ratio: float = layout[1]
		destination = "res://.godot/frontend-qa/%dx%d_%d" % [resolution.x,resolution.y,int(ratio*100)]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
		game.preferences.window_resolution = resolution
		game.preferences.ui_scale = ratio
		game.preferences.high_contrast = false
		game._apply_preferences()
		DisplayServer.window_set_size(resolution)
		root.size = resolution
		await settle()
		close_modals()
		for path in game._save_paths():
			if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		game._finish_leave(false)
		await capture("title_first_run")
		game._begin_free_sandbox()
		game._atomic_save(game.sandbox_save_path)
		game._finish_leave(false)
		await capture("title_continue")
		game._continue_latest()
		close_modals()
		game._focus_working_area()
		game._open_pause()
		await capture("pause")
		game._open_settings()
		for section in ["display","audio","input","accessibility","game"]:
			game.settings_panel.select_section(section)
			await capture("settings_" + section)
		game.settings_panel.select_section("display")
		# Keep the requested viewport while showing the actual safety dialog.
		game.settings_panel._preview_display({"window_resolution":resolution})
		await capture("display_confirmation")
		game.settings_panel.revert_display()
		game.settings_panel.close()
		game._open_campaign_directory()
		game.campaign_panel.profile.unlocked = 15
		game.campaign_panel.profile.completed = [1,2,3,4]
		game.campaign_panel.open_directory()
		await capture("campaign_directory")
		game.campaign_panel.close()
		game._finish_leave(false)
	var file := FileAccess.open("res://.godot/frontend-qa/geometry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(geometry,"\t"))
	file.close()
	game.queue_free()
	await settle()
	await create_timer(.2).timeout
	print("FRONTEND RENDER: %d captures, %d failures" % [captures,failures])
	quit(1 if failures > 0 else 0)
