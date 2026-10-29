extends SceneTree
const Preferences = preload("res://scripts/ui/operator_preferences.gd")
const Chart = preload("res://scripts/ui/power_chart.gd")
const Settings = preload("res://scripts/ui/settings_panel.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
var failures := 0
var checks := 0

class ClockSnapshot:
	extends RefCounted
	var time_hours := 5.0
	var elapsed_hours := 10.0
	var day := 2

func check(value: bool, caption: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(caption)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "res://.godot/operator_preferences_test.cfg"
	var prefs := Preferences.new()
	prefs.load_preferences(path)
	check(prefs.set_option("ui_scale",1.5)==OK,"save UI scale")
	check(prefs.set_option("high_contrast",true)==OK,"save contrast")
	check(prefs.set_option("reduced_motion",true)==OK,"save motion preference")
	check(prefs.bind_action("market",KEY_N)==OK,"duplicate key swaps actions")
	check(prefs.bindings.network==KEY_M and prefs.bindings.market==KEY_N,"conflict preserves both bindings")
	check(prefs.bind_action("pause",KEY_ESCAPE)==ERR_INVALID_PARAMETER,"Escape remains reserved")
	var restored := Preferences.new()
	restored.load_preferences(path)
	check(restored.ui_scale==1.5 and restored.high_contrast and restored.reduced_motion,"display settings survive reload")
	check(restored.bindings.market==KEY_N and restored.bindings.network==KEY_M,"bindings survive reload")
	var event := InputEventKey.new()
	event.physical_keycode=KEY_N
	check(restored.matches("market",event),"physical key maps to remapped action")
	var chart := Chart.new()
	chart.sample(12,10,0,9)
	chart.sample(15,16,2,14)
	chart.sample(15,16,2,15)
	check(chart.history.size()==2 and chart.served_history[-1]==15,"paused sample replaces rather than advances timeline")
	check(chart.sample_hours==[0.0,2.0],"chart retains elapsed game hours")
	chart.sample(10,10,0,10)
	check(chart.history.size()==1,"loading earlier time clears old chart session")
	chart.history.clear()
	chart.sample(8,9,1,8)
	check(chart.history.size()==chart.sample_hours.size(),"legacy history clear remains compatible")
	chart.sim=ClockSnapshot.new()
	chart.sample(8,9,10,8)
	check(chart._time_label(10)=="D2 05:00","chart derives clock origin from the active scenario")
	chart.free()
	var host := Control.new()
	host.size=Vector2(853,480)
	host.theme=UI.create_theme(true)
	root.add_child(host)
	var panel := Settings.new()
	host.add_child(panel)
	panel.setup(restored)
	restored.ui_scale=1.25
	panel.open()
	for frame in range(5): await process_frame
	check(panel.visible and panel.binding_buttons.size()==17,"all input actions available in scrollable settings")
	check(panel.scale_picker.selected==1,"opening settings reflects the current preference object")
	panel._capture("market")
	var cancel := InputEventKey.new()
	cancel.keycode=KEY_ESCAPE
	cancel.pressed=true
	panel._input(cancel)
	check(panel.visible and panel.pending_action.is_empty(),"Escape cancels capture before closing settings")
	panel.close()
	host.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("OPERATOR PREFERENCES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures>0 else 0)
