extends SceneTree
const Sim = preload("res://scripts/sim/grid_sim.gd")
const PATHS := ["user://test_campaign_visual_profile.json","user://test_campaign_visual_save.json","user://test_campaign_visual_auto.json","user://test_campaign_visual_backup.json","user://test_campaign_visual_sandbox.json","user://test_campaign_visual_sandbox_auto.json","user://test_campaign_visual_preferences.cfg"]
var game: Node
var checks := 0
var failures := 0

func check(value: bool, caption: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(caption)

func _initialize() -> void:
	_run.call_deferred()

func _button(node: Node, caption: String) -> Button:
	for item in node.find_children("*","Button",true,false):
		if item.text==caption: return item
	return null

func _settle() -> void:
	for frame in range(5): await process_frame

func _run() -> void:
	for path in PATHS:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await _settle()
	game.set_process(false)
	game.campaign_panel.profile_path=PATHS[0]
	game.campaign_save_path=PATHS[1]
	game.campaign_autosave_path=PATHS[2]
	game.campaign_backup_path=PATHS[3]
	game.sandbox_save_path=PATHS[4]
	game.sandbox_autosave_path=PATHS[5]
	game.preferences.storage_path=PATHS[6]
	var panel: Control=game.campaign_panel
	panel.load_profile()
	game._open_campaign_directory()
	await _settle()
	check(panel.visible and panel.mode=="directory" and panel.chapter_buttons.size()==15,"title opens all fifteen historical chapter cards")
	check(panel.chapter_cards.size()==15 and panel.selected_chapter==1,"chapter directory selects the first chapter for a new profile")
	check(not panel.chapter_buttons[1].disabled and panel.chapter_buttons[2].disabled,"new profile clearly gates later chapters")
	check(_button(panel,"返回沙盘")==null,"title chapter directory does not expose a sandbox restoration action")
	check(_button(panel,"继续战役").disabled,"continue is unavailable without a valid campaign save")
	var before: String=JSON.stringify(game.sim.snapshot(),"",true,true)
	panel.select_chapter(15)
	check(panel.selected_chapter==15 and panel.hero_enter_button.disabled and "15" in panel.hero_title.text,"locked chapter can be inspected without entering it")
	check(panel.hero_art.texture!=null and panel.hero_art.texture.resource_path=="res://assets/art/chapters/15.png","selected hero uses its own imported chapter artwork")
	check(JSON.stringify(game.sim.snapshot(),"",true,true)==before and not game.session_started,"browsing chapter art never changes the background session")
	panel.request_start(15)
	check(not game._campaign_active() and not game.confirmation.visible,"locked entry is rejected before overwrite confirmation")
	panel.chapter_buttons[1].pressed.emit()
	check(panel.mode=="prologue" and not game._campaign_active(),"first entry still offers the optional historical prologue")
	var escape:=InputEventKey.new()
	escape.keycode=KEY_ESCAPE
	escape.physical_keycode=KEY_ESCAPE
	escape.pressed=true
	root.push_input(escape)
	await _settle()
	check(panel.visible and panel.mode=="directory" and not game.session_started,"backing out of the prologue returns to a visible chapter directory")
	panel.chapter_buttons[1].pressed.emit()
	panel._finish_prologue()
	check(game._campaign_active() and panel.mode=="briefing" and game.session_started,"confirmed prologue starts the actual campaign fixture")
	panel.close()
	check(not panel.visible,"briefing close enters the active game rather than reopening the title")
	check(game.sim.save_game(PATHS[2]).ok,"isolated automatic campaign save is created")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATHS[1]))
	panel.profile.completed=[1,2]
	panel.profile.unlocked=3
	panel.profile.last_chapter=3
	panel.open_directory()
	await _settle()
	check(not _button(panel,"继续战役").disabled,"auto-only campaign progress enables the continue action")
	check(panel.selected_chapter==3 and not panel.hero_enter_button.disabled,"directory selects the latest available lesson")
	check(panel.chapter_buttons[1].text=="重玩" and not panel.chapter_buttons[3].disabled and panel.chapter_buttons[4].disabled,"completed, available and locked cards keep distinct entry states")
	panel.chapter_buttons[3].pressed.emit()
	check(game.confirmation.visible and game.sim.campaign.chapter_id==1,"enter button uses the real overwrite-confirmation flow")
	for button in game.confirm_body.find_children("*","Button",true,false):
		if "取消" in button.text: button.pressed.emit(); break
	check(not game.confirmation.visible and game.sim.campaign.chapter_id==1,"cancelling overwrite preserves the current campaign")
	for ratio in [1.0,1.5]:
		game.preferences.ui_scale=ratio
		game._layout_interface()
		await _settle()
		panel._layout_directory()
		check(panel._directory_columns.visible==(panel.size.x>=1050),"chapter layout responds to logical width at scale "+str(ratio))
		check(panel._chapter_list.get_parent()==(panel._directory_columns if panel.size.x>=1050 else panel._directory_stack),"chapter list moves into the correct responsive container")
		if panel.size.x<1050:
			check(panel._directory_stack.get_child(0)==panel._chapter_list and not panel._hero_image_frame.visible,"compact directory prioritizes chapter entry over decorative artwork")
	if "--capture-campaign-menu" in OS.get_cmdline_user_args(): await _capture(panel)
	game.session_started=false
	game.app_state=game.AppState.TITLE
	game._open_campaign_directory()
	panel.close()
	check(game.welcome.visible and not panel.visible and not game.session_started,"closing a title directory returns to the real main menu")
	game.queue_free()
	await _settle()
	for path in PATHS:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("CAMPAIGN VISUAL: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)

func _capture(panel: Control) -> void:
	var folder: String="res://.godot/campaign-menu-qa"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for layout in [[Vector2i(1280,720),1.0],[Vector2i(1280,720),1.5],[Vector2i(1920,1080),1.0]]:
		DisplayServer.window_set_size(layout[0])
		root.size=layout[0]
		game.preferences.ui_scale=layout[1]
		await _settle()
		game._layout_interface()
		panel.open_directory()
		panel.select_chapter(3,false)
		await _settle()
		if layout[1]==1.5:
			check(root.get_visible_rect().encloses(panel.chapter_buttons[1].get_global_rect()),"first chapter entry remains visible at minimum size and 150 percent scale")
		await RenderingServer.frame_post_draw
		var destination: String=folder.path_join("directory-%d-%d.png" % [layout[0].x,roundi(layout[1]*100)])
		check(root.get_texture().get_image().save_png(destination)==OK,"capture "+destination)
