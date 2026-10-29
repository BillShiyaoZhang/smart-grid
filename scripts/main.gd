extends Node3D

const UI = preload("res://scripts/ui/ui_kit.gd")
const GameHud = preload("res://scripts/ui/game_hud.gd")
const OperatorMap = preload("res://scripts/ui/operator_map.gd")
const Preferences = preload("res://scripts/ui/operator_preferences.gd")
const SettingsDesk = preload("res://scripts/ui/settings_panel.gd")
const Presenter = preload("res://scripts/ui/grid_presenter.gd")
const Sim = preload("res://scripts/sim/grid_sim.gd")
const Models = preload("res://scripts/art/model_factory.gd")
const Island = preload("res://scripts/art/island_factory.gd")
const Chart = preload("res://scripts/ui/power_chart.gd")
const MarketDesk = preload("res://scripts/ui/market_panel.gd")
const DigitalDesk = preload("res://scripts/ui/digital_panel.gd")
const PlanningDesk = preload("res://scripts/ui/planning_panel.gd")
const CampaignDesk = preload("res://scripts/ui/campaign_panel.gd")
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

func _ready() -> void:
	preferences = Preferences.new()
	preferences.load_preferences()
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
	capture_mode = "--capture" in OS.get_cmdline_user_args()
	if capture_mode:
		welcome.hide()
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
	atmosphere.ambient_light_energy = 0.25
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = atmosphere
	environment_state = atmosphere
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "AfternoonSun"
	sun.rotation_degrees = Vector3(-52,-35,0)
	sun.light_color = Color("ffedd5")
	sun.light_energy = 0.45
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
	var pos := get_viewport().get_mouse_position()
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
	if not city.building_ids.is_empty():
		selected_id = int(city.building_ids[0])
		selected_line = -1
		selected_comm_line = -1
	_update_inspector()
	_sync_world(true)
	_notify("%s · %s · 人口 %.0f" % [city.name,city.specialization,city.population])

func _sync_world(force: bool=false) -> void:
	_sync_terrain()
	if sim.region.active:
		for child in terrain.get_children():
			if child.has_meta("city_id"):
				var city: Dictionary = sim.region.city_status(int(child.get_meta("city_id")))
				child.text = "%s · %s" % [city.name,city.specialization]
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
			var height: float = heights.get(b.kind,1.5)
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
			signpost.position.y = 3.35 if b.kind == "relay" else (3.1 if b.kind == "wind" else 1.9)
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
	sun_light.light_energy = (0.06+daylight*0.39)*(0.65 if storm else 1.0)
	environment_state.ambient_light_energy = 0.11+daylight*0.14
	environment_state.ambient_light_color = Color("638aaf").lerp(Color("c5e1df"),daylight)
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
			cam_target += (right*move.x+forward*move.y)*delta*10
			cam_target.x = clampf(cam_target.x,-14,78 if sim.map_size()>16 else 14)
			cam_target.z = clampf(cam_target.z,-14,78 if sim.map_size()>16 else 14)
			_update_camera()
	var effective_speed := 0 if _modal_open() else speed
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
	autosave_clock += delta
	if autosave_clock > 90:
		autosave_clock = 0
		sim.save_game(campaign_autosave_path if _campaign_active() else "user://autosave.json")

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
				confirmation.hide()
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
				welcome.hide()
			elif end_modal.visible:
				end_modal.hide()
			elif hud.close_top():
				pass
			else:
				_set_tool("select")
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
			zoom = maxf(22,zoom-2)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(135 if sim.map_size()>16 else 58,zoom+2)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
			drag_origin = event.position
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_set_tool("select")
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_map_click(_mouse_cell())
	if event is InputEventMouseMotion and dragging:
		var d: Vector2 = event.relative
		var right := camera.global_basis.x
		var forward := Vector3(camera.global_basis.z.x,0,camera.global_basis.z.z).normalized()
		cam_target -= (right*d.x+forward*d.y)*zoom/800
		cam_target.x = clampf(cam_target.x,-14,78 if sim.map_size()>16 else 14)
		cam_target.z = clampf(cam_target.z,-14,78 if sim.map_size()>16 else 14)
		_update_camera()

func _modal_open() -> bool:
	return (settings_panel != null and settings_panel.visible) or (confirmation != null and confirmation.visible) or (campaign_panel != null and campaign_panel.visible) or (welcome != null and welcome.visible) or (help_modal != null and help_modal.visible) or (end_modal != null and end_modal.visible) or (market_panel != null and market_panel.visible) or (digital_panel != null and digital_panel.visible) or (planning_panel != null and planning_panel.visible)

func _handle_map_click(cell: Vector2i) -> void:
	var id := _building_at(cell)
	if tool == "build":
		if _is_map_cell(cell):
			var result: Dictionary = sim.build(build_kind,cell)
			_apply(result)
			if result.get("ok",false):
				selected_id=int(result.get("id",-1))
				selected_line=-1
				selected_comm_line=-1
				_notify("建成尚需接网 · 选择接线工具连接电源或变电站")
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
			if result.get("ok",false): connection_start = -1
			_sync_world(true)
	elif tool == "repair":
		if id >= 0:
			_apply(sim.repair(id))
		else:
			var line_id := _nearest_line(_mouse_ground())
			if line_id >= 0:
				_apply(sim.repair_line(line_id))
	else:
		selected_id = id
		selected_line = -1 if id >= 0 or overlay=="comm" else _nearest_line(_mouse_ground())
		selected_comm_line = _nearest_communication(_mouse_ground()) if id<0 and overlay=="comm" else -1
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
	_apply(sim.save_game(campaign_save_path if _campaign_active() else "user://tidal_grid_save.json"))

func _load(path: String="") -> void:
	if path.is_empty(): path = campaign_save_path if _campaign_active() else "user://tidal_grid_save.json"
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
	_rebuild_session()
	_notify("存档已读取；上个会话的草案与关注列表已清空。")

func _rebuild_session(reset_view: bool=false) -> void:
	for item in visuals.values(): item.queue_free()
	visuals.clear()
	chart.reset_history()
	hud.operator_dock.reset_session()
	for center in [market_panel,digital_panel,planning_panel,campaign_panel]:
		if center.has_method("reset_session"): center.reset_session()
	hud.close_popups()
	hud.close_tray()
	inspector_selection = ""
	for panel in [market_panel,digital_panel,planning_panel,campaign_panel,welcome,help_modal,end_modal,confirmation,settings_panel]:
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

func start_campaign_chapter(id: int, discard_drafts: bool=false) -> void:
	if not discard_drafts and _offer_discard_drafts(func(): start_campaign_chapter(id,true)): return
	if id<1 or id>int(campaign_panel.profile.unlocked):
		_notify("请先完成上一章。",false)
		return
	if not _campaign_active():
		var backup: Dictionary = sim.save_game(campaign_backup_path)
		if not backup.ok: _apply(backup); return
	var result: Dictionary = sim.start_campaign(id)
	if not result.ok: _apply(result); return
	campaign_panel.profile.last_chapter=id
	campaign_panel.save_profile()
	_rebuild_session(true)
	sim.save_game(campaign_save_path)
	campaign_panel.open_briefing()

func restart_campaign_chapter(discard_drafts: bool=false) -> void:
	if not discard_drafts and _offer_discard_drafts(func(): restart_campaign_chapter(true)): return
	var result: Dictionary = sim.restart_campaign_chapter()
	if not result.ok: _apply(result); return
	_rebuild_session(true)
	sim.save_game(campaign_save_path)
	campaign_panel.open_briefing()

func continue_campaign(discard_drafts: bool=false) -> void:
	if not discard_drafts and _offer_discard_drafts(func(): continue_campaign(true)): return
	var path := campaign_save_path
	if FileAccess.file_exists(campaign_autosave_path):
		if not FileAccess.file_exists(path) or FileAccess.get_modified_time(campaign_autosave_path)>FileAccess.get_modified_time(path): path=campaign_autosave_path
	var result: Dictionary = sim.load_game(path)
	if not result.ok: _apply(result); return
	_rebuild_session()
	if not last_finished: hud.toggle_popup("missions")

func return_to_sandbox(discard_drafts: bool=false) -> void:
	if not discard_drafts and _offer_discard_drafts(func(): return_to_sandbox(true)): return
	if _campaign_active():
		sim.save_game(campaign_save_path)
		if FileAccess.file_exists(campaign_backup_path):
			var result: Dictionary=sim.load_game(campaign_backup_path)
			if not result.ok: _apply(result); return
		else: sim.reset(42)
		_rebuild_session()
	else:
		campaign_panel.hide()

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
	settings_panel.closed.connect(_update_hud)

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

func _hud_action(value: String) -> void:
	match value:
		"pause": _toggle_pause()
		"speed_1", "speed_3", "speed_8": speed=int(value.trim_prefix("speed_")); previous_speed=speed; _update_hud()
		"save": _save()
		"load": _load()
		"help": help_modal.show()
		"settings": settings_panel.open(); _update_time_status(true)
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
			sim.save_game(campaign_save_path)
			campaign_panel.open_report(bool(sim.campaign.completed))
	else:
		var mission_text := str(sim.objectives)
		if mission_text != mission_snapshot:
			_clear_children(mission_box)
			var first_active := true
			for objective in sim.objectives:
				var done: bool = bool(objective.get("completed",objective.get("done",false)))
				var name_: String = str(objective.get("title",objective.get("name","运营目标")))
				var l := _label(mission_box,("✓  " if done else "○  ")+name_,12,TEAL if done else CREAM)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.custom_minimum_size.x = 260
				if not done and first_active:
					first_active = false
					var desc: String = str(objective.get("description",objective.get("detail","")))
					if not desc.is_empty():
						var d := _label(mission_box,desc,10,MUTED)
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
	_update_onboarding()

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
	var observation: Dictionary = sim.facility_observation(int(b.id))
	var status: String = str(observation.status) if observation.trusted else "运行状态待核实"
	if float(b.get("repair_remaining",0)) > 0:
		status = "抢修中 · %.1f 小时" % b.repair_remaining
	elif observation.trusted and float(observation.get("health",100)) <= 0:
		status = "设备故障 · 等待维修"
	elif b.kind in ["home","factory","hospital"] and not b.get("powered",false):
		status = "供电中断 · 请检查连接"
	_paragraph(inspector_box,"●  "+status,TEAL if observation.trusted else ORANGE,14)
	_stat(inspector_box,"设备等级","L%d" % b.get("level",1))
	var comm: Dictionary=sim.communication_status(int(b.id))
	_stat(inspector_box,"设备遥测","可信" if observation.trusted else "未确认 / 过时",TEAL if observation.trusted else ORANGE)
	_stat(inspector_box,"资产状况","%.0f%%" % observation.health if observation.trusted else "需遥测或现场检查")
	if float(b.get("capacity",0))>0 and b.kind!="substation": _stat(inspector_box,"额定容量","%.1f MW" % b.capacity)
	if b.kind in ["home","factory","hospital"]:
		_stat(inspector_box,"当前需求","%.2f MW" % observation.demand if observation.trusted else "遥测未确认")
		_stat(inspector_box,"实际供电","%.2f MW" % observation.served if observation.trusted else ("用户有供电反馈" if b.get("powered",false) else "用户报告停电"),TEAL)
	else:
		_stat(inspector_box,"实时出力","%.2f MW" % observation.output if observation.trusted else "遥测未确认",TEAL)
	if b.kind in ["sensor","control","relay","soc"] and sim.feature_enabled("digital"):
		_button(inspector_box,"⌁ 打开数字电网运行中心",func(): _open_center("network"); digital_panel._select_device(int(b.id)),Vector2(0,34))
		_button(inspector_box,"⌁ 从这里铺设通信链路",func(): _set_tool("datalink"); connection_start=int(b.id); _sync_world(true),Vector2(0,34))
	if sim.evolution.is_storage(str(b.kind)):
		_stat(inspector_box,"储存能量","%.2f MWh" % observation.energy if observation.trusted else "遥测未确认",TEAL)
		if sim.feature_enabled("market"): _button(inspector_box,"⇄ 储能策略与电价",func(): _open_center("market"); market_panel.tabs.current_tab=2,Vector2(0,32))
	if sim.evolution.is_terminal(str(b.kind)):
		_stat(inspector_box,"净交换功率","%+.2f MW" % observation.output if observation.trusted else "遥测未确认",TEAL)
		if sim.feature_enabled("market"): _button(inspector_box,"⇄ 打开电力交易中心",func(): _open_center("market"),Vector2(0,32))
	if sim.feature_enabled("research"): _button(inspector_box,"运行边界与精细控制  "+preferences.binding_label("planning"),func(): _open_center("planning"); planning_panel.select_facility(int(b.id)),Vector2(0,32))
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
	_append_object_jobs(inspector_box,"line",id)

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
	_apply(sim.research())
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
	welcome = _modal(dialog_layer,740,650)
	var v := _column(welcome.get_node("Dialog/ContentScroll/Content"),10)
	if ResourceLoader.exists("res://assets/art/operator_cover.png"):
		var art := TextureRect.new()
		art.texture = load("res://assets/art/operator_cover.png")
		art.custom_minimum_size = Vector2(0,140)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		v.add_child(art)
	_label(v,"潮汐电网",34)
	_label(v,"让清洁能源，点亮一座海湾。",19,TEAL)
	_paragraph(v,"你接手了青屿湾的供电网络。建设发电设施，连接城区，平衡昼夜供需，并在风暴来临时守住每一盏灯。",CREAM,15)
	UI.spacer(v).size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label(v,"建造与接线  →  调度与储能  →  抢修与扩建",15,ORANGE)
	_label(v,"左键交互 · 右键取消 · 空格暂停 · H 调度员手册",14,MUTED)
	var begin := _button(v,"开始运营   →",func(): welcome.hide(); onboarding=true; onboarding_skipped=false; _update_onboarding(); _notify("用接线工具连接中央变电站与东部工业园区。"),Vector2(0,48))
	var campaign_actions := _row(v,10)
	_button(campaign_actions,"历史战役  ·  电力时代",func(): campaign_panel.open_directory(),Vector2(0,40))
	_button(campaign_actions,"继续战役",func(): continue_campaign(),Vector2(0,40))
	begin.add_theme_stylebox_override("normal",UI.style(Color("28584f"),6,TEAL,10))
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
		["建设与接线","从底部选择发电、输电、储能、城市或数字设施，展开建设目录。选择设施后点击空地放置；接线工具需要依次点击两座设施。所有电力设施都需要电气连接。\n\n右键取消当前工具；Esc 优先关闭展开面板。点击地图上的设施或线路，在右侧查看详情和操作。"],
		["调度与储能","光伏随太阳变化，风机随天气变化。燃气提供可调备用，电池在富余时充电、短缺时放电。MW 表示当前功率，MWh 表示储存能量。\n\n左侧统计入口提供供需曲线、电网拓扑、清洁能源与储能数据。选中设施后，可从高级控制进入精细调度。"],
		["故障与恢复","图层入口提供景观、功率、健康和通信视图。可靠观测或现场巡检决定你能看到哪些故障，未知读数不能作为确定信息。\n\n点击线路可以巡检定位、派现场开关队或抢修；远程控制需要可信路径。备用供电路径可以分散潮流，提高韧性。"],
		["委托与运营","点击左上角当前委托查看完整目标、研究、需求响应和风暴演练。研究解锁能力后仍然需要真实通信路径。\n\n自然风暴首次在第1天14:00抵达，此后每30游戏小时再来；失供电按每MWh ¥60支付补偿。一般操作显示短暂回执，已知异常在右上角告警中保留。"],
		["电价与交易","按 M 进入市场，配置购售电、零售电价、储能策略和12小时锁价合约。建造市场联络站并接线后才可以交付电力；合约用不完仍需付费。\n\n配置修改后点击应用；刷新、切页和报价不会结算。推进1小时可以观察真实账单。"],
		["数字电网","按 N 管理独立通信网，按4进入地图通信布线。通信线与电力线分别建设。可信遥测帮助定位故障；失联时可先巡检或派现场队。\n\n安全页面选择明确的演练目标，事件页查看已检测事件与作业回执。隔离和修补需要时间；推进15分钟观察恢复。"],
		["科技与区域","按 T 浏览六代科技，选中节点后查看前置、费用、时间与解锁设施。研发需要游戏时间，一次开展一个项目。\n\n设施页区分运行设置与建设目录。区域页可以开启八城沙盘、定位城市并设定长期目标。历史开局与恢复位于科技页的场景选项。"],
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
	end_modal = _modal(dialog_layer,650,410)
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
	if _campaign_active(): campaign_panel.open_report(victory); return
	var panel := end_modal.get_node("Dialog/ContentScroll/Content")
	_clear_children(panel)
	var v := _column(panel,18)
	_label(v,"青屿湾示范区  /  运营报告",14,MUTED)
	_label(v,"运营委托完成" if victory else "运营资金告急",26,TEAL if victory else RED)
	_paragraph(v,"你完成了建设、清洁转型、数字化和风暴恢复四项委托。青屿湾已成为智能电网示范区，接下来按 T 研究更多代际科技、开启八城区域沙盘，或设定长期运营目标。" if victory else "累计亏损已经超过应急额度。你可以继续调整电网与成本，也可以重新接手一座全新的海湾。",CREAM,14)
	_stat(v,"当前资金","¥ "+_number(sim.cash))
	_stat(v,"电网规模","%d 设施 · %d 线路" % [sim.buildings.size(),sim.lines.size()])
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

func _new_game(heritage: bool=false,discard_drafts: bool=false) -> void:
	if not discard_drafts and _offer_discard_drafts(func(): _new_game(heritage,true)): return
	if heritage:
		sim.start_heritage()
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
		if modal==null: continue
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
	var cancel := _button(confirm_body,"取消，继续编辑",func(): confirmation.hide())
	_button(confirm_body,"确认切换并清空草案",func(): confirmation.hide(); next.call())
	confirmation.show()
	cancel.grab_focus()
	_update_time_status(true)
	return true

func _front_modal() -> Control:
	for modal in [settings_panel,confirmation,campaign_panel,planning_panel,digital_panel,market_panel,end_modal,help_modal,welcome]:
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
