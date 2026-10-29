extends SceneTree
## Real-scene coverage: navigation, progressive UI, independent profile and restoration.
var game: Node
var checks := 0
var failures := 0
var capture_enabled := false
const TEST_PATHS := ["user://test_campaign_ui_profile.json","user://test_campaign_ui_save.json","user://test_campaign_ui_auto.json","user://test_campaign_ui_backup.json","user://test_campaign_ui_prior.json"]

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, caption: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error("FAIL: "+caption)
	else: print("PASS: "+caption)

func button(node: Node, caption: String) -> Button:
	if node is Button and caption in node.text: return node
	for child in node.get_children():
		var found := button(child,caption)
		if found!=null: return found
	return null

func settle() -> void:
	for i in range(4): await process_frame

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode=code
	event.pressed=true
	game._unhandled_input(event)

func capture(caption: String) -> void:
	if not capture_enabled: return
	await settle()
	await RenderingServer.frame_post_draw
	var folder := "res://.godot/campaign-ui-qa/screens"
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(caption+".png"))==OK,"capture "+caption)

func _run() -> void:
	capture_enabled="--capture-campaign" in OS.get_cmdline_user_args()
	for path in TEST_PATHS:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game.set_process(false)
	game.campaign_panel.profile_path=TEST_PATHS[0]
	game.campaign_save_path=TEST_PATHS[1]
	game.campaign_autosave_path=TEST_PATHS[2]
	game.campaign_backup_path=TEST_PATHS[3]
	game.campaign_panel.load_profile()
	await capture("welcome")
	check(game.welcome.visible and game.sim.buildings.size()==10,"modern welcome and default sandbox are preserved")
	button(game.welcome,"历史战役").pressed.emit()
	var panel: Control=game.campaign_panel
	check(panel.visible and panel.chapter_buttons.size()==15,"welcome opens the complete fifteen-chapter directory")
	check(not panel.chapter_buttons[1].disabled and panel.chapter_buttons[2].disabled,"only first chapter is initially unlocked")
	panel.request_start(2)
	check(not game._campaign_active(),"locked chapter cannot be entered through navigation method")
	panel.chapter_buttons[1].pressed.emit()
	await capture("prologue")
	check(panel.mode=="prologue" and not game._campaign_active(),"first chapter has an optional non-mutating historical prologue")
	button(panel,"跳过序章").pressed.emit()
	await capture("briefing")
	check(game._campaign_active() and game.sim.campaign.chapter_id==1 and panel.mode=="briefing","skipping prologue starts the real historical fixture and briefing")
	check(FileAccess.file_exists(TEST_PATHS[3]) and FileAccess.file_exists(TEST_PATHS[1]),"entering campaign backs up sandbox and saves separately")
	button(panel,"进入现场").pressed.emit()
	check(not panel.visible and game.hud.popups.missions.visible,"briefing enters map with the current task")
	var cash_before: float=game.sim.cash
	var time_before: float=game.sim.elapsed_hours
	check(panel.hint_level==0,"task does not disclose optional hints automatically")
	var hint := button(game.mission_box,"给我一个提示")
	check(hint!=null,"task offers an explicit hint action")
	if hint!=null: hint.pressed.emit()
	await capture("task_hint")
	check(panel.hint_level==1 and game.sim.cash==cash_before and game.sim.elapsed_hours==time_before,"requesting a hint does not grant money or advance simulation")
	game.hud.close_popups()
	key(KEY_M); key(KEY_N); key(KEY_4)
	check(not game.market_panel.visible and not game.digital_panel.visible and game.tool!="datalink","keyboard cannot enter future market or digital systems")
	game.hud.toggle_category("power")
	check(not game.build_buttons.solar.visible and not game.build_buttons.fusion.visible,"historical construction only shows chapter facilities")
	game.hud.close_tray()
	game._save()
	var first_map: String=game.terrain_identity
	var old_cash: float=game.sim.cash
	game.sim.step(.25)
	game._load()
	check(game._campaign_active() and is_equal_approx(game.sim.cash,old_cash),"campaign quick-load restores the independent campaign save")
	game.sim.save_game(TEST_PATHS[4])
	# UI completion fixture; model tests separately prove real mission reachability.
	game.sim.campaign.completed=true
	game._update_hud()
	await capture("report")
	check(panel.mode=="report" and int(panel.profile.unlocked)==2,"chapter completion shows report and unlocks the next chapter")
	game._update_hud()
	check(int(panel.profile.unlocked)==2,"report refresh cannot unlock additional chapters")
	game._load(TEST_PATHS[4])
	check(int(panel.profile.unlocked)==2,"loading a prior mission state never rolls discovery progress back")
	panel.open_directory()
	panel.chapter_buttons[2].pressed.emit()
	check(game.sim.campaign.chapter_id==2 and game.terrain_identity!=first_map,"same-size historical chapter changes rebuild terrain identity")
	check(game.visuals.size()==game.sim.buildings.size() and game.connection_start==-1,"chapter switch rebuilds matching visuals and clears transient tools")
	panel.close()
	game._open_center("planning")
	await capture("planning")
	check(game.planning_panel.visible and not game.planning_panel.scenario_toggle.visible,"campaign planning hides historical reset actions")
	check(not game.planning_panel.era_buttons[5].visible and game.planning_panel.tabs.is_tab_hidden(2),"campaign planning hides future era and unintroduced region mode")
	check(game.planning_panel.technology_buttons.ac_systems.visible,"second chapter exposes its allowed AC research")
	game.planning_panel.technology_buttons.ac_systems.pressed.emit()
	game.planning_panel.technology_action.pressed.emit()
	check(game.sim.evolution.project=="ac_systems","campaign planning submits the real selected research")
	game.planning_panel.close()
	game.selected_id=1
	game.connection_start=1
	game.restart_campaign_chapter()
	check(game.sim.campaign.chapter_id==2 and game.selected_id==-1 and game.connection_start==-1,"retry resets the current fixture and transient selection")
	check(int(panel.profile.unlocked)==2,"retry preserves discovered chapters")
	for resolution in [Vector2i(1280,720),Vector2i(1440,900),Vector2i(1920,1080)]:
		if capture_enabled: DisplayServer.window_set_size(resolution)
		root.size=resolution
		panel.open_directory()
		await settle()
		await capture("directory_%dx%d" % [resolution.x,resolution.y])
		var viewport_rect := Rect2(Vector2.ZERO,Vector2(resolution))
		check(viewport_rect.encloses(panel.body.get_global_rect()),"campaign window stays inside viewport at "+str(resolution))
	game.sim.start_campaign(11)
	game._rebuild_session(true)
	game._open_center("network")
	check(game.digital_panel.telemetry_button!=null and not game.digital_panel.telemetry_button.disabled,"digital center exposes the real level-one research action")
	game.digital_panel.telemetry_button.pressed.emit()
	check(game.sim.research_level==1 and game.digital_panel.telemetry_button.disabled,"chapter eleven stops research at telemetry level one")
	check(not game.digital_panel.response_button.visible and game.digital_panel.tabs.is_tab_hidden(2),"telemetry lesson hides demand response and security controls")
	game.sim.start_campaign(12)
	game._rebuild_session(true)
	game._open_center("network")
	check("设施远控研究" in game.digital_panel.telemetry_button.text and game.digital_panel.response_button.visible,"chapter twelve labels remote control and introduces demand response")
	game.sim.start_campaign(8)
	game._rebuild_session(true)
	var before_guide_cash: float=game.sim.cash
	game.campaign_panel.guide_to("build")
	check(game.hud.active_category=="storage" and game.cam_target==game._cell_position(Vector2i(28,28)) and game.sim.cash==before_guide_cash,"pumped-storage guidance locates the public hill region and correct catalog without building")
	game.sim.start_campaign(15)
	game.sim.campaign.step_index=3
	game._rebuild_session(true)
	root.size=Vector2i(1280,720)
	game.hud.toggle_popup("missions")
	for i in range(3):
		var extra_hint := button(game.mission_box,"给我一个提示")
		if extra_hint!=null: extra_hint.pressed.emit()
	await settle()
	check(Rect2(Vector2.ZERO,Vector2(1280,720)).encloses(game.hud.popups.missions.get_global_rect()),"long final lesson and all three hints stay inside the minimum viewport")
	game.return_to_sandbox()
	check(not game._campaign_active() and game.sim.buildings.size()==10 and game.sim.objectives.size()==4,"return restores the original sandbox backup")
	check(int(panel.profile.unlocked)==2,"returning to sandbox preserves campaign discovery")
	for path in TEST_PATHS:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	game.queue_free()
	await settle()
	print("CAMPAIGN UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
