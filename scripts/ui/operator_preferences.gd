extends RefCounted
## Personal presentation/input options live outside campaign and sandbox saves.
signal changed

const DEFAULT_PATH := "user://operator_preferences.cfg"
const DEFAULT_BINDINGS := {
	"pause": KEY_SPACE, "select": KEY_1, "line": KEY_2, "repair": KEY_3,
	"datalink": KEY_4, "rotate_left": KEY_Q, "rotate_right": KEY_E,
	"save": KEY_F5, "load": KEY_F9, "help": KEY_H, "market": KEY_M,
	"network": KEY_N, "planning": KEY_T, "move_up": KEY_W,
	"move_down": KEY_S, "move_left": KEY_A, "move_right": KEY_D
}
const ACTION_NAMES := {
	"pause":"暂停 / 继续", "select":"选择", "line":"电缆接线", "repair":"现场抢修",
	"datalink":"通信布线", "rotate_left":"向左旋转", "rotate_right":"向右旋转",
	"save":"保存", "load":"读取", "help":"操作手册", "market":"经营工作台",
	"network":"运维工作台", "planning":"发展规划", "move_up":"视角向上",
	"move_down":"视角向下", "move_left":"视角向左", "move_right":"视角向右"
}
var ui_scale := 1.0
var high_contrast := false
var reduced_motion := false
var bindings: Dictionary = DEFAULT_BINDINGS.duplicate()
var storage_path := DEFAULT_PATH

func load_preferences(path: String=DEFAULT_PATH) -> void:
	storage_path = path
	var config := ConfigFile.new()
	if config.load(storage_path) != OK: return
	var stored_scale: float = float(config.get_value("display","ui_scale",1.0))
	ui_scale = stored_scale if stored_scale in [1.0,1.25,1.5] else 1.0
	high_contrast = bool(config.get_value("display","high_contrast",false))
	reduced_motion = bool(config.get_value("display","reduced_motion",false))
	var stored_bindings: Variant = config.get_value("input","bindings",{})
	if stored_bindings is Dictionary:
		var used: Array[int] = []
		var candidate: Dictionary = {}
		for action in DEFAULT_BINDINGS:
			var key: int = int(stored_bindings.get(action,DEFAULT_BINDINGS[action]))
			if key <= 0 or key == KEY_ESCAPE or key in used:
				bindings = DEFAULT_BINDINGS.duplicate()
				return
			used.append(key)
			candidate[action] = key
		bindings = candidate

func save_preferences() -> Error:
	var config := ConfigFile.new()
	config.set_value("display","ui_scale",ui_scale)
	config.set_value("display","high_contrast",high_contrast)
	config.set_value("display","reduced_motion",reduced_motion)
	config.set_value("input","bindings",bindings)
	return config.save(storage_path)

func set_option(key: String, value: Variant) -> Error:
	match key:
		"ui_scale":
			if not float(value) in [1.0,1.25,1.5]: return ERR_INVALID_PARAMETER
			ui_scale = float(value)
		"high_contrast": high_contrast = bool(value)
		"reduced_motion": reduced_motion = bool(value)
		_: return ERR_INVALID_PARAMETER
	var result: Error = save_preferences()
	changed.emit()
	return result

func bind_action(action: String, keycode: int) -> Error:
	if not bindings.has(action) or keycode <= 0 or keycode == KEY_ESCAPE:
		return ERR_INVALID_PARAMETER
	# Swap the previous action rather than silently leaving another action unbound.
	var previous: int = int(bindings[action])
	for other in bindings:
		if other != action and int(bindings[other]) == keycode:
			bindings[other] = previous
	bindings[action] = keycode
	var result: Error = save_preferences()
	changed.emit()
	return result

func reset_bindings() -> Error:
	bindings = DEFAULT_BINDINGS.duplicate()
	var result: Error = save_preferences()
	changed.emit()
	return result

func matches(action: String, event: InputEventKey) -> bool:
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	return bindings.has(action) and key == int(bindings[action])

func is_action_pressed(action: String) -> bool:
	return bindings.has(action) and Input.is_physical_key_pressed(int(bindings[action]))

func binding_label(action: String) -> String:
	return OS.get_keycode_string(int(bindings.get(action,0)))
