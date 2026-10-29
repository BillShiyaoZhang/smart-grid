extends SceneTree
const Preferences = preload("res://scripts/ui/operator_preferences.gd")
const Settings = preload("res://scripts/ui/settings_panel.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
const PATH := "user://test_settings.cfg"
const LEGACY_PATH := "user://test_settings_legacy.cfg"
var checks := 0
var failures := 0
var preview_cues: Array[String]=[]

func check(value: bool, caption: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(caption)

func _initialize() -> void:
	_run.call_deferred()

func _read() -> RefCounted:
	var preferences:=Preferences.new()
	preferences.load_preferences(PATH)
	return preferences

func _test_preferences() -> void:
	var legacy:=ConfigFile.new()
	legacy.set_value("display","ui_scale",1.5)
	legacy.set_value("display","high_contrast",true)
	legacy.set_value("display","reduced_motion",true)
	legacy.set_value("input","bindings",Preferences.DEFAULT_BINDINGS)
	check(legacy.save(LEGACY_PATH)==OK,"legacy personal config fixture saves")
	var migrated:=Preferences.new()
	migrated.load_preferences(LEGACY_PATH)
	check(migrated.ui_scale==1.5 and migrated.high_contrast and migrated.reduced_motion,"earlier display fields migrate without losing accessibility")
	check(migrated.music_volume==.5 and migrated.pause_unfocused and migrated.autosave_seconds==90,"new settings use safe defaults for old configurations")
	legacy.set_value("display","max_fps","fast")
	legacy.set_value("display","msaa_3d",16)
	legacy.set_value("display","window_mode","exclusive")
	legacy.set_value("audio","master_volume",NAN)
	legacy.set_value("audio","music_volume",-1)
	legacy.set_value("audio","mute_unfocused","false")
	legacy.set_value("input","pan_sensitivity",9)
	legacy.set_value("game","autosave_seconds",1)
	legacy.save(LEGACY_PATH)
	migrated.load_preferences(LEGACY_PATH)
	check(migrated.max_fps==60 and migrated.msaa_3d==2 and migrated.window_mode=="windowed","invalid display values recover independently")
	check(migrated.master_volume==.8 and migrated.music_volume==.5 and migrated.mute_unfocused,"invalid numeric and boolean audio fields recover independently")
	check(migrated.pan_sensitivity==1.0 and migrated.autosave_seconds==90,"invalid controls and save intervals recover independently")
	var prefs:=Preferences.new()
	prefs.load_preferences(PATH)
	for key in Preferences.DEFAULTS:
		check(prefs.get(key)==Preferences.DEFAULTS[key],"default "+key)
	var updates: Dictionary={"max_fps":120,"msaa_3d":4,"vsync":false,"master_volume":0.0,"music_volume":.31,"sfx_volume":.42,"ambience_volume":.26,"alerts_volume":.63,"mute_unfocused":false,"pan_sensitivity":1.75,"zoom_sensitivity":.65,"pause_unfocused":false,"autosave_seconds":300,"ui_scale":1.25,"high_contrast":true,"reduced_motion":true}
	check(prefs.set_options(updates)==OK,"all settings persist as one update")
	var restored: RefCounted=_read()
	for key in updates: check(is_equal_approx(float(restored.get(key)),float(updates[key])) if updates[key] is float else restored.get(key)==updates[key],"round trip "+key)
	var before: float=prefs.music_volume
	check(prefs.set_options({"music_volume":.9,"max_fps":41})==ERR_INVALID_PARAMETER and prefs.music_volume==before,"invalid batch does not partially mutate preferences")
	for pair in [["master_volume",-0.1],["alerts_volume",1.1],["sfx_volume",INF],["pan_sensitivity",.4],["zoom_sensitivity",2.1],["ui_scale",1.1],["window_resolution",Vector2i(900,600)],["vsync",1],["autosave_seconds",30],["unknown",true]]:
		check(prefs.set_option(pair[0],pair[1])==ERR_INVALID_PARAMETER,"reject invalid option "+str(pair[0]))
	check(prefs.available_resolutions(Vector2i(1366,768))==[Vector2i(1280,720)],"resolution menu filters to current screen bounds")
	check(prefs.available_resolutions(Vector2i(1920,1080)).size()==4,"full HD offers all four supported window sizes")
	prefs.set_option("music_volume",.2)
	prefs.set_option("ui_scale",1.5)
	prefs.bind_action("market",KEY_N)
	check(prefs.reset_section("audio")==OK and prefs.music_volume==.5 and prefs.master_volume==.8,"sound page reset restores its defaults")
	check(prefs.ui_scale==1.5 and prefs.bindings.market==KEY_N,"sound page reset preserves accessibility and input")
	prefs.set_option("pan_sensitivity",1.7)
	check(prefs.reset_section("input")==OK and prefs.pan_sensitivity==1 and prefs.bindings.market==KEY_M,"input page reset restores sensitivity and key mappings together")
	check(prefs.begin_display_preview({"window_mode":"borderless","window_resolution":Vector2i(1920,1080)})==OK,"display changes can be previewed before persistence")
	prefs.set_option("music_volume",.24)
	var staging: RefCounted=_read()
	check(staging.window_mode=="windowed" and staging.window_resolution==Vector2i(1440,900) and is_equal_approx(staging.music_volume,.24),"saving another page cannot persist unconfirmed display settings")
	check(prefs.revert_display_preview()==OK and prefs.window_mode=="windowed","display rollback restores confirmed values")
	prefs.begin_display_preview({"window_mode":"borderless"})
	check(prefs.confirm_display_preview()==OK and _read().window_mode=="borderless","confirmed window choice survives reload")
	var previous_cap: int=Engine.max_fps
	if DisplayServer.get_name()=="headless":
		prefs.apply_runtime(root)
		check(Engine.max_fps==120 and root.msaa_3d==Viewport.MSAA_4X,"runtime application controls frame cap and viewport antialiasing in headless mode")
	Engine.max_fps=previous_cap

func _button(node: Node, caption: String) -> Button:
	for item in node.find_children("*","Button",true,false):
		if item.text==caption: return item
	return null

func _test_panel() -> void:
	var host:=Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.theme=UI.create_theme()
	root.add_child(host)
	var prefs:=Preferences.new()
	prefs.load_preferences(PATH)
	prefs.set_options({"window_mode":"windowed","window_resolution":Vector2i(1440,900)})
	var panel:=Settings.new()
	host.add_child(panel)
	panel.setup(prefs)
	panel.sound_preview_requested.connect(func(cue: String): preview_cues.append(cue))
	panel.open()
	for frame in range(4): await process_frame
	check(panel.tabs.get_tab_count()==5 and panel.page_buttons.size()==5,"settings exposes five independent pages")
	check(panel.binding_buttons.size()==17,"all existing configurable input actions remain available")
	for section in Settings.SECTION_TITLES:
		panel.page_buttons[section].pressed.emit()
		check(panel.current_section==section and panel.tabs.current_tab==Settings.SECTION_TITLES.keys().find(section),"navigation selects "+section)
	panel.select_section("audio")
	_button(panel,"试听音效").pressed.emit()
	_button(panel,"试听警报").pressed.emit()
	check(preview_cues==["confirm","alert"],"sound audition buttons emit distinct audio routing cues")
	panel.option_controls.music_volume.value=.37
	check(is_equal_approx(prefs.music_volume,.37),"moving audio slider applies its current value immediately")
	panel._process(.31)
	check(is_equal_approx(_read().music_volume,.37),"slider changes persist after the write debounce")
	panel.select_section("accessibility")
	panel.scale_picker.item_selected.emit(1)
	check(prefs.ui_scale==1.25 and _read().ui_scale==1.25,"UI scale applies and saves through the real selector")
	panel.select_section("display")
	panel.option_controls.window_mode.item_selected.emit(1)
	check(panel.display_preview_active and prefs.window_mode=="borderless" and panel.display_preview_seconds_left==15,"selecting window mode starts the fifteen-second confirmation")
	check(root.gui_get_focus_owner()==panel._revert_display_button,"display preview initially focuses the safe rollback button")
	check(_read().window_mode=="windowed","window preview does not overwrite the on-disk confirmed setting")
	panel._process(15.1)
	check(not panel.display_preview_active and prefs.window_mode=="windowed" and panel.visible,"display timeout rolls back without leaving settings")
	panel._preview_display({"window_mode":"borderless"})
	panel._confirm_display_button.pressed.emit()
	check(not panel.display_preview_active and _read().window_mode=="borderless","display confirm button commits the choice")
	panel._preview_display({"window_mode":"windowed"})
	var escape:=InputEventKey.new()
	escape.pressed=true
	escape.keycode=KEY_ESCAPE
	panel._input(escape)
	check(panel.visible and not panel.display_preview_active and prefs.window_mode=="borderless","Escape cancels display preview before closing the settings page")
	panel._preview_display({"window_mode":"windowed"})
	panel.close()
	check(not panel.visible and prefs.window_mode=="borderless","closing settings rolls back unconfirmed display changes")
	panel.open()
	panel._capture("market")
	panel._input(escape)
	check(panel.visible and panel.pending_action.is_empty(),"Escape cancels key capture before dismissing settings")
	panel.select_section("audio")
	prefs.set_option("pan_sensitivity",1.8)
	panel._reset_current()
	check(prefs.music_volume==.5 and is_equal_approx(prefs.pan_sensitivity,1.8),"real page-reset button preserves other pages")
	if "--capture-settings" in OS.get_cmdline_user_args():
		await _capture(panel,host,prefs)
	panel.close()
	host.queue_free()
	await process_frame

func _capture(panel: Control, host: Control, prefs: RefCounted) -> void:
	var folder: String="res://.godot/settings-qa"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080)]:
		DisplayServer.window_set_size(resolution)
		root.size=resolution
		for frame in range(2): await process_frame
		var ratio: float=1.5 if resolution.x==1280 else 1.0
		host.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		host.scale=Vector2(ratio,ratio)
		host.size=root.get_visible_rect().size/ratio
		prefs.ui_scale=ratio
		panel._refresh_controls()
		for section in Settings.SECTION_TITLES:
			panel.select_section(section)
			for frame in range(5): await process_frame
			check(root.get_visible_rect().encloses(panel.get_global_rect()),"settings stays inside viewport at "+str(resolution))
			await RenderingServer.frame_post_draw
			var destination: String=folder.path_join("%s-%d.png" % [section,resolution.x])
			check(root.get_texture().get_image().save_png(destination)==OK,"render settings "+destination)

func _run() -> void:
	for path in [PATH,LEGACY_PATH]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_test_preferences()
	await _test_panel()
	for path in [PATH,LEGACY_PATH]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("SETTINGS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
