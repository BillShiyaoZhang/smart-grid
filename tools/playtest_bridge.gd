extends SceneTree
## Development-only live playtesting. Run with --script; normal games never load it.
## Commands use real Viewport mouse/key events, not model mutation or UI callbacks.
const ROOT := "res://.godot/live-playtest/"
var game: Node
var busy := false
var last_id := ""
var captures := 0

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	if FileAccess.file_exists(ROOT+"command.json"):
		var prior: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"command.json"))
		if prior is Dictionary: last_id = str(prior.get("id",""))
	root.size = Vector2i(1440,900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	# An isolated hidden rendering window cannot receive OS focus. These are test
	# overrides only; the actual focus options are exercised in dedicated tests.
	game.preferences.pause_unfocused = false
	game.preferences.mute_unfocused = false
	game._apply_preferences()
	await _settle(8)
	_write({"ready":true,"state":_state()})
	print("LIVE_PLAYTEST_READY: ",ProjectSettings.globalize_path(ROOT))

func _process(_delta: float) -> bool:
	if busy or game==null or not is_instance_valid(game): return false
	var path := ROOT+"command.json"
	if not FileAccess.file_exists(path): return false
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or str(parsed.get("id",""))==last_id: return false
	last_id = str(parsed.get("id",""))
	busy = true
	_execute(parsed)
	return false

func _execute(command: Dictionary) -> void:
	var error := ""
	match str(command.get("action","state")):
		"click":
			await _click(Vector2(float(command.get("x",0)),float(command.get("y",0))))
		"button":
			var control: Control = _find_button(root,str(command.get("text","")))
			if control==null: error = "Visible button not found: "+str(command.get("text",""))
			else: await _click(control.get_global_rect().get_center())
		"key":
			var code: int = OS.find_keycode_from_string(str(command.get("key","Escape")))
			var event := InputEventKey.new()
			event.keycode = code
			event.physical_keycode = code
			event.ctrl_pressed = bool(command.get("ctrl",false))
			event.shift_pressed = bool(command.get("shift",false))
			event.pressed = true
			root.push_input(event,true)
			await process_frame
			event = event.duplicate()
			event.pressed = false
			root.push_input(event,true)
		"text":
			for character in str(command.get("text","")):
				var event := InputEventKey.new()
				event.unicode = character.unicode_at(0)
				event.pressed = true
				root.push_input(event,true)
		"wheel":
			var event := InputEventMouseButton.new()
			event.position = Vector2(float(command.get("x",720)),float(command.get("y",450)))
			event.button_index = MOUSE_BUTTON_WHEEL_UP if int(command.get("direction",1))>0 else MOUSE_BUTTON_WHEEL_DOWN
			event.pressed = true
			root.push_input(event,true)
		"wait": await create_timer(clampf(float(command.get("seconds",.2)),.01,30)).timeout
		"resize":
			var extent := Vector2i(int(command.get("width",1440)),int(command.get("height",900)))
			DisplayServer.window_set_size(extent)
			root.size = extent
		"quit":
			game.queue_free()
			await _settle(6)
			_write({"id":last_id,"finished":true})
			quit()
			return
	await _settle(6)
	var screenshot := ""
	if bool(command.get("capture",true)):
		await RenderingServer.frame_post_draw
		captures += 1
		screenshot = ROOT+"%03d.png" % captures
		root.get_texture().get_image().save_png(screenshot)
	_write({"id":last_id,"error":error,"screenshot":ProjectSettings.globalize_path(screenshot) if not screenshot.is_empty() else "","state":_state()})
	busy = false

func _click(at: Vector2) -> void:
	root.warp_mouse(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion,true)
	await _settle(2)
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event,true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)

func _settle(frames: int) -> void:
	for index in range(frames): await process_frame

func _visible(control: Control) -> bool:
	if not control.is_visible_in_tree(): return false
	var bounds := control.get_global_rect()
	if not Rect2(Vector2.ZERO,Vector2(root.size)).intersects(bounds): return false
	var parent: Node = control.get_parent()
	while parent!=null:
		if parent is Control and parent.clip_contents and not parent.get_global_rect().intersects(bounds): return false
		parent = parent.get_parent()
	return true

func _find_button(node: Node, text: String) -> Control:
	if node is Button and _visible(node) and not node.disabled and node.text.contains(text): return node
	for child in node.get_children():
		var result: Control = _find_button(child,text)
		if result!=null: return result
	return null

func _controls(node: Node, result: Array) -> void:
	if node is Control and _visible(node) and (node is BaseButton or node is Range or node is LineEdit):
		var rect: Rect2 = node.get_global_rect()
		var entry: Dictionary = {"path":str(node.get_path()),"type":node.get_class(),"x":rect.position.x,"y":rect.position.y,"width":rect.size.x,"height":rect.size.y}
		if node is Button: entry.text = node.text; entry.disabled = node.disabled
		if node is Range: entry.value = node.value
		result.append(entry)
	for child in node.get_children(): _controls(child,result)

func _state() -> Dictionary:
	var controls: Array = []
	_controls(game.root_ui,controls)
	var buildings: Array = []
	for building in game.sim.buildings:
		var screen: Vector2 = game.camera.unproject_position(game._cell_position(building.cell)+Vector3.UP*.5)
		buildings.append({"id":int(building.id),"kind":str(building.kind),"name":str(building.name),"cell":[building.cell.x,building.cell.y],"screen":[screen.x,screen.y]})
	var step: Dictionary = game.sim.campaign.current_step() if game.sim.campaign.active else {}
	return {"app_state":int(game.app_state),"session_started":bool(game.session_started),"title":game.welcome.visible,"pause":game.pause_menu.visible,"settings":game.settings_panel.visible,"settings_page":game.settings_panel.current_section,"campaign_panel":game.campaign_panel.visible,"campaign_mode":game.campaign_panel.mode,"chapter":int(game.sim.campaign.chapter_id),"step":int(game.sim.campaign.step_index),"step_title":str(step.get("title","")),"step_instruction":str(step.get("instruction","")),"speed":int(game.speed),"game_hour":float(game.sim.elapsed_hours),"cash":float(game.sim.cash),"tool":str(game.tool),"lines":game.sim.lines.size(),"selected":int(game.selected_id),"ui_scale":float(game.preferences.ui_scale),"camera_zoom":float(game.zoom),"controls":controls,"buildings":buildings,"audio":game.audio.get_debug_state() if game.audio else {}}

func _write(value: Dictionary) -> void:
	var file := FileAccess.open(ROOT+"response.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
