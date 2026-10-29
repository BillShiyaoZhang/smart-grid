extends Control
## Screen-space network information. Hidden electrical truth never enters this view.
const UI = preload("res://scripts/ui/ui_kit.gd")
const Presenter = preload("res://scripts/ui/grid_presenter.gd")
var game: Node
var _clock := 0.0

func setup(owner_game: Node) -> void:
	game = owner_game
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	_clock += delta
	if _clock >= .12:
		_clock = 0
		queue_redraw()

func _screen(point: Vector3) -> Vector2:
	return game.camera.unproject_position(point) / game.root_ui.scale

func _label(at: Vector2, text: String, color: Color=UI.TEXT) -> void:
	var font := get_theme_default_font()
	var dimensions: Vector2 = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,14)
	at.x=clampf(at.x,8,maxf(8,size.x-dimensions.x-10))
	at.y=clampf(at.y,20,maxf(20,size.y-10))
	var rect := Rect2(at-Vector2(4,16),dimensions+Vector2(8,6))
	draw_style_box(UI.style(Color("102833ee"),3,Color("36515b"),3),rect)
	draw_string(font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)

func _draw() -> void:
	if game == null or not game.is_ready or game._modal_open(): return
	var electrical: bool = game.overlay == "power" or game.tool == "line"
	if game.tool == "build" and game.build_kind in ["hydro","pumped_storage"]:
		var map: Dictionary = game.sim.map_spec()
		var cells: Array = map.get("river_cells",[]) if game.build_kind == "hydro" else map.get("hill_cells",[])
		if cells.is_empty():
			for x in range(1,game.sim.map_size()-1):
				for y in range(1,game.sim.map_size()-1):
					var cell := Vector2i(x,y)
					if game.sim.evolution.can_place(game.build_kind,cell).get("ok",false): cells.append(cell)
		for cell in cells:
			var world: Vector3 = game._cell_position(cell)
			var polygon := PackedVector2Array()
			for corner in [Vector3(-.9,.08,-.9),Vector3(.9,.08,-.9),Vector3(.9,.08,.9),Vector3(-.9,.08,.9)]: polygon.append(_screen(world+corner))
			draw_colored_polygon(polygon,Color(.45,.9,.75,.16))
		if not game.hud.tray.visible and size.y>=650: _label(Vector2(100,176),"选址范围 · 轮廓内仍需满足空地与预算",UI.TEAL)
	for line in game.sim.lines:
		var selected: bool = int(line.id) == game.selected_line or int(line.id) == game.hover_line
		var related: bool = game.connection_start in [int(line.a),int(line.b)] or game.selected_id in [int(line.a),int(line.b)]
		if not electrical and not selected and not related: continue
		var first: Dictionary = game.sim.get_building(int(line.a))
		var second: Dictionary = game.sim.get_building(int(line.b))
		if first.is_empty() or second.is_empty(): continue
		var start := _screen(game._cell_position(first.cell)+Vector3.UP*.5)
		var finish := _screen(game._cell_position(second.cell)+Vector3.UP*.5)
		var observation: Dictionary = game.sim.line_observation(int(line.id))
		var current: bool = observation.get("visibility","") in ["verified","patrol"]
		var color := (Color("c5fff0") if game.preferences.high_contrast else UI.TEAL) if current else Color("acc4cb")
		var flow: float = float(observation.get("flow",0)) if observation.get("flow") != null and current else 0.0
		var fault: bool = current and observation.get("fault_known",false) and observation.get("fault",false)
		var closed: bool = current and observation.get("closed",false)
		if current and absf(flow) / maxf(.1,float(line.capacity)) > .85: color = UI.AMBER
		if fault: color = UI.RED
		if selected: draw_line(start,finish,UI.TEXT,6,true)
		if not current or not closed or fault: draw_dashed_line(start,finish,color,3 if selected else 2,7)
		else: draw_line(start,finish,color,3.5 if selected else 2,true)
		if selected:
			draw_circle(start,5,UI.TEXT); draw_circle(finish,5,UI.TEXT)
			var state: String = "%.1f / %.0f MW" % [absf(flow),line.capacity] if current else str({"unknown":"? 未知","stale":"? 缓存过时","suspect":"? 读数可疑"}.get(observation.get("visibility","unknown"),"? 待核实"))
			if fault: state="× 已确认故障"
			elif current and not closed: state="○ 开关断开"
			var caption := "线路 %02d · %s" % [line.id,state]
			_label(start.lerp(finish,.5)+Vector2(8,-12),caption,UI.TEXT)
		if closed and not fault and absf(flow)>.02:
			var direction: Vector2 = (finish-start).normalized() * (1 if flow>0 else -1)
			var middle: Vector2 = start.lerp(finish,.55)
			draw_line(middle,middle-direction.rotated(.55)*9,color,2,true)
			draw_line(middle,middle-direction.rotated(-.55)*9,color,2,true)
	if game.tool in ["line","datalink"] and game.connection_start >= 0:
		var first: Dictionary = game.sim.get_building(game.connection_start)
		if not first.is_empty():
			var start := _screen(game._cell_position(first.cell)+Vector3.UP*.65)
			var endpoint: int = game._building_at(game._mouse_cell())
			var preview: Dictionary = game.sim.preview_connection(game.connection_start,endpoint,"power" if game.tool=="line" else game.communication_kind)
			var finish: Vector2 = get_local_mouse_position()
			if endpoint>=0: finish = _screen(game._cell_position(game.sim.get_building(endpoint).cell)+Vector3.UP*.65)
			draw_dashed_line(start,finish,UI.TEAL if preview.ok else UI.AMBER,3,8)
			draw_circle(start,6,UI.TEXT)
	var clusters: Dictionary = {}
	for building in game.sim.buildings:
		var id: int = int(building.id)
		var point := _screen(game._cell_position(building.cell)+Vector3.UP*2)
		var targeted: bool = id in [game.selected_id,game.connection_start,game._building_at(game.hover_cell)]
		if targeted:
			_label(point+Vector2(7,-5),"%02d · %s" % [id,building.name],UI.TEXT)
		elif game.zoom>60:
			var bucket := Vector2i(floori(point.x/64),floori(point.y/44))
			if not clusters.has(bucket): clusters[bucket] = {"point":Vector2(bucket)*Vector2(64,44)+Vector2(10,22),"count":0,"kind":str(building.kind)}
			clusters[bucket].count += 1
	for cluster in clusters.values():
		var point: Vector2 = cluster.point
		_draw_role(point,str(cluster.kind))
		_label(point+Vector2(9,5),"×%d" % cluster.count,UI.TEXT)
	var show_legend: bool=not (game.tool=="build" and size.y<650)
	if electrical and show_legend:
		_label(Vector2(100,148),"电力：实线已核实 · 虚线未知/断开 · 箭头潮流 · × 已知故障",UI.MUTED)
	elif game.overlay == "comm" and show_legend:
		_label(Vector2(100,148),"通信：实线光纤 · 虚线无线 · ✓可信 · ?待核实",Color("81c9ee"))

func _draw_role(at: Vector2, kind: String) -> void:
	var category: String=Presenter.category_for(kind)
	draw_circle(at,9,UI.SURFACE)
	match category:
		"power": draw_polyline(PackedVector2Array([at+Vector2(0,-7),at+Vector2(7,6),at+Vector2(-7,6),at+Vector2(0,-7)]),UI.TEAL,2,true)
		"city": draw_rect(Rect2(at-Vector2(6,6),Vector2(12,12)),UI.TEXT,false,2)
		"storage":
			draw_rect(Rect2(at-Vector2(7,4),Vector2(14,9)),UI.AMBER,false,2)
			draw_line(at+Vector2(0,-2),at+Vector2(0,3),UI.AMBER,2)
		"digital": draw_polyline(PackedVector2Array([at+Vector2(0,-7),at+Vector2(7,0),at+Vector2(0,7),at+Vector2(-7,0),at+Vector2(0,-7)]),Color("81c9ee"),2,true)
		_: draw_arc(at,6,0,TAU,12,UI.TEXT,2,true)
