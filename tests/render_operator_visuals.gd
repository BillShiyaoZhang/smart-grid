extends SceneTree
const Sim = preload("res://scripts/sim/grid_sim.gd")
const Chart = preload("res://scripts/ui/power_chart.gd")
const DigitalMap = preload("res://scripts/ui/digital_map.gd")
const Preferences = preload("res://scripts/ui/operator_preferences.gd")
const Settings = preload("res://scripts/ui/settings_panel.gd")
const UI = preload("res://scripts/ui/ui_kit.gd")
var host: Control

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/operator-visual-qa"))
	root.size=Vector2i(1280,720)
	var sim := Sim.new()
	sim.reset(42)
	host=Control.new()
	host.size=Vector2(1280,720)
	host.theme=UI.create_theme()
	root.add_child(host)
	var background := ColorRect.new()
	background.size=host.size
	background.color=UI.SURFACE
	host.add_child(background)
	var column := UI.column(host,20)
	column.position=Vector2(24,24)
	column.size=Vector2(420,650)
	UI.label(column,"供需与可靠性 · MW",22)
	UI.label(column,"青绿供给 · 琥珀需求 · 白虚线已供 · 红区失供",14)
	var chart := Chart.new()
	chart.custom_minimum_size=Vector2(420,180)
	column.add_child(chart)
	for i in range(25):
		var demand: float = 20.0+sin(i*0.5)*5.0
		var served: float = demand-maxf(0,6.0-absf(float(i)-12.0))
		chart.sample(demand,24.0+sin(i*0.7)*4.0,float(i),served)
	var topology := Chart.new()
	topology.mode="topology"
	topology.sim=sim
	topology.custom_minimum_size=Vector2(420,180)
	column.add_child(topology)
	var empty := Chart.new()
	empty.custom_minimum_size=Vector2(420,90)
	column.add_child(empty)
	var digital := DigitalMap.new()
	digital.sim=sim
	digital.position=Vector2(510,80)
	digital.size=Vector2(710,440)
	host.add_child(digital)
	await capture("charts")
	column.hide()
	digital.hide()
	host.size=Vector2(1280,720)/1.5
	host.scale=Vector2.ONE*1.5
	var preferences := Preferences.new()
	preferences.storage_path="res://.godot/operator_visual_settings.cfg"
	preferences.ui_scale=1.5
	preferences.high_contrast=true
	host.theme=UI.create_theme(true)
	var settings := Settings.new()
	host.add_child(settings)
	settings.setup(preferences)
	settings.open()
	await capture("settings_150")
	print("OPERATOR VISUALS: charts, empty state, digital topology and 150% settings captured")
	quit()

func capture(name_: String) -> void:
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var rendered: Image = root.get_texture().get_image()
	rendered.save_png("res://.godot/operator-visual-qa/"+name_+".png")
