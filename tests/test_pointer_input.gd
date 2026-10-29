extends SceneTree
## Real mouse events must use their captured position even if the OS pointer moved.
var game: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, caption: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("FAIL: "+caption)

func settle() -> void:
	for index in range(5): await process_frame

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)

func click(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)

func point(id: int) -> Vector2:
	return game.camera.unproject_position(game._cell_position(game.sim.get_building(id).cell)+Vector3.UP*.6)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await settle()
	game._begin_free_sandbox(true)
	game.set_process(false)
	game.speed = 0
	await physics_frame
	await settle()
	key(KEY_2)
	check(game.tool=="line","real key event selects cable tool")
	var before: int = game.sim.lines.size()
	click(point(2))
	await settle()
	check(game.connection_start==2,"captured mouse position selects actual substation endpoint")
	click(point(6))
	await settle()
	check(game.sim.lines.size()==before+1 and game.connection_start==-1,"second mouse event physically connects the industrial park")
	check(game.sim.get_building(6).powered,"real connection supplies the previously unconnected customer")
	check(game.cable_visuals.size()==game.sim.lines.size(),"rendered cables follow the real topology mutation")
	key(KEY_1)
	click(point(3))
	await settle()
	check(game.selected_id==3,"mouse selection uses remodeled house footprint")
	click(point(8))
	await settle()
	check(game.selected_id==8,"mouse selection uses remodeled turbine footprint")
	game._open_pause()
	var paused_cash: float = game.sim.cash
	click(point(1))
	await settle()
	check(game.pause_menu.visible and game.sim.cash==paused_cash,"pause overlay blocks real mouse input to the map")
	game.queue_free()
	await settle()
	print("POINTER INPUT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
