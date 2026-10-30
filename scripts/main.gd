extends Node3D

const UI = preload("res://scripts/ui/ui_kit.gd")
const GameHud = preload("res://scripts/ui/game_hud.gd")
const OperatorMap = preload("res://scripts/ui/operator_map.gd")
const Preferences = preload("res://scripts/ui/operator_preferences.gd")
const SettingsDesk = preload("res://scripts/ui/settings_panel.gd")
const Presenter = preload("res://scripts/ui/grid_presenter.gd")
const FacilityReadout = preload("res://scripts/ui/facility_readout.gd")
const Sim = preload("res://scripts/sim/grid_sim.gd")
const Models = preload("res://scripts/art/model_factory.gd")
const Island = preload("res://scripts/art/island_factory.gd")
const Chart = preload("res://scripts/ui/power_chart.gd")
const MarketDesk = preload("res://scripts/ui/market_panel.gd")
const DigitalDesk = preload("res://scripts/ui/digital_panel.gd")
const PlanningDesk = preload("res://scripts/ui/planning_panel.gd")
const CampaignDesk = preload("res://scripts/ui/campaign_panel.gd")
const FrontendMenu = preload("res://scripts/ui/frontend_menu.gd")
const SaveCatalog = preload("res://scripts/ui/save_catalog.gd")
const INK := Color("102c38")
const PANEL := Color("122e3bdd")
const TEAL := Color("77dbc0")
const CREAM := Color("f2eddb")
const MUTED := Color("95b0b6")
const ORANGE := Color("efbb7d")
const RED := Color("f38a79")
const GRID_SIZE := 16
const SPACING := 2.0

var hud: Control
var inspector_selection := ""
var sim: RefCounted
var camera: Camera3D
var world: Node3D
var terrain: Node3D
var terrain_size := 16
var terrain_identity := ""
var sun_light: DirectionalLight3D
var environment_state: Environment
var rain_root: Node3D
var building_root: Node3D
var cable_root: Node3D
var communication_root: Node3D
var marker_root: Node3D
var visuals: Dictionary = {}
var cable_visuals: Dictionary = {}
var selection_ring: MeshInstance3D
var ghost: Node3D
var ghost_cell := Vector2i(-100,-100)
var hover_cell := Vector2i(-100,-100)
var selected_id := -1
var selected_line := -1
var selected_comm_line := -1
var communication_kind := "fiber"
var build_category := "power"
var connection_start := -1
var tool := "select"
var build_kind := "solar"
var overlay := "normal"
var speed := 1
var previous_speed := 1
var sim_accum := 0.0
var ui_accum := 0.0
var elapsed := 0.0
var orbit := 0.0
var cam_target := Vector3.ZERO
var zoom := 47.0
var dragging := false
var drag_origin := Vector2.ZERO
var is_ready := false
var capture_mode := false
var welcome: Control
var help_modal: Control
var end_modal: Control
var root_ui: Control
var hud_values: Dictionary = {}
var inspector_box: VBoxContainer
var mission_box: VBoxContainer
var events_label: RichTextLabel
var tool_buttons: Dictionary = {}
var build_buttons: Dictionary = {}
var time_label: Label
var weather_label: Label
var hint_label: Label
var notice_label: Label
var notice_timer := 0.0
var tooltip_label: Label
var chart: Control
var topology: Control
var mode_label: Label
var sidebar_title: Label
var research_button: Button
var response_button: Button
var market_panel: Control
var market_ticker: Label
var digital_panel: Control
var planning_panel: Control
var digital_ticker: Label
var dialog_layer: Control
var refresh_inspector := true
var mission_snapshot := ""
var last_structure := ""
var last_finished := false
var autosave_clock := 0.0
var campaign_panel: Control
var campaign_save_path := "user://campaign_save.json"
var campaign_autosave_path := "user://campaign_autosave.json"
var campaign_backup_path := "user://before_campaign.json"
var preferences: RefCounted
var settings_panel: Control
var operator_map: Control
var confirmation: Control
var confirm_body: VBoxContainer
var pending_demolition := -1
var hover_line := -1
var previous_overlay := "normal"
var onboarding := false
var onboarding_skipped := false
var _last_map_size := Vector2.ZERO
var _charted_receipts: Dictionary = {}
var _charted_storm := false
enum AppState { TITLE, PLAYING, PAUSED }
var app_state: AppState = AppState.TITLE
var session_started := false
var pause_menu: Control
var audio: Node
var title_catalog: Dictionary = {}
var sandbox_save_path := "user://tidal_grid_save.json"
var sandbox_autosave_path := "user://autosave.json"
var _settings_origin := "playing"
var _focus_suspended := false
var _audio_accum := 0.0
var _audio_progress_signature := ""
var _restore_settings_on_cancel := false
var _campaign_from_live_sandbox := false
var _visual_preferences := ""
var _binding_preferences := ""

func _ready() -> void:
	preferences = Preferences.new()
	preferences.load_preferences()
	if ResourceLoader.exists("res://scripts/audio/audio_director.gd"):
		audio = load("res://scripts/audio/audio_director.gd").new()
		add_child(audio)
	sim = Sim.new()
	sim.reset(42)
	_setup_world()
	_setup_ui()
	_apply_preferences()
	_sync_world(true)
	_update_hud()
	_update_inspector()
	_update_camera()
	get_viewport().size_changed.connect(_layout_interface)
	is_ready = true
	get_tree().auto_accept_quit = false
	get_tree().node_added.connect(_wire_ui_sound)
	_wire_sound_tree(root_ui)
	_refresh_title()
	hud.hide()
	operator_map.hide()
	world.hide()
	capture_mode = "--capture" in OS.get_cmdline_user_args()
	if capture_mode:
		_activate_session()
		_capture_preview()

func _setup_world() -> void:
	world = Node3D.new()
	add_child(world)
	terrain = Island.create(16,SPACING)
	world.add_child(terrain)
	building_root = Node3D.new()
	world.add_child(building_root)
	cable_root = Node3D.new()
	world.add_child(cable_root)
	communication_root = Node3D.new()
	world.add_child(communication_root)
	marker_root = Node3D.new()
	world.add_child(marker_root)
	var env := WorldEnvironment.new()
	var atmosphere := Environment.new()
	atmosphere.background_mode = Environment.BG_COLOR
	atmosphere.background_color = Color("153d4a")
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_color = Color("c5e1df")
	atmosphere.ambient_light_energy = 0.29
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = atmosphere
	environment_state = atmosphere
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "AfternoonSun"
	sun.rotation_degrees = Vector3(-52,-35,0)
	sun.light_color = Color("ffedd5")
	sun.light_energy = 0.54
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
	sun_light = sun
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = zoom
	camera.far = 250
	camera.current = true
	add_child(camera)
	selection_ring = _tile_mesh(Color(0.48,1,0.8,0.45))
	marker_root.add_child(selection_ring)
	selection_ring.hide()
	rain_root = Node3D.new()
	world.add_child(rain_root)
	var rain_mat := StandardMaterial3D.new()
	rain_mat.albedo_color = Color(0.65,0.85,0.93,0.4)
	rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in range(64):
		var drop := MeshInstance3D.new()
		var drop_mesh := BoxMesh.new()
		drop_mesh.size = Vector3(0.018,0.75,0.018)
		drop.mesh = drop_mesh
		drop.material_override = rain_mat
		drop.position = Vector3(sin(i*13.7)*17,fmod(i*3.71,16),cos(i*7.3)*17)
		drop.rotation.z = -0.2
		rain_root.add_child(drop)
	rain_root.hide()

func _tile_mesh(color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.93,0.025,1.93)
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func _update_camera() -> void:
	camera.size = zoom
	var angle := deg_to_rad(45.0) + orbit
	camera.position = cam_target + Vector3(sin(angle)*36,32,cos(angle)*36)
	camera.look_at(cam_target)	
	if operator_map: operator_map.queue_redraw()

func focus_cell(cell: Vector2i) -> void:
	cam_target = _cell_position(cell)
	zoom = 32.0
	_update_camera()

func focus_target(kind: String, id: int) -> void:
	for panel in [market_panel,digital_panel,planning_panel,campaign_panel]:
		if panel: panel.hide()
	hud.close_popups()
	_set_tool("select")
	selected_id = -1
	selected_line = -1
	selected_comm_line = -1
	if kind in ["line","power"]:
		var line: Dictionary = sim.get_line(id)
		if line.is_empty(): _missing_target(); return
		selected_line = id
		var a: Dictionary = sim.get_building(int(line.a))
		var b: Dictionary = sim.get_building(int(line.b))
		cam_target = _cell_position(a.cell).lerp(_cell_position(b.cell),.5)
		zoom = clampf(_cell_position(a.cell).distance_to(_cell_position(b.cell))*1.6,28,72)
	elif kind in ["communication","comm","link"]:
		for link in sim.digital.links:
			if int(link.id)==id:
				selected_comm_line=id
				cam_target = _cell_position(sim.get_building(int(link.a)).cell).lerp(_cell_position(sim.get_building(int(link.b)).cell),.5)
				zoom=32
				overlay="comm"
	else:
		var building: Dictionary = sim.get_building(id)
		if building.is_empty(): _missing_target(); return
		selected_id = id
		cam_target = _cell_position(building.cell)
		zoom = 28.0
	# Place the target in the usable map area to the left of the workspace.
	cam_target += camera.global_basis.x*zoom*.12
	_update_camera()
	if not hud.operator_dock.pinned: hud.operator_dock.show_page("object")
	_sync_world(true)
	_update_inspector()
	_update_hud()

func _missing_target() -> void:
	inspector_selection=""
	_clear_children(inspector_box)
	_label(inspector_box,"目标已移除，请重新选择对象。",14,MUTED)
	hud.refresh_context()
	_notify("该目标已不存在；历史回执仍可查阅。",false)

func _focus_working_area() -> void:
	if sim.buildings.is_empty(): return
	var minimum := Vector2(10000,10000)
	var maximum := Vector2(-10000,-10000)
	for building in sim.buildings:
		var cell := Vector2(building.cell)
		minimum = minimum.min(cell)
		maximum = maximum.max(cell)
	cam_target = _cell_position(Vector2i((minimum+maximum)/2))
	zoom = clampf((maximum-minimum).length()*SPACING*1.1,30,80)
	_update_camera()

func _cell_position(cell: Vector2i) -> Vector3:
	return Vector3((cell.x-7.5)*SPACING,0,(cell.y-7.5)*SPACING)

func _mouse_ground() -> Vector3:
	return _ground_at_screen(get_viewport().get_mouse_position())

func _ground_at_screen(pos: Vector2) -> Vector3:
	var hit: Variant = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(pos),camera.project_ray_normal(pos))
	return hit if hit != null else Vector3(999,0,999)

func _mouse_cell() -> Vector2i:
	return _cell_at_screen(get_viewport().get_mouse_position())

func _cell_at_screen(screen_position: Vector2) -> Vector2i:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*200)
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		var collider: Object = result.collider
		var id := int(collider.get_meta("building_id",-1))
		var building: Dictionary = sim.get_building(id)
		if not building.is_empty():
			return building.cell
	var ground: Variant = Plane(Vector3.UP,0).intersects_ray(origin,direction)
	if ground == null:
		return Vector2i(-100,-100)
	return Vector2i(roundi(ground.x/SPACING+7.5),roundi(ground.z/SPACING+7.5))

func _building_at(cell: Vector2i) -> int:
	for b in sim.buildings:
		if b.cell == cell:
			return int(b.id)
	return -1

func _is_map_cell(cell: Vector2i) -> bool:
	return cell.x >= 1 and cell.x < sim.map_size()-1 and cell.y >= 1 and cell.y < sim.map_size()-1

func _sync_terrain() -> void:
	var map_description: Dictionary = sim.map_spec()
	var identity := str(map_description.get("id","sandbox"))+":"+str(sim.map_size())
	if terrain_identity == identity: return
	terrain_identity = identity
	terrain_size = sim.map_size()
	terrain.queue_free()
	terrain = Island.create(terrain_size,SPACING) if map_description.is_empty() else Island.create_for_map(map_description,SPACING)
	if terrain_size > 16:
		# Keep the teaching town's original cell-to-world mapping unchanged.
		terrain.position = Vector3(32,0,32)
		if map_description.is_empty():
			Models.box(terrain,Vector3(57,0.016,7.4),Vector3(17,-0.018,-41),Color("6caeaf"),"RiverCorridor")
			Models.box(terrain,Vector3(40,0.014,44),Vector3(22,-0.023,22),Color("98b992"),"EasternBasin")
			for spec in [["河流走廊 · 水电选址",Vector3(13,0.15,-43)],["东部丘陵 · 抽水蓄能选址",Vector3(20,0.15,36)]]:
				var caption := Label3D.new()
				caption.text = spec[0]
				caption.font = load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
				caption.font_size = 40
				caption.pixel_size = 0.025
				caption.outline_size = 2
				caption.position = spec[1]
				caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				caption.modulate = Color("315d58")
				terrain.add_child(caption)
		for city in sim.region.cities:
			var caption := Label3D.new()
			caption.text = "%s · %s" % [city.name,city.specialization]
			caption.font = load("res://assets/fonts/NotoSansCJKsc-Regular.otf")
			caption.font_size = 48
			caption.outline_size = 5
			caption.pixel_size = 0.025
			caption.position = Vector3((city.anchor.x-23.5)*SPACING,2.0,(city.anchor.y-23.5)*SPACING)
			caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			caption.no_depth_test = true
			caption.set_meta("city_id",int(city.id))
			terrain.add_child(caption)
	world.add_child(terrain)
	cam_target = Vector3.ZERO
	zoom = 47.0
	_update_camera()

func focus_city(id: int) -> void:
	var city: Dictionary = sim.region.city_status(id)
	if city.is_empty():
		return
	cam_target = _cell_position(city.anchor)
	zoom = 40.0
	_update_camera()
	selected_id=-1
	selected_line=-1
	selected_comm_line=-1
	if not city.building_ids.is_empty():
		selected_id = int(city.building_ids[0])
	_update_inspector()
	_sync_world(true)
	_notify("%s · %s · 人口 %.0f" % [city.name,city.specialization,city.population])

func _sync_world(force: bool=false) -> void:
	_sync_terrain()
	if sim.region.active:
		for child in terrain.get_children():
			if child.has_meta("city_id"):
				var city: Dictionary = sim.region.city_status(int(child.get_meta("city_id")))
				var phase: String=str(city.get("service_phase","active"))
				child.text = "%s · %s" % [city.name,{"prospect":"潜在市场","planned":"建设接入中","active":str(city.specialization)}.get(phase,str(city.specialization))]
	var ids: Array = []
	for b in sim.buildings:
		ids.append(b.id)
		if not visuals.has(b.id):
			var model: Node3D = Models.building(b.kind)
			model.position = _cell_position(b.cell)
			building_root.add_child(model)
			visuals[b.id] = model
			var heights := {"wind":3.5,"sensor":2.7,"home":1.45,"solar":0.8,"battery":1.5,"factory":1.8,"gas":1.85,"hospital":2.0,"substation":1.8,"intertie":2.2,"control":2.0,"relay":3.2,"soc":1.6,"nuclear":2.8,"fusion":2.5,"coal":2.8,"steam":2.5,"hydro":1.7,"cooling":2.4,"academy":1.7,"pumped_storage":1.5,"flow_battery":1.9,"hydrogen":2.2,"hvdc":2.2,"ccgt":2.2,"condenser":1.6}
			var body := StaticBody3D.new()
			body.set_meta("building_id",int(b.id))
			var collision := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			var height: float = float(model.get_meta("pick_height",heights.get(b.kind,1.5)))
			shape.size = Vector3(1.75,height,1.75)
			collision.shape = shape
			collision.position.y = height/2
			body.add_child(collision)
			model.add_child(body)
			var signpost := Label3D.new()
			signpost.name = "Status"
			signpost.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			signpost.no_depth_test = true
			signpost.font_size = 36
			signpost.font = root_ui.theme.default_font
			signpost.pixel_size = 0.012
			signpost.outline_size = 8
			signpost.modulate = CREAM
			signpost.position = model.get_meta("label_anchor",Vector3(0,3.35 if b.kind == "relay" else (3.1 if b.kind == "wind" else 1.9),0))
			model.add_child(signpost)
			var lamp := OmniLight3D.new()
			lamp.name = "EveningLight"
			lamp.light_color = Color("ffca83")
			lamp.omni_range = 3.0
			lamp.position.y = 0.9
			lamp.light_energy = 0
			model.add_child(lamp)
		var label: Label3D = visuals[b.id].get_node("Status")
		var marker: Dictionary = Presenter.facility_marker(sim,int(b.id))
		var consumer: bool = b.kind in ["home","factory","hospital"]
		label.text = "" if marker.get("color_key","")=="muted" else str(marker.get("text",""))
		label.modulate = MUTED if marker.get("color_key","")=="muted" else RED
		if overlay == "power":
			var status: Dictionary=sim.communication_status(int(b.id))
			var measurement: Dictionary = sim.facility_observation(int(b.id))
			label.text = "%.1f MW" % float(measurement.served if consumer else measurement.output) if measurement.trusted else "无遥测"
			label.modulate = ORANGE if consumer else TEAL
		elif overlay == "health":
			var status: Dictionary = sim.communication_status(int(b.id))
			var measurement: Dictionary = sim.facility_observation(int(b.id))
			label.text = "%d%%" % measurement.health if measurement.trusted else "?"
			label.modulate = TEAL if status.get("trusted",false) else Color("95b0b6")
		elif overlay == "comm":
			var status: Dictionary = sim.communication_status(int(b.id))
			label.text = "●" if status.get("trusted",false) else "?"
			label.modulate = Color("81c9ee") if status.get("trusted",false) else ORANGE
	for id in visuals.keys():
		if not ids.has(id):
			visuals[id].queue_free()
			visuals.erase(id)
	var structure := str(sim.lines)+str(sim.digital.observations)+str(selected_line)
	if force or structure != last_structure:
		for child in cable_root.get_children():
			child.queue_free()
		cable_visuals.clear()
		for line in sim.lines:
			_draw_cable(line)
		last_structure = structure
	cable_root.visible = overlay!="comm" and tool!="datalink"
	communication_root.visible = overlay=="comm" or tool=="datalink"
	if communication_root.visible:
		_draw_communications()
	if selected_id >= 0:
		var b: Dictionary = sim.get_building(selected_id)
		if not b.is_empty():
			selection_ring.position = _cell_position(b.cell) + Vector3.UP*0.035
			selection_ring.show()
		else:
			selection_ring.hide()
	else:
		selection_ring.hide()
	if topology:
		topology.queue_redraw()
	_update_lighting()

func _draw_communications() -> void:
	for child in communication_root.get_children():
		child.queue_free()
	for link in sim.digital.links:
		var a: Dictionary = sim.get_building(int(link.a))
		var b: Dictionary = sim.get_building(int(link.b))
		if a.is_empty() or b.is_empty():
			continue
		var color := Color("81c9ee")
		if link.get("fault",false):
			color=RED
		elif not link.get("online",true):
			color=Color("627784")
		if int(link.id)==selected_comm_line:
			color=CREAM
		var from:=_cell_position(a.cell)+Vector3.UP*.72
		var to:=_cell_position(b.cell)+Vector3.UP*.72
		for i in range(12):
			if link.kind=="wireless" and i%2==0:
				continue
			_cylinder_between(communication_root,from.lerp(to,i/12.0),from.lerp(to,(i+1)/12.0),.035,color)
	for child in communication_root.get_children():
		if child is MeshInstance3D and child.material_override!=null:
			child.material_override.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
			child.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _update_lighting() -> void:
	var daylight := smoothstep(-0.15,0.4,sin((float(sim.time_hours)-6.0)*PI/12.0))
	var storm: bool = sim.weather == "风暴"
	sun_light.light_energy = (0.12+daylight*0.42)*(0.70 if storm else 1.0)
	environment_state.ambient_light_energy = 0.23+daylight*0.06
	environment_state.ambient_light_color = Color("638aaf").lerp(Color("c5e1df"),daylight)
	if terrain != null:
		for title in ["Sea", "WaterSurround"]:
			var sea := terrain.get_node_or_null(title) as MeshInstance3D
			if sea != null and sea.material_override is ShaderMaterial:
				sea.material_override.set_shader_parameter("daylight", daylight)
				sea.material_override.set_shader_parameter("motion", not preferences.reduced_motion)
	rain_root.visible = storm and not preferences.reduced_motion
	for id in visuals:
		var lamp: OmniLight3D = visuals[id].get_node("EveningLight")
		var b: Dictionary = sim.get_building(int(id))
		lamp.light_energy = (1.0-daylight)*0.65 if b.get("powered",false) else 0.0

func _draw_cable(line: Dictionary) -> void:
	var a: Dictionary = sim.get_building(line.a)
	var b: Dictionary = sim.get_building(line.b)
	if a.is_empty() or b.is_empty():
		return
	var from := _cell_position(a.cell)
	var to := _cell_position(b.cell)
	var observation: Dictionary=sim.line_observation(int(line.id))
	var visibility:=str(observation.get("visibility","unknown"))
	var current: bool=visibility in ["verified","patrol"]
	var color := TEAL if current else Color("698b91")
	var fault: bool = bool(observation.get("fault",false)) and observation.get("fault_known",false) and current
	var measured: Variant=observation.get("flow")
	var signed_flow: float=float(measured) if measured!=null and current else 0.0
	var flow: float = absf(signed_flow)
	var rating: float = float(line.get("capacity",8))
	if fault:
		color = RED
	elif current and not observation.get("closed",true):
		color = Color("657c86")
	elif flow/rating > 0.85:
		color = ORANGE
	if selected_line == int(line.id):
		color = CREAM
	var container := Node3D.new()
	container.set_meta("observation_visibility",visibility)
	container.set_meta("fault_marker",fault)
	cable_root.add_child(container)
	cable_visuals[line.id] = container
	var previous := from + Vector3.UP*0.38
	for i in range(1,13):
		var t := i/12.0
		var point := from.lerp(to,t) + Vector3.UP*(0.38+sin(t*PI)*0.13)
		_cylinder_between(container,previous,point,0.04,color)
		previous = point
	# Low terminal posts leave the island architecture clearly visible.
	for p in [from,to]:
		_cylinder_between(container,p+Vector3.UP*0.02,p+Vector3.UP*0.47,0.035,Color("465e65"))
	if not preferences.reduced_motion and not fault and current and observation.get("closed",true) and flow > 0.02:
		var dot := MeshInstance3D.new()
		dot.name = "EnergyDot"
		var sphere := SphereMesh.new()
		sphere.radius = 0.065
		sphere.height = 0.13
		dot.mesh = sphere
		var dot_mat := StandardMaterial3D.new()
		dot_mat.albedo_color = CREAM
		dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dot.material_override = dot_mat
		container.set_meta("from",from if signed_flow>0 else to)
		container.set_meta("to",to if signed_flow>0 else from)
		container.add_child(dot)
	if fault:
		var flash := Label3D.new()
		flash.position = from.lerp(to,0.5)+Vector3.UP*0.7
		flash.text = "×"
		flash.font_size = 60
		flash.pixel_size = 0.016
		flash.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		flash.modulate = RED
		container.add_child(flash)

func _cylinder_between(parent: Node3D, from: Vector3, to: Vector3, radius: float, color: Color) -> void:
	var obj := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = from.distance_to(to)
	mesh.radial_segments = 6
	obj.mesh = mesh
	obj.position = (from+to)/2
	var direction := (to-from).normalized()
	if absf(direction.dot(Vector3.UP)) < 0.999:
		obj.quaternion = Quaternion(Vector3.UP,direction)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.15
	obj.material_override = mat
	parent.add_child(obj)

func _process(delta: float) -> void:
	if not is_ready:
		return
	_audio_accum += delta
	if _audio_accum >= .65:
		_audio_accum = 0.0
		_update_audio()
	if app_state == AppState.TITLE:
		return
	elapsed += delta
	if rain_root.visible:
		for drop in rain_root.get_children():
			drop.position.y -= delta*17
			drop.position.x += delta*2.3
			if drop.position.y < 0:
				drop.position.y += 16
				if drop.position.x > 18:
					drop.position.x = -18
	var move := Vector2.ZERO
	if not _modal_open():
		var text_focused: bool = get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit
		if not text_focused: move = Vector2(float(preferences.is_action_pressed("move_right"))-float(preferences.is_action_pressed("move_left")),float(preferences.is_action_pressed("move_down"))-float(preferences.is_action_pressed("move_up")))
		if move.length() > 0:
			var right := camera.global_basis.x
			var forward := Vector3(camera.global_basis.z.x,0,camera.global_basis.z.z).normalized()
			cam_target += (right*move.x+forward*move.y)*delta*10*preferences.pan_sensitivity
			cam_target.x = clampf(cam_target.x,-14,78 if sim.map_size()>16 else 14)
			cam_target.z = clampf(cam_target.z,-14,78 if sim.map_size()>16 else 14)
			_update_camera()
	var effective_speed := 0 if _modal_open() or _focus_suspended else speed
	sim_accum += delta * effective_speed
	if sim_accum >= 0.5:
		var hours := minf(sim_accum,3.0)/24.0
		sim.step(hours)
		sim_accum = 0
		_sync_world()
		_update_hud()
		refresh_inspector = true
		chart.sample(float(sim.totals.get("demand",0)),float(sim.totals.get("generation",0))+float(sim.totals.get("import_mw",0)),float(sim.elapsed_hours),float(sim.totals.get("served",0)))
	ui_accum += delta
	if ui_accum > 0.65:
		ui_accum = 0
		_update_time_status()
		_update_onboarding()
		if refresh_inspector and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_update_inspector()
			refresh_inspector = false
	for id in visuals:
		var rotor: Node3D = visuals[id].find_child("Rotor",true,false)
		if rotor and not preferences.reduced_motion:
			rotor.rotate_z(delta*1.3*maxi(1,effective_speed))
	for id in cable_visuals:
		var cable: Node3D = cable_visuals[id]
		var dot: Node3D = cable.get_node_or_null("EnergyDot")
		if dot:
			var t := fmod(elapsed*0.35+float(id)*0.17,1.0)
			var start: Vector3 = cable.get_meta("from")
			var finish: Vector3 = cable.get_meta("to")
			dot.position = start.lerp(finish,t)+Vector3.UP*(0.38+sin(t*PI)*0.13)
	if notice_timer > 0:
		notice_timer -= delta
		notice_label.visible = notice_timer > 0
	_update_hover()
	if session_started and effective_speed>0: autosave_clock += delta
	if session_started and preferences.autosave_seconds>0 and autosave_clock >= preferences.autosave_seconds:
		autosave_clock = 0
		var auto_result: Dictionary = _atomic_save(campaign_autosave_path if _campaign_active() else sandbox_autosave_path)
		if not auto_result.get("ok",false): _notify("自动保存失败，请手动保存或检查存储空间。",false)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and _guard_modal_focus(event): return
	if settings_panel != null and settings_panel.visible: return
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.keycode==KEY_F and not _modal_open():
		hud.operator_dock.open_search()
		get_viewport().set_input_as_handled()
		return
	# Reserve pause before focused HUD buttons receive the default Space accept.
	if is_ready and not _modal_open() and event is InputEventKey and preferences.matches("pause",event) and not (get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit):
		if event.pressed and not event.echo: _toggle_pause()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not is_ready:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if settings_panel.visible:
				settings_panel.close()
			elif confirmation.visible:
				_cancel_confirmation()
			elif campaign_panel.visible:
				campaign_panel.close()
			elif planning_panel.visible:
				planning_panel.close()
			elif digital_panel.visible:
				digital_panel.close()
			elif market_panel.visible:
				market_panel.close()
			elif help_modal.visible:
				help_modal.hide()
			elif welcome.visible:
				pass # Escape never starts the title-screen background session.
			elif pause_menu.visible:
				_close_pause()
			elif end_modal.visible:
				end_modal.hide()
			elif hud.close_top():
				pass
			else:
				if tool!="select" or connection_start>=0: _set_tool("select")
				else: _open_pause()
			_update_time_status()
			return
		if preferences.matches("planning",event) and planning_panel.visible:
			planning_panel.close()
			return
		if preferences.matches("market",event) and market_panel.visible:
			market_panel.close()
			return
		if preferences.matches("network",event) and digital_panel.visible:
			digital_panel.close()
			return
		if _modal_open():
			return
		var keycode: int = _canonical_key(event)
		match keycode:
			KEY_SPACE: _toggle_pause()
			KEY_1: _set_tool("select")
			KEY_2: _set_tool("line")
			KEY_3: _set_tool("repair")
			KEY_4:
				_set_tool("datalink")
				_sync_world(true)
			KEY_Q:
				orbit -= PI/8
				_update_camera()
			KEY_E:
				orbit += PI/8
				_update_camera()
			KEY_F5: _save()
			KEY_F9: _load()
			KEY_H: help_modal.show()
			KEY_M: _open_center("market")
			KEY_N: _open_center("network")
			KEY_T: _open_center("planning")
	if _modal_open():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(22,zoom-2*preferences.zoom_sensitivity)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(135 if sim.map_size()>16 else 58,zoom+2*preferences.zoom_sensitivity)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
			drag_origin = event.position
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_set_tool("select")
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_map_click(_cell_at_screen(event.position),event.position)
	if event is InputEventMouseMotion and dragging:
		var d: Vector2 = event.relative
		var right := camera.global_basis.x
		var forward := Vector3(camera.global_basis.z.x,0,camera.global_basis.z.z).normalized()
		cam_target -= (right*d.x+forward*d.y)*zoom/800*preferences.pan_sensitivity
		cam_target.x = clampf(cam_target.x,-14,78 if sim.map_size()>16 else 14)
		cam_target.z = clampf(cam_target.z,-14,78 if sim.map_size()>16 else 14)
		_update_camera()

func _modal_open() -> bool:
	return (pause_menu != null and pause_menu.visible) or (settings_panel != null and settings_panel.visible) or (confirmation != null and confirmation.visible) or (campaign_panel != null and campaign_panel.visible) or (welcome != null and welcome.visible) or (help_modal != null and help_modal.visible) or (end_modal != null and end_modal.visible) or (market_panel != null and market_panel.visible) or (digital_panel != null and digital_panel.visible) or (planning_panel != null and planning_panel.visible)

func _handle_map_click(cell: Vector2i, screen_position: Vector2=Vector2.INF) -> void:
	var click_ground: Vector3 = _mouse_ground() if not screen_position.is_finite() else _ground_at_screen(screen_position)
	var id := _building_at(cell)
	if tool == "build":
		if _is_map_cell(cell):
			var result: Dictionary = sim.build(build_kind,cell)
			_apply(result)
			if result.get("ok",false):
				if audio: audio.play_action("build",true)
				selected_id=int(result.get("id",-1))
				selected_line=-1
				selected_comm_line=-1
				_notify(str(result.message) if result.has("project_id") else "建成尚需接网 · 选择接线工具连接电源或变电站")
			_sync_world(true)
		else:
			_notify("请在岛屿内的空地上建造",false)
	elif tool in ["line","datalink"]:
		selected_line=-1
		selected_comm_line=-1
		if id < 0:
			_notify("点击两座设施的地块，建立电力连接",false)
		elif connection_start < 0:
			connection_start = id
			selected_id = id
			_notify("已选起点 · 再点击另一座设施")
		elif connection_start != id:
			var result: Dictionary=sim.connect_communication(connection_start,id,communication_kind) if tool=="datalink" else sim.connect_buildings(connection_start,id)
			_apply(result)
			if result.get("ok",false):
				connection_start = -1
				if audio: audio.play_action("connect",true)
			_sync_world(true)
	elif tool == "repair":
		if id >= 0:
			_apply(sim.repair(id))
		else:
			var line_id := _nearest_line(click_ground)
			if line_id >= 0:
				_apply(sim.repair_line(line_id))
	else:
		selected_id = id
		if audio and id>=0: audio.play_ui("select")
		selected_line = -1 if id >= 0 or overlay=="comm" else _nearest_line(click_ground)
		selected_comm_line = _nearest_communication(click_ground) if id<0 and overlay=="comm" else -1
		if not hud.operator_dock.pinned: hud.operator_dock.page="object"; hud.operator_dock._sync_visibility()
		_sync_world()
	_update_inspector()
	_update_hud()
	if connection_start >= 0 and tool in ["line","datalink"]:
		hint_label.text = "起点 %s · 选择终点 · 右键取消" % sim.get_building(connection_start).get("name","")

func _nearest_communication(point: Vector3) -> int:
	var nearest: int=-1
	var distance: float = 10.0*preferences.ui_scale
	for link in sim.digital.links:
		var a: Dictionary=sim.get_building(int(link.a))
		var b: Dictionary=sim.get_building(int(link.b))
		if a.is_empty() or b.is_empty():
			continue
		var start: Vector2 = camera.unproject_position(_cell_position(a.cell))
		var finish: Vector2 = camera.unproject_position(_cell_position(b.cell))
		var screen: Vector2 = camera.unproject_position(point)
		var d: float = Geometry2D.get_closest_point_to_segment(screen,start,finish).distance_to(screen)
		if d<distance:
			distance=d
			nearest=int(link.id)
	return nearest

func _nearest_line(point: Vector3) -> int:
	var nearest := -1
	var distance: float = 10.0*preferences.ui_scale
	for line in sim.lines:
		var a: Dictionary = sim.get_building(line.a)
		var b: Dictionary = sim.get_building(line.b)
		if a.is_empty() or b.is_empty():
			continue
		var start: Vector2 = camera.unproject_position(_cell_position(a.cell))
		var finish: Vector2 = camera.unproject_position(_cell_position(b.cell))
		var screen: Vector2 = camera.unproject_position(point)
		var d: float = Geometry2D.get_closest_point_to_segment(screen,start,finish).distance_to(screen)
		if d < distance:
			distance = d
			nearest = line.id
	return nearest

func _update_hover() -> void:
	if _modal_open() or root_ui.get_viewport().gui_get_hovered_control() != null:
		if ghost:
			ghost.hide()
		tooltip_label.hide()
		hover_line = -1
		return
	var cell := _mouse_cell()
	hover_cell = cell
	hover_line = _nearest_line(_mouse_ground()) if overlay != "comm" else -1
	if tool == "build" and _is_map_cell(cell):
		if ghost == null or ghost.get_meta("kind","") != build_kind:
			if ghost:
				ghost.queue_free()
			ghost = Node3D.new()
			ghost.set_meta("kind",build_kind)
			var highlight := _tile_mesh(Color(0.45,0.95,0.78,0.35))
			ghost.add_child(highlight)
			var model: Node3D = Models.building(build_kind)
			ghost.add_child(model)
			marker_root.add_child(ghost)
		ghost.position = _cell_position(cell)+Vector3.UP*0.055
		ghost.show()
		var preview: Dictionary = sim.preview_build(build_kind,cell)
		var highlight: MeshInstance3D = ghost.get_child(0)
		highlight.material_override.albedo_color = Color(.45,.95,.78,.4) if preview.ok else Color(.95,.35,.28,.5)
		tooltip_label.text = "%s %s · ¥%s\n%s" % ["✓ 可建" if preview.ok else "× 不可建",sim.catalog[build_kind].name,_number(float(preview.get("cost",0))),"点击建造；完成后需接网" if preview.ok else str(preview.message)]
		if preview.ok:
			tooltip_label.text+="\n基础维护约 ¥%.0f/h；燃料等费用另计" % float(preview.get("maintenance",0))
			var requirement: String=str({"nuclear":"运行需同岛冷却、人才和厂用电","fusion":"运行需两份冷却、人才和厂用电","hydro":"河流选址；运行受生态下泄约束","pumped_storage":"丘陵选址；储能仍需先充电"}.get(build_kind,""))
			if not requirement.is_empty(): tooltip_label.text+="\n"+requirement
		tooltip_label.add_theme_color_override("font_color",TEAL if preview.ok else ORANGE)
	else:
		if ghost:
			ghost.hide()
		if tool == "build":
			tooltip_label.text = "× 不可建 · 请在岛屿内部空地上放置"
			tooltip_label.add_theme_color_override("font_color",ORANGE)
			_position_tooltip()
			return
		var id := _building_at(cell)
		if id >= 0:
			var b: Dictionary = sim.get_building(id)
			tooltip_label.text = str(b.name)+"  ·  点击查看"
			if tool == "line" and connection_start >= 0 and id != connection_start:
				var preview: Dictionary = sim.preview_connection(connection_start,id)
				tooltip_label.text = ("✓ " if preview.ok else "× ")+"连接至 "+str(b.name)+" · ¥"+_number(float(preview.get("cost",0)))+"\n"+str(preview.message)
			elif tool=="datalink" and connection_start>=0 and id!=connection_start:
				var preview: Dictionary = sim.preview_connection(connection_start,id,communication_kind)
				tooltip_label.text=("✓ " if preview.ok else "× ")+"通信至 "+str(b.name)+" · ¥"+_number(float(preview.get("cost",0)))+"\n"+str(preview.message)
		else:
			tooltip_label.hide()
			return
	_position_tooltip()

func _position_tooltip() -> void:
	tooltip_label.position = get_viewport().get_mouse_position()/root_ui.scale+Vector2(18,18)
	tooltip_label.position.x = clampf(tooltip_label.position.x,8,root_ui.size.x-tooltip_label.size.x-12)
	tooltip_label.position.y = clampf(tooltip_label.position.y,8,root_ui.size.y-tooltip_label.size.y-12)
	tooltip_label.show()

func _apply(result: Variant) -> void:
	if result is Dictionary:
		if audio: audio.play_action("action",bool(result.get("ok",true)))
		_notify(str(result.get("message","操作完成")),bool(result.get("ok",true)))
	else:
		_notify("操作完成")
	refresh_inspector = true

func _set_tool(value: String) -> void:
	if value=="datalink" and not sim.feature_enabled("digital"):
		_notify("独立通信将在后续章节介绍。",false)
		return
	if value=="build" and not sim.can_build(build_kind).ok:
		_apply(sim.can_build(build_kind))
		return
	var previous_tool: String=tool
	if tool=="select" and value!="select": previous_overlay=overlay
	tool = value
	if value == "datalink": overlay = "comm"
	elif value == "line": overlay = "power"
	elif value == "build" and build_kind in ["sensor","control","relay","soc"]: overlay = "comm"
	elif value == "build": overlay = "power"
	elif value == "select" and previous_tool!="select": overlay = previous_overlay
	if value == "select" and hud != null: hud.close_tray()
	connection_start = -1
	if ghost:
		ghost.hide()
	for key in tool_buttons:
		tool_buttons[key].button_pressed = key == tool
	for key in build_buttons:
		build_buttons[key].button_pressed = tool == "build" and key == build_kind
	var text := "选择设施，查看运行状态"
	if tool == "line":
		text = "连线模式 · 依次点击两座设施 · 右键取消"
	elif tool=="datalink":
		text = "通信布线 · 依次点击两座设备 · 介质 %s · %s 管理网络" % ["光纤" if communication_kind=="fiber" else "无线",preferences.binding_label("network")]
	elif tool == "repair":
		text = "抢修模式 · 点击设施或故障线路派遣队伍"
	elif tool == "build":
		text = "%s · ¥%s · 点击空地放置 · 右键取消" % [sim.catalog[build_kind].name,_number(sim.catalog[build_kind].price)]
	hint_label.text = text
	mode_label.text = "建造规划" if tool == "build" else ("通信布线" if tool=="datalink" else ("电网布线" if tool == "line" else "运行视图"))
	if communication_root:
		communication_root.visible=overlay=="comm" or tool=="datalink"
		cable_root.visible=not communication_root.visible
	hud.refresh_context()
	if operator_map: operator_map.queue_redraw()

func _set_build_category(category: String) -> void:
	build_category = category
	hud.toggle_category(category)

func _toggle_pause() -> void:
	if speed == 0:
		speed = previous_speed
	else:
		previous_speed = speed
		speed = 0
	_update_hud()

func _campaign_active() -> bool:
	return sim != null and sim.get("campaign") != null and bool(sim.campaign.active)

func _save() -> void:
	if not session_started: return
	_apply(_atomic_save(campaign_save_path if _campaign_active() else sandbox_save_path))

func _load(path: String="") -> void:
	if path.is_empty(): path = campaign_save_path if _campaign_active() else sandbox_save_path
	if _has_unsent_drafts():
		_clear_children(confirm_body)
		_label(confirm_body,"读取存档并清空草案？",22,ORANGE)
		_paragraph(confirm_body,"当前未提交的市场、设施或安全设置将被清空。个人显示和快捷键设置会保留。",CREAM,14)
		_button(confirm_body,"取消，继续编辑",func(): confirmation.hide()).grab_focus()
		_button(confirm_body,"读取并清空草案",func(): confirmation.hide(); _load_confirmed(path))
		confirmation.show()
		_update_time_status(true)
		return
	_load_confirmed(path)

func _load_confirmed(path: String) -> void:
	var result: Dictionary = sim.load_game(path)
	_apply(result)
	if not result.get("ok",false): return
	_campaign_from_live_sandbox = false
	_rebuild_session()
	if audio: audio.play_action("load",true)
	_notify("存档已读取；上个会话的草案与关注列表已清空。")

func _rebuild_session(reset_view: bool=false) -> void:
	_activate_session()
	autosave_clock = 0.0
	for item in visuals.values(): item.queue_free()
	visuals.clear()
	chart.reset_history()
	if sim.has_method("operating_snapshot"):
		var prior_storm: Variant=null
		for row in sim.operating_snapshot().get("history",[]):
			chart.sample(float(row.demand),float(row.generation),float(row.hour),float(row.served))
			if prior_storm!=null and bool(row.get("storm",false))!=bool(prior_storm):
				chart.record_event("观测到风暴" if row.get("storm",false) else "观测到风暴结束",float(row.hour))
			prior_storm=bool(row.get("storm",false))
	_charted_receipts.clear()
	_charted_storm=bool(sim.storm_active)
	hud.operator_dock.reset_session()
	for center in [market_panel,digital_panel,planning_panel,campaign_panel]:
		if center.has_method("reset_session"): center.reset_session()
	hud.close_popups()
	hud.close_tray()
	inspector_selection = ""
	for panel in [market_panel,digital_panel,planning_panel,campaign_panel,welcome,pause_menu,help_modal,end_modal,confirmation,settings_panel]:
		if panel!=null: panel.hide()
	last_finished = false
	mission_snapshot = ""
	planning_panel._asset_signature=""
	planning_panel._city_signature=""
	planning_panel._pending_facility=""
	market_panel._ledger_signature=""
	digital_panel._asset_signature=""
	digital_panel._link_signature=""
	digital_panel._circuit_signature=""
	digital_panel._incidents_signature=""
	digital_panel._jobs_signature=""
	sim_accum = 0.0
	_audio_progress_signature = _progress_audio_signature()
	selected_id = -1
	selected_line = -1
	selected_comm_line = -1
	connection_start = -1
	if reset_view:
		speed = 1
		previous_speed = 1
		cam_target = Vector3.ZERO
		orbit = 0.0
		zoom = 47.0
	if ghost: ghost.queue_free(); ghost=null
	_set_tool("select")
	_sync_world(true)
	_update_camera()
	_update_hud()
	_update_inspector()
	if reset_view and _campaign_active(): _focus_working_area()
	if audio: audio.reset_session(_audio_baseline())

func start_campaign_chapter(id: int, discard_drafts: bool=false) -> void:
	if not discard_drafts and _offer_discard_drafts(func(): start_campaign_chapter(id,true)): return
	if id<1 or id>int(campaign_panel.profile.unlocked):
		_notify("请先完成上一章。",false)
		return
	if session_started and not _campaign_active():
		var backup: Dictionary = _atomic_save(campaign_backup_path)
		if not backup.ok: _apply(backup); return
		_campaign_from_live_sandbox = true
	elif not session_started: _campaign_from_live_sandbox = false
	var result: Dictionary = sim.start_campaign(id)
	if not result.ok: _apply(result); return
	campaign_panel.profile.last_chapter=id
	campaign_panel.save_profile()
	_rebuild_session(true)
	var saved: Dictionary = _atomic_save(campaign_save_path)
	if saved.get("ok",false): _remove_stale_auto(campaign_autosave_path)
	else: _apply(saved)
	campaign_panel.open_briefing()
	if audio: audio.play_action("chapter",true)

func restart_campaign_chapter(discard_drafts: bool=false) -> void:
	if not discard_drafts and _offer_discard_drafts(func(): restart_campaign_chapter(true)): return
	var result: Dictionary = sim.restart_campaign_chapter()
	if not result.ok: _apply(result); return
	_rebuild_session(true)
	var saved: Dictionary = _atomic_save(campaign_save_path)
	if saved.get("ok",false): _remove_stale_auto(campaign_autosave_path)
	else: _apply(saved)
	campaign_panel.open_briefing()
	if audio: audio.play_action("chapter",true)

func continue_campaign(discard_drafts: bool=false) -> void:
	if not discard_drafts and _offer_discard_drafts(func(): continue_campaign(true)): return
	var catalog: Dictionary = SaveCatalog.inspect([campaign_save_path,campaign_autosave_path],"campaign")
	if catalog.latest.is_empty(): _notify("没有可读取的战役进度；原存档已保留。",false); return
	var path: String = str(catalog.latest.path)
	if session_started and not _campaign_active():
		var backup: Dictionary = _atomic_save(campaign_backup_path)
		if not backup.get("ok",false): _apply(backup); return
		_campaign_from_live_sandbox = true
	elif not session_started: _campaign_from_live_sandbox = false
	var result: Dictionary = sim.load_game(path)
	if not result.ok: _apply(result); return
	_rebuild_session()
	if not last_finished: hud.toggle_popup("missions")

func return_to_sandbox(discard_drafts: bool=false) -> void:
	if not discard_drafts and _offer_discard_drafts(func(): return_to_sandbox(true)): return
	if _campaign_active():
		var saved: Dictionary = _atomic_save(campaign_save_path)
		if not saved.get("ok",false): _apply(saved); return
		var paths: Array = [campaign_backup_path,sandbox_save_path,sandbox_autosave_path] if _campaign_from_live_sandbox else [sandbox_save_path,sandbox_autosave_path,campaign_backup_path]
		var prior: Dictionary = SaveCatalog.inspect(paths)
		if not prior.latest.is_empty():
			var result: Dictionary=sim.load_game(str(prior.latest.path))
			if not result.ok: _apply(result); return
		else: sim.reset(42)
		_campaign_from_live_sandbox = false
		_rebuild_session()
	else:
		campaign_panel.hide()
		if app_state==AppState.TITLE: _refresh_title()

func _notify(message: String, positive: bool=true) -> void:
	notice_label.text = ("✓  " if positive else "!  ")+message
	notice_label.add_theme_color_override("font_color",TEAL if positive else ORANGE)
	notice_label.show()
	notice_timer = 5.0

func _style(color: Color, radius: int=8, border: Color=Color("36515b")) -> StyleBoxFlat:
	return UI.style(color,mini(radius,8),border)

func _panel(parent: Node, position_: Vector2, size_: Vector2, color: Color=PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = position_
	p.size = size_
	p.add_theme_stylebox_override("panel",_style(color))
	parent.add_child(p)
	return p

func _label(parent: Node, text: String, font_size: int=16, color: Color=CREAM) -> Label:
	return UI.label(parent,text,font_size,color)

func _button(parent: Node, text: String, callback: Callable, min_size: Vector2=Vector2(0,36), toggle: bool=false) -> Button:
	var button: Button=UI.button(parent,text,callback,min_size,toggle)
	if text.begins_with("应用") or text.begins_with("签订"): UI.action(button)
	elif text.begins_with("拆除设施") or text.begins_with("确认拆除"): UI.action(button,"destructive")
	return button

func _column(parent: Node, separation: int=10) -> VBoxContainer:
	return UI.column(parent,separation)

func _row(parent: Node, separation: int=10) -> HBoxContainer:
	return UI.row(parent,separation)

func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	root_ui = Control.new()
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root_ui)
	root_ui.theme = UI.create_theme()
	operator_map = OperatorMap.new()
	root_ui.add_child(operator_map)
	operator_map.setup(self)
	hud = GameHud.new()
	root_ui.add_child(hud)
	hud.setup(self)
	hud.tool_requested.connect(_set_tool)
	hud.build_requested.connect(func(kind: String):
		build_kind=kind
		_set_tool("build")
		if root_ui.size.x<1120 or root_ui.size.y<650: hud.close_tray()
	)
	hud.overlay_requested.connect(func(value: String): overlay=value; _sync_world(true); hud.refresh_context())
	hud.center_requested.connect(_open_center)
	hud.action_requested.connect(_hud_action)
	hud_values = hud.values
	tool_buttons = hud.tool_buttons
	build_buttons = hud.build_buttons
	inspector_box = hud.inspector_box
	mission_box = hud.mission_box
	events_label = hud.events_label
	research_button = hud.research_button
	response_button = hud.response_button
	time_label = hud.time_label
	weather_label = hud.weather_label
	hint_label = hud.hint_label
	mode_label = hud.mode_label
	notice_label = hud.notice_label
	tooltip_label = hud.tooltip_label
	market_ticker = hud.market_ticker
	digital_ticker = hud.digital_ticker
	chart = hud.chart
	topology = hud.topology
	chart.sim = sim
	topology.node_selected.connect(func(id: int): focus_target("building",id))
	topology.line_selected.connect(func(id: int): focus_target("line",id))
	_setup_modals()
	settings_panel = SettingsDesk.new()
	root_ui.add_child(settings_panel)
	settings_panel.setup(preferences)
	settings_panel.preferences_changed.connect(_apply_preferences)
	settings_panel.closed.connect(_settings_closed)
	settings_panel.sound_preview_requested.connect(func(cue: String):
		if audio: audio.play_ui(cue)
	)

func _prepare_center(center: Control) -> void:
	if center==market_panel:
		var storage_trading: bool = sim.feature_enabled("storage_control") and (not _campaign_active() or int(sim.campaign.chapter_id)>=15)
		market_panel.tabs.set_tab_hidden(2,not storage_trading)
		if market_panel.tabs.current_tab==2 and not storage_trading: market_panel.tabs.current_tab=0
	if center==digital_panel:
		digital_panel.tabs.set_tab_hidden(2,not sim.feature_enabled("security"))
		if digital_panel.tabs.current_tab==2 and not sim.feature_enabled("security"): digital_panel.tabs.current_tab=0
		digital_panel.remote_button.visible=sim.feature_enabled("remote")
		_set_security_buttons(digital_panel)
	for other in [market_panel,digital_panel,planning_panel,campaign_panel]:
		if other != null and other != center: other.hide()
	hud.close_popups()
	hud.close_tray()
	tooltip_label.hide()
	if ghost: ghost.hide()
	if center.has_method("inherit_selection"): center.inherit_selection(selected_id,selected_line,selected_comm_line)
	_update_time_status(true)

func _set_security_buttons(node: Node) -> void:
	if node is Button and ("隔离所选" in node.text or "解除设备隔离" in node.text or "恢复 / 修补" in node.text):
		node.visible=sim.feature_enabled("security")
	for child in node.get_children(): _set_security_buttons(child)

func _open_center(value: String) -> void:
	var feature: String = {"market":"market","network":"digital","planning":"research"}.get(value,"")
	if not feature.is_empty() and not sim.feature_enabled(feature):
		_notify("这一系统将在后续章节开放。",false)
		return
	match value:
		"market": market_panel.open()
		"network": digital_panel.open()
		"planning": planning_panel.open()

func advance_management(hours: float=1.0) -> Dictionary:
	return _advance_operating_time(hours, false)

func wait_for_next_event() -> Dictionary:
	var duration: float = sim.next_event_hours(24.0) if sim.has_method("next_event_hours") else 1.0
	return _advance_operating_time(clampf(duration, 0.001, 24.0), true)

func _advance_operating_time(hours: float, stop_on_event: bool) -> Dictionary:
	if not is_finite(hours) or hours <= 0.0:
		return {"ok":false, "message":"请选择有效的推进时间。", "advanced":0.0}
	var started: float = float(sim.elapsed_hours)
	var limit: float = minf(hours, 48.0)
	var initial_deficit: float = maxf(0, float(sim.totals.get("demand",0))-float(sim.totals.get("served",0)))
	var known_alerts: Dictionary = {}
	for alert in Presenter.alerts(sim): known_alerts[str(alert.id)] = true
	var known_receipts: String = str(sim.operation_receipts().filter(func(receipt: Dictionary): return str(receipt.get("phase","")) in ["executed","rejected"]))
	var stage: int = int(sim.management_status().get("stage",-1)) if sim.has_method("management_status") else -1
	var campaign_step: int = int(sim.campaign.step_index)
	var objective_state := str(sim.objectives.map(func(item: Dictionary): return bool(item.get("done",false))))
	var reason := "下一事件已到达" if stop_on_event else "已完成真实结算"
	var remaining: float = limit
	while remaining > 0.000001:
		if _campaign_active() and (sim.campaign.completed or sim.campaign.failed): break
		var chunk: float = minf(remaining, 0.05)
		sim.step(chunk)
		remaining -= chunk
		chart.sample(float(sim.totals.get("demand",0)),float(sim.totals.get("generation",0))+float(sim.totals.get("import_mw",0)),float(sim.elapsed_hours),float(sim.totals.get("served",0)))
		_record_observed_events()
		if not stop_on_event: continue
		var receipts: Array = sim.operation_receipts().filter(func(receipt: Dictionary): return str(receipt.get("phase","")) in ["executed","rejected"])
		if str(receipts)!=known_receipts and not receipts.is_empty():
			reason = "操作已拒绝，请查看回执" if str(receipts[-1].get("phase",""))=="rejected" else "操作已完成，请核对生效值"
			break
		var deficit: float = maxf(0,float(sim.totals.get("demand",0))-float(sim.totals.get("served",0)))
		if deficit>initial_deficit+maxf(0.1,float(sim.totals.get("demand",0))*.02):
			reason="供电缺口增大，已停止等待"
			break
		var new_alert := ""
		for alert in Presenter.alerts(sim):
			if not known_alerts.has(str(alert.id)):
				new_alert=str(alert.title)
				break
		if not new_alert.is_empty():
			reason="出现新事项："+new_alert
			break
		if (_campaign_active() and int(sim.campaign.step_index)!=campaign_step) or str(sim.objectives.map(func(item: Dictionary): return bool(item.get("done",false))))!=objective_state:
			reason="目标已更新"
			break
		if sim.has_method("management_status") and int(sim.management_status().get("stage",-1))!=stage:
			reason="经营阶段已更新"
			break
	_sync_world(true)
	_update_hud()
	_update_inspector()
	var actual: float = float(sim.elapsed_hours)-started
	var result := {"ok":true,"advanced":actual,"message":"推进 %.0f 游戏分钟 · %s" % [actual*60.0,reason]}
	_notify(str(result.message))
	return result

func _hud_action(value: String) -> void:
	match value:
		"pause": _toggle_pause()
		"speed_1", "speed_3", "speed_8": speed=int(value.trim_prefix("speed_")); previous_speed=speed; _update_hud()
		"save": _save()
		"load": _load()
		"help": help_modal.show()
		"settings": _open_settings()
		"menu": _open_pause()
		"diagnosis": hud.operator_dock.show_page("diagnosis")
		"workspace": hud.operator_dock.open_search()
		"jobs": hud.operator_dock.show_page("jobs")
		"working_area": _focus_working_area()
		"full_map": cam_target=_cell_position(Vector2i(sim.map_size()/2,sim.map_size()/2)); zoom=135 if sim.map_size()>16 else 58; _update_camera()
		"campaign": campaign_panel.open_directory()
		"research": _research()
		"response": _apply(sim.demand_response()); _update_hud()
		"storm": _storm()
		"clear_selection":
			selected_id=-1
			selected_line=-1
			selected_comm_line=-1
			_update_inspector()
			_sync_world()

func _compact(value: float) -> String:
	if absf(value) >= 1000:
		return ("%.0fk" if is_zero_approx(fmod(absf(value),1000.0)) else "%.1fk") % (value/1000)
	return "%.0f" % value

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _update_hud() -> void:
	var t: Dictionary = sim.totals
	if planning_panel != null and planning_panel.visible:
		planning_panel.refresh()
	if sim.get("digital")!=null:
		digital_ticker.text="可信通信 %.0f%%  ·  已检测事件 %d  ·  指令队列 %d" % [100*float(t.get("comm_trusted",0)),t.get("cyber_active",0),t.get("remote_pending",0)]
		if digital_panel.visible:
			digital_panel.refresh()
	if sim.get("market") != null:
		market_ticker.text = "现货 ¥%.2f  /  零售 ¥%.0f" % [sim.market.state.get("spot_price",0),sim.market.state.get("retail_price",145)]
		if market_panel.visible:
			market_panel.refresh(false)
	hud_values.cash.text = "¥ %s" % _number(sim.cash)
	hud_values.supply.text = "已供 %.1f / 需求 %.1f MW" % [t.get("served",0),t.get("demand",0)]
	var reliability: float = float(t.get("reliability",1))
	if reliability <= 1.001:
		reliability *= 100
	hud_values.reliability.text = "%.1f%%" % reliability
	hud_values.reliability.add_theme_color_override("font_color",TEAL if reliability>95 else ORANGE)
	var renewable: float = float(t.get("renewable_supply_share",0))
	if renewable <= 1.001:
		renewable *= 100
	hud_values.renewables.text = "可再生供电 %.0f%%" % renewable
	hud_values.battery.text = "储能 %.1f MWh" % t.get("battery_mwh",0)
	var balance: float = float(t.get("income",0))-float(t.get("expenses",0))
	hud_values.balance.text = ("+ " if balance>=0 else "− ")+"¥"+_number(absf(balance))+"/h"
	hud_values.balance.add_theme_color_override("font_color",TEAL if balance>=0 else RED)
	var hours: float = fmod(float(sim.time_hours),24)
	time_label.text = "第 %d 天  %02d:%02d" % [sim.day,int(hours),int(fmod(hours,1)*60)]
	var translated := {"clear":"晴朗","sunny":"晴朗","cloudy":"多云","storm":"风暴","windy":"海风"}
	weather_label.text = str(translated.get(sim.weather,sim.weather))
	research_button.text = _digital_research_caption()
	research_button.disabled = not _digital_research_available()
	for kind in build_buttons:
		build_buttons[kind].disabled = not sim.can_build(kind).ok
	response_button.disabled = sim.research_level < 2
	if _campaign_active():
		var signature := "%d:%d:%s:%s:%d" % [sim.campaign.chapter_id,sim.campaign.step_index,sim.campaign.completed,sim.campaign.failed,campaign_panel.hint_level]
		if signature!=mission_snapshot:
			_clear_children(mission_box)
			campaign_panel.populate_task(mission_box)
			mission_snapshot=signature
		campaign_panel.refresh_task_progress()
		if (sim.campaign.completed or sim.campaign.failed) and not last_finished:
			last_finished=true
			campaign_panel.record_completion()
			var report_save: Dictionary = _atomic_save(campaign_save_path)
			if not report_save.get("ok",false): _apply(report_save)
			campaign_panel.open_report(bool(sim.campaign.completed))
			if audio: audio.play_action("victory" if sim.campaign.completed else "failure",true)
	else:
		var management: Dictionary = sim.management_status() if sim.has_method("management_status") else {}
		var mission_text := str([sim.objectives,management])
		if mission_text != mission_snapshot:
			_clear_children(mission_box)
			if management.get("active",false):
				_populate_management_missions(management)
			else:
				var first_active := true
				for objective in sim.objectives:
					var done: bool = bool(objective.get("completed",objective.get("done",false)))
					var name_: String = str(objective.get("title",objective.get("name","运营目标")))
					var l := _label(mission_box,("✓  " if done else "○  ")+name_,14,TEAL if done else CREAM)
					l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					l.custom_minimum_size.x = 260
					if not done and first_active:
						first_active = false
						UI.metric(mission_box,"目标进度",float(objective.get("progress",0))*100,100,"%",TEAL)
						var desc: String = str(objective.get("description",objective.get("detail","")))
						if not desc.is_empty():
							var d := _label(mission_box,desc,14,MUTED)
							d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
							d.custom_minimum_size.x = 260
			mission_snapshot = mission_text
		var all_finished := true
		for objective in sim.objectives:
			if not bool(objective.get("done",false)):
				all_finished = false
		if all_finished and not last_finished:
			last_finished = true
			_show_result(true)
		elif sim.cash < -20000 and not last_finished:
			last_finished = true
			_show_result(false)
	var logs := ""
	for i in range(maxi(0,sim.log_entries.size()-30),sim.log_entries.size()):
		var entry: Variant = sim.log_entries[i]
		if entry is Dictionary:
			logs += "[color=#7ed9c2]•[/color] "+str(entry.get("message",entry.get("text","")))+"\n\n"
		else:
			logs += "• "+str(entry)+"\n\n"
	events_label.text = logs
	hud.refresh_context()
	_update_time_status()
	chart.sample(float(t.get("demand",0)),float(t.get("generation",0))+float(t.get("import_mw",0)),float(sim.elapsed_hours),float(t.get("served",0)))
	hud.operator_dock.refresh()
	if hud.has_method("refresh_visuals"): hud.refresh_visuals()
	_record_observed_events()
	_update_onboarding()
	if session_started:
		var progress: String = _progress_audio_signature()
		if progress!=_audio_progress_signature:
			if not _audio_progress_signature.is_empty() and audio: audio.play_action("objective",true)
			_audio_progress_signature = progress

func _record_observed_events() -> void:
	if not chart.has_method("record_event"): return
	for receipt in sim.operation_receipts():
		if str(receipt.get("phase","")) not in ["executed","rejected"]: continue
		var identity := str([receipt.get("command_id",-1),receipt.get("action",""),receipt.get("elapsed_hours",0),receipt.get("phase","")])
		if _charted_receipts.has(identity): continue
		_charted_receipts[identity]=true
		chart.record_event("操作生效" if receipt.get("phase","")=="executed" else "执行拒绝",float(receipt.get("elapsed_hours",sim.elapsed_hours)))
	if bool(sim.storm_active)!=_charted_storm:
		chart.record_event("风暴抵达" if sim.storm_active else "风暴离开",float(sim.elapsed_hours))
		_charted_storm=bool(sim.storm_active)

func _populate_management_missions(status: Dictionary) -> void:
	_paragraph(mission_box,str(status.get("title","海湾经营")),TEAL,20)
	_paragraph(mission_box,str(status.get("description","")),CREAM,14)
	for condition in status.get("conditions",[]):
		if not condition is Dictionary: continue
		var target: float=float(condition.get("target",1))
		var amount: float=float(condition.get("value",0))
		var accent: Color=TEAL if condition.get("met",false) else ORANGE
		if target<=0:
			_label(mission_box,str(condition.get("label","经营条件")),14,MUTED)
			_label(mission_box,"%+.0f %s" % [amount,condition.get("unit","")],24,accent)
			_label(mission_box,"目标：不低于 %.0f %s" % [target,condition.get("unit","")],14,MUTED)
		else:
			UI.metric(mission_box,str(condition.get("label","经营条件")),amount,target,str(condition.get("unit","")),
				accent,bool(condition.get("known",true)),"目标 ≥ %.0f %s" % [target,condition.get("unit","")])
	if float(status.get("required_hours",0))>0:
		UI.metric(mission_box,"持续达标",float(status.get("elapsed_hours",0)),float(status.required_hours),"小时",TEAL)
	if not str(status.get("interruption","")).is_empty():
		_paragraph(mission_box,"最近中断 · "+str(status.interruption),ORANGE,14)
	if float(status.get("best_hours",0))>0:
		_label(mission_box,"最佳连续 %.1f 游戏小时" % float(status.best_hours),14,MUTED)
	if status.get("first_storm_ready",false) and not status.get("first_storm_prepared",false):
		var prepare := _button(mission_box,"准备完成 · 开始风暴预警",func(): _apply(sim.prepare_first_storm()); _update_hud(),Vector2(0,42))
		UI.action(prepare)
	var actions := _row(mission_box,6)
	_button(actions,"定位当前问题",func(): hud.operator_dock.show_page("diagnosis"))
	_button(actions,"等待下一事件",wait_for_next_event)

func _number(value: float) -> String:
	var whole := roundi(value)
	var raw := str(absi(whole))
	var result := ""
	for i in range(raw.length()):
		if i > 0 and (raw.length()-i)%3 == 0:
			result += ","
		result += raw[i]
	return ("−" if whole<0 else "")+result

func _stat(parent: Node, title: String, value: String, color: Color=CREAM) -> void:
	var row := _row(parent,8)
	var title_label := _label(row,title,12,MUTED)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(row,value,13,color)

func _paragraph(parent: Node, text: String, color: Color=MUTED, font_size: int=12) -> Label:
	var l := _label(parent,text,font_size,color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 244
	return l

func _update_inspector() -> void:
	if selected_id>=0 and sim.get_building(selected_id).is_empty(): selected_id=-1
	if selected_line>=0 and sim.get_line(selected_line).is_empty(): selected_line=-1
	hud.refresh_context()
	if selected_id < 0 and selected_line < 0 and selected_comm_line < 0: return
	var selection := str([selected_id,selected_line,selected_comm_line])
	if selection != inspector_selection:
		inspector_selection = selection
		_clear_children(inspector_box)
		_populate_inspector()
		_organize_inspector()
		hud.inspector_scroll.scroll_vertical = 0
		return
	# Build a detached presentation and reconcile values in place. Existing buttons,
	# focus and scroll survive normal simulation refreshes.
	var live := inspector_box
	var draft := VBoxContainer.new()
	inspector_box = draft
	_populate_inspector()
	_organize_inspector()
	inspector_box = live
	if _ui_shape(live) == _ui_shape(draft):
		_sync_ui_values(live,draft)
	else:
		var scroll: int = hud.inspector_scroll.scroll_vertical
		_clear_children(live)
		for child in draft.get_children(): draft.remove_child(child); live.add_child(child)
		hud.inspector_scroll.set_deferred("scroll_vertical",scroll)
	draft.free()

func _ui_shape(node: Node) -> String:
	var result := node.get_class()
	for child in node.get_children(): result += "("+_ui_shape(child)+")"
	return result

func _sync_ui_values(live: Node, draft: Node) -> void:
	if live.has_method("sync_from"):
		live.sync_from(draft)
		return
	if live.get_meta("facility_editor", false):
		live.refresh()
		return
	if live is Label:
		live.text = draft.text
		live.add_theme_color_override("font_color",draft.get_theme_color("font_color"))
	elif live is Button:
		live.text = draft.text
		live.disabled = draft.disabled
		live.tooltip_text = draft.tooltip_text
	for i in live.get_child_count(): _sync_ui_values(live.get_child(i),draft.get_child(i))

func _organize_inspector() -> void:
	var advanced: Array[Node] = []
	var demolition: Node
	var dispatch_next := false
	for child in inspector_box.get_children():
		if child.get_meta("inspector_advanced",false):
			advanced.append(child)
			continue
		if child is Button:
			if "拆除" in child.text: demolition=child; continue
			if "运行边界" in child.text or "策略" in child.text or "运行中心" in child.text or "交易中心" in child.text: advanced.append(child)
		elif child is Label and "燃气出力上限" in child.text:
			advanced.append(child)
			dispatch_next = true
		elif dispatch_next:
			advanced.append(child)
			dispatch_next = false
	if not advanced.is_empty():
		var toggle := _button(inspector_box,"高级控制  ▾",func(): hud.advanced_open=not hud.advanced_open; _set_advanced_visible(),Vector2(0,34),true)
		toggle.button_pressed = hud.advanced_open
		var box := _column(inspector_box,8)
		box.name = "AdvancedControls"
		box.visible = hud.advanced_open
		for child in advanced: inspector_box.remove_child(child); box.add_child(child)
	if demolition:
		inspector_box.move_child(demolition,inspector_box.get_child_count()-1)
		demolition.add_theme_color_override("font_color",RED)

func _set_advanced_visible() -> void:
	var box := inspector_box.get_node_or_null("AdvancedControls")
	if box: box.visible = hud.advanced_open

func _populate_inspector() -> void:
	inspector_box.add_theme_constant_override("separation",8)
	if selected_comm_line >= 0: _inspect_communication(); return
	if selected_line >= 0: _inspect_line(); return
	var b: Dictionary = sim.get_building(selected_id) if selected_id >= 0 else {}
	if b.is_empty(): return
	_label(inspector_box,"设施档案  /  ASSET %02d" % int(b.id),11,TEAL)
	_label(inspector_box,str(b.name),23)
	_append_lens_explanation(inspector_box,"facility",int(b.id))
	var observation: Dictionary = sim.facility_observation(int(b.id))
	var customer: bool=b.kind in ["home","factory","hospital"]
	var service_active: bool=not customer or not sim.has_method("customer_service_active") or sim.customer_service_active(int(b.id))
	var status: String = str(observation.status) if observation.trusted else "运行状态待核实"
	if not service_active:
		var city: Dictionary=sim.region.city_status(int(b.get("city_id",-1)))
		status="潜在市场 · 尚未开通服务" if city.get("service_phase","prospect")=="prospect" else "接入建设中 · 尚未开通服务"
	elif float(b.get("repair_remaining",0)) > 0:
		status = "抢修中 · %.1f 小时" % b.repair_remaining
	elif observation.trusted and float(observation.get("health",100)) <= 0:
		status = "设备故障 · 等待维修"
	elif customer and not b.get("powered",false):
		status = "供电中断 · 请检查连接"
	_paragraph(inspector_box,"●  "+status,TEAL if observation.trusted else ORANGE,14)
	_stat(inspector_box,"设备等级","L%d" % b.get("level",1))
	var comm: Dictionary=sim.communication_status(int(b.id))
	_stat(inspector_box,"设备遥测","可信" if observation.trusted else "未确认 / 过时",TEAL if observation.trusted else ORANGE)
	_stat(inspector_box,"资产状况","%.0f%%" % observation.health if observation.trusted else "需遥测或现场检查")
	var generator: bool = b.kind in ["gas","solar","wind","hydro","dc_dynamo"] or sim.evolution.is_generator(str(b.kind))
	var measurable: bool = (customer and service_active) or generator or sim.evolution.is_storage(str(b.kind))
	if measurable:
		var readout := FacilityReadout.new()
		var snapshot: Dictionary = observation.duplicate(true)
		snapshot.merge({"capacity":float(b.get("capacity",0)), "energy_capacity":float(b.get("energy_capacity",0)),
			"generator":generator, "storage":sim.evolution.is_storage(str(b.kind))}, true)
		if snapshot.storage and sim.has_method("storage_status"):
			var storage: Dictionary=sim.storage_status(int(b.id))
			snapshot.duration_hours=storage.get("duration_hours")
			snapshot.reserve_soc=storage.get("reserve_soc",0.0)
		readout.set_snapshot(snapshot)
		inspector_box.add_child(readout)
		if not observation.trusted: _label(inspector_box,"遥测未确认 · 斜纹表示未知读数",14,MUTED)
		if b.kind in ["home","factory","hospital"] and not observation.trusted:
			_label(inspector_box,"用户有供电反馈" if b.get("powered",false) else "用户报告停电",14,TEAL if b.get("powered",false) else ORANGE)
	if customer and not service_active:
		_label(inspector_box,"开通服务后才计入供电、收入和失供责任。",14,MUTED).autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		_button(inspector_box,"规划与开通城市服务",func(): _open_center("planning"); planning_panel.tabs.current_tab=2; planning_panel.selected_city=int(b.get("city_id",-1)); planning_panel.refresh(),Vector2(0,38))
	if b.kind in ["sensor","control","relay","soc"] and sim.feature_enabled("digital"):
		_button(inspector_box,"⌁ 打开数字电网运行中心",func(): _open_center("network"); digital_panel._select_device(int(b.id)),Vector2(0,34))
		_button(inspector_box,"⌁ 从这里铺设通信链路",func(): _set_tool("datalink"); connection_start=int(b.id); _sync_world(true),Vector2(0,34))
	if sim.evolution.is_storage(str(b.kind)):
		if sim.feature_enabled("market"): _button(inspector_box,"⇄ 储能策略与电价",func(): _open_center("market"); market_panel.tabs.current_tab=2,Vector2(0,32))
	if sim.evolution.is_terminal(str(b.kind)):
		_stat(inspector_box,"净交换功率","%+.2f MW" % observation.output if observation.trusted else "遥测未确认",TEAL)
		if sim.feature_enabled("market"): _button(inspector_box,"⇄ 打开电力交易中心",func(): _open_center("market"),Vector2(0,32))
	if sim.feature_enabled("research"): _button(inspector_box,"运行边界与精细控制  "+preferences.binding_label("planning"),func(): _open_center("planning"); planning_panel.select_facility(int(b.id)),Vector2(0,32))
	if planning_panel.has_method("create_facility_editor") and (b.kind=="gas" or sim.evolution.is_generator(str(b.kind)) or sim.evolution.is_storage(str(b.kind))):
		planning_panel.create_facility_editor(inspector_box,int(b.id))
	var data: Dictionary = sim.catalog.get(b.kind,{})
	_paragraph(inspector_box,str(data.get("description","")),MUTED,11)
	var id: int = b.id
	if b.kind == "gas":
		var control_group := _column(inspector_box,6)
		control_group.set_meta("inspector_advanced",true)
		_label(control_group,"燃气出力上限 · 远程需可信遥测",14,ORANGE)
		for method in ["remote","field"]:
			if method=="remote" and not sim.feature_enabled("remote"): continue
			var dispatch := _row(control_group,6)
			for setting in [0.0,0.5,1.0]:
				var ratio: float = setting
				var route: String = method
				var caption := ("远程" if route=="remote" else "现场")+"%d%%" % int(ratio*100)
				var button := _button(dispatch,caption,func(): _apply(sim.set_dispatch(id,ratio,route)); _update_inspector(),Vector2(90,34))
				button.disabled = route=="remote" and not sim.digital.can_configure(sim,id)
				button.tooltip_text = "远程命令到达后验证执行" if route=="remote" else "派现场设置队，¥350，约21游戏分钟后执行"
	var actions := _row(inspector_box,8)
	var upgrade_button := _button(actions,"↑ 升级 ¥"+_compact(float(data.get("price",0))*0.65*float(b.get("level",1))),func(): _apply(sim.upgrade(id)); _sync_world(true); _update_hud(); _update_inspector(),Vector2(113,34))
	upgrade_button.disabled = not sim.evolution.upgrade_supported(str(b.kind)) or int(b.level)>=3
	upgrade_button.tooltip_text = sim.evolution.upgrade_effect(str(b.kind)) if sim.evolution.upgrade_supported(str(b.kind)) else "此设施暂无能力升级；可维护设备或增容相连线路"
	_button(actions,"＋ 维护 ¥1.2k",func(): _apply(sim.repair(id)); _update_inspector(),Vector2(113,34))
	_button(inspector_box,"⌁  从这里连接线路",func(): _set_tool("line"); connection_start=id; _notify("再点击目标设施，完成接线"),Vector2(0,34))
	_button(inspector_box,"☆ 固定关注此设施",func(): hud.operator_dock.watch(id); _notify("已更新关注列表；Ctrl+F 查看"),Vector2(0,34))
	if sim.feature_enabled("research") and not _campaign_active():
		_button(inspector_box,"比较此设施的运行或退出影响",func(): _preview_object("facility",id),Vector2(0,36))
		if sim.lifecycle.enabled: _button(inspector_box,"比较继续运行、检修与更换",func(): _preview_object("facility",id,true),Vector2(0,36))
	_append_object_jobs(inspector_box,"facility",id)
	_button(inspector_box,"拆除设施 · 回收 ¥%s" % _number(float(b.get("refund_basis",data.get("price",0)))*0.35),func(): _request_demolition(id),Vector2(0,30))

func _inspect_line() -> void:
	var line: Dictionary=sim.get_line(selected_line)
	if line.is_empty():
		selected_line=-1
		return
	var observation: Dictionary=sim.line_observation(selected_line)
	var visibility:=str(observation.get("visibility","unknown"))
	var trusted: bool=visibility in ["verified","patrol"]
	var names: Dictionary={"unknown":"未观测 · 等待查线","stale":"缓存已过时","verified":"可信馈线遥测","suspect":"读数可疑 · 控制受限","patrol":"现场巡检核实"}
	_label(inspector_box,"线路档案 / FEEDER %02d" % int(line.id),11,TEAL)
	_label(inspector_box,"配电线路",23)
	_append_lens_explanation(inspector_box,"line",int(line.id))
	_paragraph(inspector_box,"%s → %s" % [sim.get_building(line.a).get("name",""),sim.get_building(line.b).get("name","")])
	_label(inspector_box,"● "+str(names.get(visibility,visibility)),12,TEAL if trusted else ORANGE)
	if trusted and observation.get("fault_known",false):
		_label(inspector_box,"故障已定位" if observation.get("fault",false) else ("开关合闸" if observation.get("closed",false) else "开关断开"),13,RED if observation.get("fault",false) else TEAL)
	var flow: Variant=observation.get("flow")
	_stat(inspector_box,"实时潮流","%.2f MW" % absf(float(flow)) if flow!=null and trusted else "不可用")
	_stat(inspector_box,"设计容量","%.1f MW" % line.capacity)
	_stat(inspector_box,"记录年龄","%.2f 小时" % observation.get("age_hours",0))
	var health: Variant=observation.get("health")
	if health!=null and trusted:
		_stat(inspector_box,"线路健康","%.0f%%" % float(health))
	_paragraph(inspector_box,str(observation.get("reason","通信与现场观测决定你能知道什么。")),MUTED,11)
	var id: int=line.id
	if sim.feature_enabled("remote"): _button(inspector_box,"远程开关 · 发送指令",func(): _apply(sim.remote_switch(id)); _sync_world(true); _update_inspector(),Vector2(0,34))
	_button(inspector_box,"现场开关 · ¥350",func(): _apply(sim.field_switch(id)); _update_inspector(),Vector2(0,34))
	_button(inspector_box,"巡检定位 · ¥500",func(): _apply(sim.patrol_line(id)); _update_inspector(),Vector2(0,34))
	_button(inspector_box,"＋ 派遣线路抢修队",func(): _apply(sim.repair_line(id)); _update_inspector(),Vector2(0,34))
	_button(inspector_box,"↑ 线路增容 · ¥%s" % _compact(4500.0*float(line.get("level",1))),func(): _apply(sim.upgrade_line(id)); _sync_world(true); _update_hud(); _update_inspector(),Vector2(0,34))
	if sim.feature_enabled("research") and not _campaign_active():
		_button(inspector_box,"比较退出此线后的供电与成本",func(): _preview_object("line",id),Vector2(0,36))
		if sim.lifecycle.enabled: _button(inspector_box,"比较继续运行、检修与更换",func(): _preview_object("line",id,true),Vector2(0,36))
	_append_object_jobs(inspector_box,"line",id)

func _append_lens_explanation(parent: Node,kind: String,id: int) -> void:
	var data: Dictionary=hud.lens_snapshot
	var explained:=false
	for risk in data.get("risks",[]):
		if str(risk.get("target_type",""))!=kind or int(risk.get("target_id",-1))!=id: continue
		var card:=UI.card(parent,Color("50686b"),8)
		_paragraph(card,str(GameHud.LENSES.get(hud.lens,"运行"))+"视角 · "+str(risk.get("consequence","")),ORANGE,14)
		if preferences.information_depth!="beginner": _paragraph(card,"原因与证据："+str(risk.get("detail",""))+"\n来源："+str(risk.get("source","")),MUTED,14)
		explained=true
		break
	if not explained and hud.lens!="operations":
		var interpretation:=""
		match hud.lens:
			"assets":
				for asset in data.get("assets",[]):
					if str(asset.target_type)==kind and int(asset.target_id)==id:
						interpretation=str(asset.criticality_label)+" · "+str(asset.criticality_detail)
						break
			"customers":
				var feedback: Dictionary=Presenter.customer_feedback(sim,id) if kind=="facility" else {}
				interpretation=str(feedback.get("text","客户影响须结合街区反馈核实；连接关系不等于实际停电范围。"))
			"digital":
				var status: Dictionary=sim.communication_status(id) if kind=="facility" else {}
				interpretation="可信通信路径已建立；执行前仍需新鲜观测和权限。" if status.get("trusted",false) else "? 控制条件尚未核实；检查通信路径、读数新鲜度与权限。"
			"market": interpretation="现货 ¥%.0f/MWh · 改变交换功率也会改变线路负载；收益需结合实际交付与结算。" % float(sim.totals.get("market_price",0))
			"planning": interpretation="比较同一24小时的供电、成本和备用，检查本对象退出或运行调整的后果。"
			"maintenance": interpretation="现场队 %d/2 · 备件 %d；先核实状态，再比较短时停运与后续恢复。" % [sim.active_repairs(),sim.lifecycle.spares]
		if not interpretation.is_empty(): _paragraph(parent,str(GameHud.LENSES[hud.lens])+"视角 · "+interpretation,MUTED,14)
	if preferences.information_depth=="engineer":
		var observed: Dictionary=sim.facility_observation(id) if kind=="facility" else sim.line_observation(id)
		_paragraph(parent,"观测年龄 %.2f h · %s" % [float(observed.get("age_hours",0)),str(observed.get("reason","待核实"))],MUTED,14)

func _preview_object(kind: String,id: int,maintenance: bool=false) -> void:
	_open_center("planning")
	if not planning_panel.visible or planning_panel.tabs.is_tab_hidden(3): return
	planning_panel.tabs.current_tab=3
	var bench: Node=planning_panel.decision_workbench
	if maintenance and bench.has_method("preview_maintenance_target"): bench.preview_maintenance_target(kind,id)
	else: bench.preview_target(kind,id)

func _inspect_communication() -> void:
	var link: Dictionary={}
	for item in sim.digital.links:
		if int(item.id)==selected_comm_line:
			link=item
	if link.is_empty():
		selected_comm_line=-1
		return
	_label(inspector_box,"通信档案 / LINK %02d" % int(link.id),11,Color("81c9ee"))
	_label(inspector_box,"光纤链路" if link.kind=="fiber" else "无线链路",23)
	_stat(inspector_box,"状态","链路故障" if link.get("fault",false) else ("已开通" if link.get("online",true) else "已停用"))
	_stat(inspector_box,"链路时延","%.0f ms" % link.get("latency_ms",0))
	_stat(inspector_box,"设备健康","%.0f%%" % link.get("health",100))
	var id: int=link.id
	_button(inspector_box,"开通 / 停用通信链路",func(): _apply(sim.toggle_communication(id)); _sync_world(true); _update_inspector(),Vector2(0,34))
	_button(inspector_box,"修复通信链路 · ¥650",func(): _apply(sim.repair_communication(id)); _sync_world(true); _update_inspector(),Vector2(0,34))
	_button(inspector_box,"升级通信链路 · ¥2k",func(): _apply(sim.upgrade_communication(id)); _sync_world(true); _update_inspector(),Vector2(0,34))
	_button(inspector_box,"⌁ 数字电网运行中心",func(): _open_center("network"); digital_panel.selected_link=id; digital_panel.tabs.current_tab=1; digital_panel.refresh(true),Vector2(0,34))

func _digital_research_caption() -> String:
	if _campaign_active() and int(sim.campaign.chapter_id)==11 and int(sim.research_level)>=1: return "✓ 一级遥测已完成"
	if _campaign_active() and int(sim.campaign.chapter_id)==12 and int(sim.research_level)==1: return "↗ 设施远控研究 · ¥32k"
	return ["↗ 遥测研究 · ¥16k","↗ 自愈研究 · ¥32k","✓ 数字化研究完成"][mini(2,int(sim.research_level))]

func _digital_research_available() -> bool:
	if _campaign_active() and int(sim.campaign.chapter_id)==11 and int(sim.research_level)>=1: return false
	return sim.feature_enabled("digital") and int(sim.research_level)<2 and (not sim.evolution.heritage or sim.evolution.has_technology("scada"))

func _research() -> void:
	var result: Dictionary = sim.research()
	_apply(result)
	if audio and result.get("ok",false): audio.play_action("research",true)
	_update_hud()
	_update_inspector()

func _storm() -> void:
	var result: Dictionary = sim.trigger_storm()
	_apply(result)
	_sync_world(true)
	_update_hud()
	_update_inspector()

func _modal(parent: Node, width: float=780, height: float=600) -> Control:
	var shade := ColorRect.new()
	shade.color = Color(.025,.065,.08,.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(shade)
	var panel := PanelContainer.new()
	panel.name = "Dialog"
	panel.set_meta("preferred_size",Vector2(width,height))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -width/2
	panel.offset_right = width/2
	panel.offset_top = -height/2
	panel.offset_bottom = height/2
	panel.add_theme_stylebox_override("panel",UI.style(UI.SURFACE,10,Color("46616a"),20,true))
	shade.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.name="ContentScroll"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.name="Content"
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return shade

func _setup_modals() -> void:
	dialog_layer = Control.new()
	dialog_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.add_child(dialog_layer)
	welcome = FrontendMenu.new()
	welcome.name = "TitleMenu"
	dialog_layer.add_child(welcome)
	welcome.setup()
	welcome.action_requested.connect(_frontend_action)
	pause_menu = FrontendMenu.new()
	pause_menu.name = "PauseMenu"
	dialog_layer.add_child(pause_menu)
	pause_menu.setup()
	pause_menu.action_requested.connect(_frontend_action)
	pause_menu.hide()
	help_modal = _modal(dialog_layer,1040,620)
	var h := _column(help_modal.get_node("Dialog/ContentScroll/Content"),14)
	var head := _row(h)
	_label(head,"调度员手册",26)
	UI.spacer(head)
	_button(head,"返回海湾  Esc",func(): help_modal.hide())
	var area := _row(h,24)
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var topics := _column(area,6)
	topics.custom_minimum_size.x = 172
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.add_child(scroll)
	var content := _column(scroll,16)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label(content,"",23,TEAL)
	var prose := _paragraph(content,"",CREAM,16)
	prose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var manual := [
		["建设与接线","点击底部建造，在托盘选择发电、输电、储能、城市或数字分类。选择设施后点击空地放置；接线工具依次点击两座设施。所有电力设施都需要电气连接。\n\n右键取消工具，Esc 优先关闭浮层。地图当前重点卡可直接进入接线或检查；电力线与通信线分别建设。"],
		["调度与储能","光伏随太阳变化，风机随天气变化。燃气提供可调备用，储能在运行条件允许时吸收富余并支援缺口。MW 表示功率，MWh 表示能量；比较页用共同尺度显示功率、标称时长与损耗。\n\n选中设施可以直接编辑运行方案。保供、削峰和套利共用一个有效备用电量，单台可覆盖或恢复继承全网。提交后查看队列与真实回执；储能条图只画已观测电量和功率。"],
		["故障与恢复","图层入口提供景观、功率、健康和通信视图。可靠观测或现场巡检决定你能看到哪些故障，未知读数不能作为确定信息。\n\n点击线路可以巡检定位、派现场开关队或抢修；远程控制需要可信路径。备用供电路径可以分散潮流，提高韧性。"],
		["委托与运营","开始运营按接网、昼夜、清洁盈利、风暴恢复、新城服务五阶段推进。点击当前任务查看条件、持续时间和最近中断；首次风暴在确认准备完成后预警一小时。自由沙盘保留原四委托与自然风暴时刻。\n\n顶部常驻供电比例和缺口。经营工作台可推进15分钟、1小时或等待下一事件；等待遇执行拒绝、供电恶化或新告警时停止。失供按每MWh ¥60补偿。"],
		["电价与交易","按 M 进入市场，配置购售电、零售电价、储能策略和12小时锁价合约。建造市场联络站并接线后才可以交付电力；合约用不完仍需付费。\n\n配置修改后点击应用；刷新、切页和报价不会结算。推进1小时可以观察真实账单。"],
		["数字电网","按 N 管理独立通信网，按4进入地图通信布线。通信线与电力线分别建设。可信遥测帮助定位故障；失联时可先巡检或派现场队。\n\n安全页面选择明确的演练目标，事件页查看已检测事件与作业回执。隔离和修补需要时间；推进15分钟观察恢复。"],
		["科技与区域","按 T 进入发展规划，科技节点与依赖线显示能力、前置、费用和时间；数字化研究也可从同一工作台进入。研发和设备投运分别满足，研究不会替代真实配套。\n\n区域页先发现潜在市场，再规划接入、建设线路并明确开通服务。未开通城市不产生收入、失供补偿或人口衰退；开通后承担真实供电责任。历史开局与恢复位于场景选项。"],
		["快捷键与存档","WASD／鼠标中键：平移\n滚轮：缩放　Q／E：旋转\n1：选择　2：接线　3：抢修　4：通信\n空格：暂停／继续　M／N／T：经营中心\nH：手册　F5：保存　F9：读取\n\n右上菜单也提供存读档入口。每90秒写入独立自动存档；经营中心暂停自动时间，返回后继续原有倍率。"]
	]
	var topic_buttons: Array[Button] = []
	for i in manual.size():
		var index: int = i
		var button := _button(topics,manual[i][0],func():
			title.text=manual[index][0]
			prose.text=_keyboard_guide() if index==manual.size()-1 else manual[index][1]
			scroll.scroll_vertical=0
			for j in topic_buttons.size(): topic_buttons[j].button_pressed=j==index
		,Vector2(0,38),true)
		topic_buttons.append(button)
	topic_buttons[0].pressed.emit()
	help_modal.hide()
	end_modal = _modal(dialog_layer,760,560)
	end_modal.hide()
	market_panel = MarketDesk.new()
	dialog_layer.add_child(market_panel)
	market_panel.setup(self)
	digital_panel = DigitalDesk.new()
	dialog_layer.add_child(digital_panel)
	digital_panel.setup(self)
	planning_panel = PlanningDesk.new()
	dialog_layer.add_child(planning_panel)
	planning_panel.setup(self)
	campaign_panel = CampaignDesk.new()
	dialog_layer.add_child(campaign_panel)
	campaign_panel.setup(self)
	confirmation=_modal(dialog_layer,560,360)
	confirm_body=_column(confirmation.get_node("Dialog/ContentScroll/Content"),12)
	confirmation.hide()

func _show_result(victory: bool) -> void:
	if audio: audio.play_action("victory" if victory else "failure",true)
	if _campaign_active(): campaign_panel.open_report(victory); return
	var panel := end_modal.get_node("Dialog/ContentScroll/Content")
	_clear_children(panel)
	var v := _column(panel,18)
	_label(v,"青屿湾示范区  /  运营报告",14,MUTED)
	_label(v,"运营委托完成" if victory else "运营资金告急",26,TEAL if victory else RED)
	var managed: bool=sim.has_method("management_status") and sim.management_status().get("active",false)
	var success_text := "你已完成接网、昼夜经营、清洁盈利、风暴恢复与新城服务。继续拓展城市，选择长期运营目标。" if managed else "建设、清洁转型、数字化与风暴恢复委托已完成。继续研究、扩张城市，或选择长期运营目标。"
	_paragraph(v,success_text if victory else "累计亏损已经超过应急额度。可以继续调整电网与成本，也可以重新接手海湾。",CREAM,14)
	_stat(v,"当前资金","¥ "+_number(sim.cash))
	_stat(v,"电网规模","%d 设施 · %d 线路" % [sim.buildings.size(),sim.lines.size()])
	var reliability: float=float(sim.total_served_mwh)/maxf(.001,float(sim.total_demand_mwh)) if sim.total_demand_mwh>0 else 1.0
	UI.metric(v,"累计供电率",reliability*100,100,"%",TEAL)
	var net := 0.0
	for row in sim.market.ledger: net+=float(row.get("net",0))
	_label(v,"累计运营净收益  %s¥%s" % ["+" if net>=0 else "−",_number(absf(net))],22,TEAL if net>=0 else RED)
	if sim.has_method("operating_snapshot"):
		var snapshots: Array=sim.operating_snapshot().get("history",[])
		if snapshots.size()>1:
			var trend := Chart.new()
			trend.custom_minimum_size=Vector2(0,120)
			v.add_child(trend)
			for row in snapshots: trend.sample(float(row.demand),float(row.generation),float(row.hour),float(row.served))
	UI.spacer(v).size_flags_vertical = Control.SIZE_EXPAND_FILL
	var actions := _row(v,12)
	var continue_button := _button(actions,"继续运营",func(): end_modal.hide(),Vector2(0,44))
	continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	continue_button.add_theme_stylebox_override("normal",UI.style(Color("28584f"),6,TEAL,10))
	var restart := _button(actions,"重新开始",_new_game,Vector2(0,44))
	restart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_modal.show()

func start_heritage_game(backup_path: String="user://before_heritage.json") -> void:
	var backup: Dictionary = sim.save_game(backup_path)
	if not backup.ok:
		_apply(backup)
		return
	_new_game(true)
	_notify("已备份旧进度。历史开局从短距离直流供电开始，按 T 查看研究路线。")

func _begin_management(discard_drafts: bool=false) -> void:
	if not discard_drafts and _offer_discard_drafts(func(): _begin_management(true)): return
	if sim.has_method("start_management_game"): sim.start_management_game(42)
	else: sim.reset(42)
	_rebuild_session(true)
	onboarding=true
	onboarding_skipped=false
	_focus_working_area()
	_update_hud()
	_notify("先点亮工业园。经营系统随你的建设逐步开放。")

func _begin_free_sandbox(discard_drafts: bool=false) -> void:
	if not discard_drafts and _offer_discard_drafts(func(): _begin_free_sandbox(true)): return
	sim.reset(42)
	_rebuild_session(true)
	onboarding=false
	onboarding_skipped=true
	_focus_working_area()
	_notify("自由沙盘已开启，全部经营工具可用。")

func _new_game(heritage: bool=false,discard_drafts: bool=false) -> void:
	if not discard_drafts and _offer_discard_drafts(func(): _new_game(heritage,true)): return
	var management: bool = sim.has_method("management_status") and sim.management_status().get("active",false)
	if heritage:
		sim.start_heritage()
	elif management:
		sim.start_management_game(42)
	else:
		sim.reset(42)
	_rebuild_session(true)

func _capture_preview() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://docs/screenshots")
	screenshot.save_png("res://docs/screenshots/gameplay.png")
	print("CAPTURE_SAVED: res://docs/screenshots/gameplay.png")
	if "--capture-quit" in OS.get_cmdline_user_args():
		get_tree().quit()

func _canonical_key(event: InputEventKey) -> int:
	for action in preferences.DEFAULT_BINDINGS:
		if preferences.matches(action,event): return int(preferences.DEFAULT_BINDINGS[action])
	return 0

func _keyboard_guide() -> String:
	var lines: Array[String]=["鼠标中键：平移　滚轮：缩放","Ctrl+F：设施与城市检索　Esc：取消 / 返回"]
	for action in preferences.DEFAULT_BINDINGS:
		lines.append(preferences.binding_label(action)+"："+str(preferences.ACTION_NAMES[action]))
	lines.append("\n右上菜单也提供存读档与设置。每90秒写入独立自动存档；经营中心暂停自动时间，返回后继续原有倍率。")
	return "\n".join(lines)

func _update_time_status(planning: bool=false) -> void:
	if hud == null or hud.time_status == null: return
	if planning or _modal_open():
		hud.time_status.text = "规划暂停 · 返回 %d×" % speed if speed>0 else "规划暂停 · 返回仍暂停"
	elif speed==0: hud.time_status.text="手动暂停"
	else: hud.time_status.text="运行 %d×" % speed

func _apply_preferences() -> void:
	if root_ui==null: return
	preferences.apply_runtime(get_viewport())
	if audio: audio.apply_preferences(preferences)
	var visual: String = str([preferences.ui_scale,preferences.high_contrast,preferences.reduced_motion,preferences.information_depth])
	var bindings: String = str(preferences.bindings)
	if visual==_visual_preferences:
		if bindings!=_binding_preferences and is_ready: _update_hud()
		_binding_preferences = bindings
		return
	_visual_preferences = visual
	_binding_preferences = bindings
	root_ui.theme=UI.create_theme(preferences.high_contrast)
	_layout_interface()
	if is_ready:
		_sync_world(true)
		_update_hud()

func _layout_interface() -> void:
	if root_ui==null: return
	var ratio: float=preferences.ui_scale
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	root_ui.scale=Vector2(ratio,ratio)
	root_ui.size=get_viewport().get_visible_rect().size/ratio
	_last_map_size=root_ui.size
	if hud: hud.layout_workspace()
	for modal in [welcome,help_modal,end_modal,confirmation]:
		if modal==null or not modal.has_node("Dialog"): continue
		var dialog: Control=modal.get_node("Dialog")
		var preferred: Vector2=dialog.get_meta("preferred_size",Vector2(650,500))
		var extent: Vector2=preferred.min(root_ui.size-Vector2(32,32))
		dialog.offset_left=-extent.x/2
		dialog.offset_right=extent.x/2
		dialog.offset_top=-extent.y/2
		dialog.offset_bottom=extent.y/2
	if operator_map: operator_map.queue_redraw()

func _request_demolition(id: int) -> void:
	var preview: Dictionary=sim.preview_demolition(id)
	if not preview.get("ok",false): _apply(preview); return
	pending_demolition=id
	_clear_children(confirm_body)
	_label(confirm_body,"确认拆除设施",23,RED)
	var building: Dictionary=sim.get_building(id)
	_paragraph(confirm_body,"%s · 回收 ¥%s\n将移除 %d 条电力线路、%d 条通信链路。" % [building.name,_number(float(preview.get("refund",0))),preview.get("line_ids",[]).size(),preview.get("communication_ids",[]).size()],CREAM,14)
	_paragraph(confirm_body,"关联负荷可能失供，设备在途操作会终止。实际影响依赖当前网络；未知状态需先核实。",ORANGE,14)
	var cancel := _button(confirm_body,"取消，保留设施",func(): confirmation.hide(); pending_demolition=-1)
	var button:=_button(confirm_body,"确认拆除并移除连接",_confirm_demolition)
	button.add_theme_color_override("font_color",RED)
	confirmation.show()
	cancel.grab_focus()
	_update_time_status(true)

func _confirm_demolition() -> void:
	confirmation.hide()
	if pending_demolition<0: return
	var result: Dictionary=sim.demolish(pending_demolition)
	_apply(result)
	if audio and result.get("ok",false): audio.play_action("demolish",true)
	if result.get("ok",false):
		selected_id=-1
		selected_line=-1
		selected_comm_line=-1
		inspector_selection=""
	pending_demolition=-1
	_sync_world(true)
	_update_hud()
	_update_inspector()

func _append_object_jobs(parent: Node, kind: String, id: int) -> void:
	var rows: Array=Presenter.jobs(sim)
	var displayed:=0
	for job in rows:
		if str(job.target_type)!=kind or int(job.target_id)!=id: continue
		var phase: String=str(job.phase)
		_paragraph(parent,("… 已排队 · " if phase=="pending" else ("✓ 已执行 · " if phase=="executed" else "× 执行失败 · "))+str(job.message),ORANGE if phase in ["pending","rejected"] else TEAL,14)
		displayed+=1
		if displayed>=3: break
	if displayed>0: _button(parent,"查看完整队列与回执",func(): hud.operator_dock.show_page("jobs"),Vector2(0,34))

func _has_unsent_drafts() -> bool:
	for center in [market_panel,digital_panel,planning_panel]:
		if center==null or center.get("drafts")==null: continue
		if center.has_method("_capture_drafts"): center._capture_drafts()
		var drafts: RefCounted=center.drafts
		for key in drafts.values:
			if drafts.dirty(key): return true
	return false

func _update_onboarding() -> void:
	if hud==null or hud.onboarding_panel==null: return
	hud.onboarding_panel.visible=onboarding and not onboarding_skipped and not _campaign_active() and not _modal_open()
	if not hud.onboarding_panel.visible: return
	if sim.has_method("management_status"):
		var status: Dictionary=sim.management_status()
		if status.get("active",false) and int(status.get("stage",0))>0:
			hud.onboarding_panel.hide()
			return
	var connected:=false
	for line in sim.lines:
		if (int(line.a)==2 and int(line.b)==6) or (int(line.a)==6 and int(line.b)==2): connected=true
	if connected:
		hud.onboarding_label.text="✓ 已连接工业区\n观察底部已供/需求与净收益。点击供电数字可查看诊断；供电改善后可继续自由运营。"
	else:
		hud.onboarding_label.text="1 选择接线工具\n2 点击中央变电站，再点击东部工业园区\n3 观察已供功率与收益变化；检查线路负载。"

func _offer_discard_drafts(next: Callable) -> bool:
	if not _has_unsent_drafts(): return false
	_clear_children(confirm_body)
	_label(confirm_body,"切换进度并清空草案？",22,ORANGE)
	_paragraph(confirm_body,"未提交的市场、设施和安全配置不会带入其他进度。取消可继续编辑，确认后清空当前草案。",CREAM,14)
	var cancel := _button(confirm_body,"取消，继续编辑",_cancel_confirmation)
	_button(confirm_body,"确认切换并清空草案",func(): confirmation.hide(); next.call())
	confirmation.show()
	cancel.grab_focus()
	_update_time_status(true)
	return true

func _front_modal() -> Control:
	for modal in [settings_panel,confirmation,campaign_panel,planning_panel,digital_panel,market_panel,end_modal,help_modal,pause_menu,welcome]:
		if modal!=null and modal.visible: return modal
	return null

func _modal_focusables(node: Node, result: Array[Control]) -> void:
	if node is Control and node.is_visible_in_tree() and node.focus_mode==Control.FOCUS_ALL:
		if not (node is BaseButton and node.disabled): result.append(node)
	for child in node.get_children(): _modal_focusables(child,result)

func _guard_modal_focus(event: InputEventKey) -> bool:
	var modal: Control=_front_modal()
	if modal==null: return false
	if modal==settings_panel and not settings_panel.pending_action.is_empty(): return false
	var focus: Control=get_viewport().gui_get_focus_owner()
	var outside: bool=focus==null or not modal.is_ancestor_of(focus)
	if not outside and event.keycode!=KEY_TAB: return false
	var controls: Array[Control]=[]
	_modal_focusables(modal,controls)
	if controls.is_empty(): return false
	var index: int=controls.find(focus)
	if event.keycode==KEY_TAB:
		index=posmod(index+(-1 if event.shift_pressed else 1),controls.size())
		controls[index].grab_focus()
		get_viewport().set_input_as_handled()
		return true
	if outside:
		controls[0].grab_focus()
		if event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]:
			get_viewport().set_input_as_handled()
			return true
	return false

func _save_paths() -> Array:
	return [campaign_save_path,campaign_autosave_path,sandbox_save_path,sandbox_autosave_path]

func _refresh_title() -> void:
	title_catalog = SaveCatalog.inspect(_save_paths())
	welcome.open_title(title_catalog)
	_update_audio()

func _activate_session() -> void:
	session_started = true
	app_state = AppState.PLAYING
	_focus_suspended = false
	if welcome: welcome.hide()
	if pause_menu: pause_menu.hide()
	if world: world.show()
	if hud: hud.show()
	if operator_map: operator_map.show()

func _open_pause() -> void:
	if not session_started or app_state==AppState.TITLE: return
	hud.close_popups()
	if ghost: ghost.hide()
	app_state = AppState.PAUSED
	pause_menu.open_pause()
	_update_time_status(true)
	_update_audio()

func _close_pause() -> void:
	pause_menu.hide()
	app_state = AppState.PLAYING
	_update_time_status()
	_update_audio()

func _open_settings() -> void:
	_settings_origin = "title" if app_state==AppState.TITLE else ("paused" if app_state==AppState.PAUSED else "playing")
	settings_panel.open()
	_update_time_status(true)
	_update_audio()

func _settings_closed() -> void:
	if _settings_origin=="title":
		welcome.show()
		welcome.buttons.settings.grab_focus()
	elif _settings_origin=="paused":
		pause_menu.show()
		pause_menu.buttons.settings.grab_focus()
	_update_hud()
	_update_audio()

func _frontend_action(action: String) -> void:
	match action:
		"continue":
			if app_state==AppState.PAUSED: _close_pause()
			else: _continue_latest()
		"campaign": _open_campaign_directory()
		"management", "sandbox": _request_new_mode(action)
		"save":
			_save()
			pause_menu.summary.text = notice_label.text
		"load": _load()
		"settings": _open_settings()
		"title": _leave_session(false)
		"quit": _leave_session(true)
		"credits": _show_credits()

func _continue_latest() -> void:
	var catalog: Dictionary = SaveCatalog.inspect(_save_paths())
	if catalog.latest.is_empty():
		_refresh_title()
		return
	_load(str(catalog.latest.path))

func _open_campaign_directory() -> void:
	welcome.hide()
	pause_menu.hide()
	campaign_panel.open_directory()
	_update_audio()

func close_campaign_directory() -> void:
	if app_state==AppState.TITLE:
		_refresh_title()
	elif app_state==AppState.PAUSED:
		pause_menu.show()
		pause_menu.buttons.campaign.grab_focus()
	_update_audio()

func _confirm_frontend(title_text: String, detail: String, action_text: String, callback: Callable) -> void:
	_clear_children(confirm_body)
	_label(confirm_body,title_text,23,ORANGE)
	_paragraph(confirm_body,detail,CREAM,15)
	var cancel := _button(confirm_body,"取消，保留当前进度",_cancel_confirmation)
	UI.action(_button(confirm_body,action_text,func(): confirmation.hide(); callback.call()),"destructive")
	confirmation.show()
	cancel.grab_focus()

func _request_new_mode(mode: String, confirmed: bool=false) -> void:
	if not confirmed:
		var prior: Dictionary = SaveCatalog.inspect([sandbox_save_path,sandbox_autosave_path])
		if not prior.latest.is_empty():
			_confirm_frontend("开启新进度？","经营路线与自由沙盘共用当前档位。\n%s · %s\n新进度保存后将替换该档位，教学战役不受影响。" % [prior.latest.title,prior.latest.detail],"确认开启新进度",func(): _request_new_mode(mode,true))
			return
	if mode=="management": _begin_management()
	else: _begin_free_sandbox()
	var saved: Dictionary = _atomic_save(sandbox_save_path)
	_apply(saved)
	if saved.get("ok",false): _remove_stale_auto(sandbox_autosave_path)

func request_campaign_start(id: int, discard_drafts: bool=false) -> void:
	if not discard_drafts and _offer_discard_drafts(func(): request_campaign_start(id,true)): return
	var prior: Dictionary = SaveCatalog.inspect([campaign_save_path,campaign_autosave_path],"campaign")
	if not prior.latest.is_empty() or (session_started and _campaign_active()):
		var saved_title: String = str(prior.latest.get("title","当前教学战役"))
		var saved_detail: String = str(prior.latest.get("detail",sim.campaign.chapter().get("title","")))
		_confirm_frontend("从章节开头进入？","当前战役档位：%s · %s\n从章节开头进入会替换本关进行中的进度；已完成章节与解锁仍保留。" % [saved_title,saved_detail],"确认从章节开头进入",func(): _start_confirmed_chapter(id))
	else: campaign_panel.request_start(id,true)

func _start_confirmed_chapter(id: int) -> void:
	campaign_panel.request_start(id,true)

func _leave_session(exit_game: bool, discard_drafts: bool=false) -> void:
	if session_started and not discard_drafts and _offer_discard_drafts(func(): _leave_session(exit_game,true)): return
	if session_started:
		var result: Dictionary = _atomic_save(campaign_save_path if _campaign_active() else sandbox_save_path)
		if not result.get("ok",false):
			_clear_children(confirm_body)
			_label(confirm_body,"保存失败",24,RED)
			_paragraph(confirm_body,"当前进度仍保留在游戏中。检查存储空间后可以重试。",CREAM,15)
			_button(confirm_body,"取消，返回游戏",_cancel_confirmation).grab_focus()
			_button(confirm_body,"重试保存",func(): confirmation.hide(); _leave_session(exit_game,true))
			UI.action(_button(confirm_body,"不保存并退出" if exit_game else "不保存并返回主菜单",func(): confirmation.hide(); _finish_leave(exit_game)),"destructive")
			confirmation.show()
			confirmation.z_index = 80
			return
	_finish_leave(exit_game)

func _finish_leave(exit_game: bool) -> void:
	if exit_game:
		get_tree().quit()
		return
	for center in [market_panel,digital_panel,planning_panel,campaign_panel,settings_panel,help_modal,end_modal,confirmation,pause_menu]:
		center.hide()
		if center.has_method("reset_session"): center.reset_session()
	app_state = AppState.TITLE
	_restore_settings_on_cancel = false
	session_started = false
	autosave_clock = 0.0
	_focus_suspended = false
	hud.hide()
	operator_map.hide()
	world.hide()
	_refresh_title()
	if audio: audio.reset_session({})

func _show_credits() -> void:
	_clear_children(confirm_body)
	_label(confirm_body,"制作名单",26)
	_paragraph(confirm_body,"潮汐电网 · TIDAL GRID\n原创电网建设、经营与历史教学游戏\n\n引擎：Godot\n中文字体：Noto Sans CJK SC · SIL OFL\n场景与设施：原创程序化微缩模型\n封面与概念：内置 imagegen 原创生成\n音乐与声音：原创离线作曲与合成",CREAM,15)
	_button(confirm_body,"返回主菜单",func(): confirmation.hide()).grab_focus()
	confirmation.show()

func _audio_snapshot() -> Dictionary:
	var snapshot: Dictionary = Presenter.operating_snapshot(sim)
	snapshot.time_hours = float(sim.time_hours)
	snapshot.weather = "storm" if sim.storm_active else "clear"
	snapshot.mode = "campaign" if _campaign_active() else "playing"
	# Only the selected, publicly observed facility contributes a world sound.
	snapshot.facilities = Presenter.facilities(sim,str(selected_id)).filter(func(row: Dictionary): return int(row.id)==selected_id) if selected_id>=0 else []
	return snapshot

func _audio_baseline() -> Dictionary:
	return {"snapshot":_audio_snapshot(),"alerts":Presenter.alerts(sim),"receipts":Presenter.jobs(sim)}

func _progress_audio_signature() -> String:
	if _campaign_active(): return str([sim.campaign.chapter_id,sim.campaign.step_index])
	if sim.management.state.active: return str(sim.management.state.stage)
	return str(sim.objectives.map(func(item: Dictionary): return bool(item.get("done",false))))

func _update_audio() -> void:
	if audio==null: return
	if app_state==AppState.TITLE:
		audio.set_context("title")
		return
	audio.set_context("paused" if _modal_open() or _focus_suspended else ("campaign" if _campaign_active() else "playing"))
	if not _modal_open() and not _focus_suspended:
		audio.observe_public_state(_audio_snapshot(),Presenter.alerts(sim),Presenter.jobs(sim))

func _wire_sound_tree(node: Node) -> void:
	_wire_ui_sound(node)
	for child in node.get_children(): _wire_sound_tree(child)

func _wire_ui_sound(node: Node) -> void:
	if audio==null or node.has_meta("sound_wired"): return
	if node is BaseButton:
		node.set_meta("sound_wired",true)
		node.pressed.connect(func():
			if is_instance_valid(audio): audio.play_ui("confirm")
		)
		node.focus_entered.connect(func():
			if is_instance_valid(audio): audio.play_ui("hover")
		)
	elif node is Slider:
		node.set_meta("sound_wired",true)
		node.drag_ended.connect(func(_changed: bool):
			if is_instance_valid(audio): audio.play_ui("confirm")
		)

func _notification(what: int) -> void:
	if not is_ready: return
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		_restore_settings_on_cancel = settings_panel.visible
		if settings_panel.visible: settings_panel.close()
		_leave_session(true)
	elif what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focus_suspended = session_started and preferences.pause_unfocused
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN:
		_focus_suspended = false

func _cancel_confirmation() -> void:
	confirmation.hide()
	if _restore_settings_on_cancel:
		_restore_settings_on_cancel = false
		_open_settings()

func _remove_stale_auto(path: String) -> void:
	if not FileAccess.file_exists(path): return
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(path))!=OK:
		_notify("新进度已保存，但旧自动存档无法清理。请检查存储权限。",false)

func _atomic_save(path: String) -> Dictionary:
	var pending: String = path + ".pending"
	var written: Dictionary = sim.save_game(pending)
	if not written.get("ok",false): return written
	var target: String = ProjectSettings.globalize_path(path)
	var temporary: String = ProjectSettings.globalize_path(pending)
	var previous: String = target + ".previous-" + str(Time.get_ticks_usec())
	var existed: bool = FileAccess.file_exists(path)
	if existed and DirAccess.rename_absolute(target,previous)!=OK:
		DirAccess.remove_absolute(temporary)
		return {"ok":false,"message":"无法替换存档；原存档已保留。"}
	if DirAccess.rename_absolute(temporary,target)!=OK:
		if existed: DirAccess.rename_absolute(previous,target)
		return {"ok":false,"message":"无法完成存档写入；请检查存储权限。"}
	if existed: DirAccess.remove_absolute(previous)
	if audio: audio.play_action("save",true)
	return {"ok":true,"message":"存档已保存。"}
