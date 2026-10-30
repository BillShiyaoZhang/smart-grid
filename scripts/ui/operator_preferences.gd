extends RefCounted
## Personal settings stay outside simulation snapshots, campaigns and sandbox saves.
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
const DEFAULTS := {
	"window_mode":"windowed", "window_resolution":Vector2i(1440,900), "vsync":true,
	"max_fps":60, "msaa_3d":2,
	"master_volume":0.8, "music_volume":0.5, "sfx_volume":0.75,
	"ambience_volume":0.55, "alerts_volume":0.75, "mute_unfocused":true,
	"pan_sensitivity":1.0, "zoom_sensitivity":1.0,
	"ui_scale":1.0, "high_contrast":false, "reduced_motion":false, "information_depth":"operator",
	"pause_unfocused":true, "autosave_seconds":90
}
const SECTIONS := {
	"display":["window_mode","window_resolution","vsync","max_fps","msaa_3d"],
	"audio":["master_volume","music_volume","sfx_volume","ambience_volume","alerts_volume","mute_unfocused"],
	"input":["pan_sensitivity","zoom_sensitivity"],
	"accessibility":["ui_scale","high_contrast","reduced_motion","information_depth"],
	"game":["pause_unfocused","autosave_seconds"]
}
const RESOLUTIONS := [Vector2i(1280,720),Vector2i(1440,900),Vector2i(1600,900),Vector2i(1920,1080)]
var window_mode := "windowed"
var window_resolution := Vector2i(1440,900)
var vsync := true
var max_fps := 60
var msaa_3d := 2
var master_volume := 0.8
var music_volume := 0.5
var sfx_volume := 0.75
var ambience_volume := 0.55
var alerts_volume := 0.75
var mute_unfocused := true
var pan_sensitivity := 1.0
var zoom_sensitivity := 1.0
var ui_scale := 1.0
var high_contrast := false
var reduced_motion := false
var information_depth := "operator"
var pause_unfocused := true
var autosave_seconds := 90
var bindings: Dictionary = DEFAULT_BINDINGS.duplicate()
var storage_path := DEFAULT_PATH
var _display_restore: Dictionary = {}
var _runtime_display_key := ""

func load_preferences(path: String=DEFAULT_PATH) -> void:
	storage_path=path
	_display_restore.clear()
	for key in DEFAULTS: set(key,DEFAULTS[key])
	bindings=DEFAULT_BINDINGS.duplicate()
	var config:=ConfigFile.new()
	if config.load(storage_path)!=OK: return
	for section in SECTIONS:
		for key in SECTIONS[section]:
			# Earlier releases stored presentation options in [display].
			var legacy_section: String="display" if section=="accessibility" else section
			var value: Variant=config.get_value(section,key,config.get_value(legacy_section,key,DEFAULTS[key]))
			if _valid_option(key,value): set(key,value)
	var stored_bindings: Variant=config.get_value("input","bindings",{})
	if stored_bindings is Dictionary:
		var used: Array[int]=[]
		var candidate: Dictionary={}
		for action in DEFAULT_BINDINGS:
			var raw: Variant=stored_bindings.get(action,DEFAULT_BINDINGS[action])
			if not _integer(raw) or int(raw)<=0 or int(raw)==KEY_ESCAPE or int(raw) in used: return
			used.append(int(raw))
			candidate[action]=int(raw)
		bindings=candidate

func save_preferences() -> Error:
	var config:=ConfigFile.new()
	for section in SECTIONS:
		for key in SECTIONS[section]:
			# Saving another setting cannot persist an unconfirmed display preview.
			config.set_value(section,key,_display_restore.get(key,get(key)))
	config.set_value("input","bindings",bindings)
	return config.save(storage_path)

func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value))

func _valid_option(key: String, value: Variant) -> bool:
	if not DEFAULTS.has(key): return false
	match key:
		"information_depth": return value is String and value in ["beginner","operator","engineer"]
		"window_mode": return value is String and value in ["windowed","borderless"]
		"window_resolution": return value is Vector2i and value in RESOLUTIONS
		"vsync","mute_unfocused","high_contrast","reduced_motion","pause_unfocused": return value is bool
		"max_fps": return _integer(value) and int(value) in [0,30,60,120]
		"msaa_3d": return _integer(value) and int(value) in [0,2,4]
		"autosave_seconds": return _integer(value) and int(value) in [0,90,180,300]
		"ui_scale": return (value is int or value is float) and float(value) in [1.0,1.25,1.5]
		"pan_sensitivity","zoom_sensitivity": return (value is int or value is float) and is_finite(float(value)) and float(value)>=0.5 and float(value)<=2.0
		_: return (value is int or value is float) and is_finite(float(value)) and float(value)>=0.0 and float(value)<=1.0

func set_option(key: String, value: Variant) -> Error:
	return set_options({key:value})

func set_options(values: Dictionary, persist: bool=true) -> Error:
	for key in values:
		if not _valid_option(str(key),values[key]): return ERR_INVALID_PARAMETER
	for key in values: set(key,values[key])
	var result: Error=save_preferences() if persist else OK
	changed.emit()
	return result

func reset_section(section: String) -> Error:
	if not SECTIONS.has(section): return ERR_INVALID_PARAMETER
	var values: Dictionary={}
	for key in SECTIONS[section]: values[key]=DEFAULTS[key]
	if section=="input": bindings=DEFAULT_BINDINGS.duplicate()
	return set_options(values)

func begin_display_preview(values: Dictionary) -> Error:
	for key in values:
		if str(key) not in ["window_mode","window_resolution"] or not _valid_option(str(key),values[key]): return ERR_INVALID_PARAMETER
	if _display_restore.is_empty(): _display_restore={"window_mode":window_mode,"window_resolution":window_resolution}
	return set_options(values,false)

func confirm_display_preview() -> Error:
	_display_restore.clear()
	return save_preferences()

func revert_display_preview() -> Error:
	if _display_restore.is_empty(): return OK
	var values: Dictionary=_display_restore.duplicate()
	_display_restore.clear()
	return set_options(values)

func available_resolutions(maximum: Vector2i=Vector2i.ZERO) -> Array[Vector2i]:
	if maximum==Vector2i.ZERO:
		maximum=Vector2i(1920,1080) if DisplayServer.get_name()=="headless" else DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var result: Array[Vector2i]=[]
	for resolution in RESOLUTIONS:
		if resolution.x<=maximum.x and resolution.y<=maximum.y: result.append(resolution)
	# The game requires 1280 × 720; retain that choice on smaller desktops.
	if result.is_empty(): result.append(RESOLUTIONS[0])
	return result

func apply_runtime(viewport: Viewport=null) -> void:
	Engine.max_fps=max_fps
	if is_instance_valid(viewport):
		viewport.msaa_3d={0:Viewport.MSAA_DISABLED,2:Viewport.MSAA_2X,4:Viewport.MSAA_4X}[msaa_3d]
	if DisplayServer.get_name()=="headless": return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var resolutions: Array[Vector2i]=available_resolutions()
	var actual: Vector2i=window_resolution if window_resolution in resolutions else resolutions[-1]
	var display_key:=str([window_mode,actual])
	if display_key==_runtime_display_key: return
	_runtime_display_key=display_key
	if window_mode=="borderless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS,true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS,false)
		DisplayServer.window_set_size(actual)
		var usable:=DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		DisplayServer.window_set_position(usable.position+(usable.size-actual)/2)

func bind_action(action: String, keycode: int) -> Error:
	if not bindings.has(action) or keycode<=0 or keycode==KEY_ESCAPE: return ERR_INVALID_PARAMETER
	var previous: int=int(bindings[action])
	for other in bindings:
		if other!=action and int(bindings[other])==keycode: bindings[other]=previous
	bindings[action]=keycode
	var result: Error=save_preferences()
	changed.emit()
	return result

func reset_bindings() -> Error:
	bindings=DEFAULT_BINDINGS.duplicate()
	var result: Error=save_preferences()
	changed.emit()
	return result

func matches(action: String, event: InputEventKey) -> bool:
	var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
	return bindings.has(action) and key==int(bindings[action])

func is_action_pressed(action: String) -> bool:
	return bindings.has(action) and Input.is_physical_key_pressed(int(bindings[action]))

func binding_label(action: String) -> String:
	return OS.get_keycode_string(int(bindings.get(action,0)))
