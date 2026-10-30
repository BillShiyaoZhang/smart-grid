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
		var loading: float=absf(flow)/maxf(.1,float(line.capacity))
		var focus_network: bool=game.hud.lens in ["operations","planning","market"]
		if not electrical and not selected and not related and not fault and not (current and absf(flow)>.02): continue
		# A dark outline preserves the route against both sunlit grass and storm light.
		if current: draw_line(start,finish,Color("0a202ccc"),7 if selected else 5,true)
		if focus_network and loading<.8 and not selected and not related: color=Color("658a8a88")
		if current and loading >= .8: color = UI.AMBER
		if current and loading>1.0: color=UI.RED
		if fault: color = UI.RED
		if selected: draw_line(start,finish,UI.TEXT,6,true)
		if not current or not closed or fault: draw_dashed_line(start,finish,color,3 if selected else 2,7)
		else: draw_line(start,finish,color,4 if selected else clampf(1.5+sqrt(absf(flow))*.5,1.5,7),true)
		if current and loading>=.8 and not selected and focus_network and game.zoom<65:
			_label(start.lerp(finish,.5)+Vector2(5,16),"! %.0f%% · %.1f MW" % [loading*100,absf(flow)],color)
		if fault:
			var center: Vector2=start.lerp(finish,.5)
			draw_circle(center,10,Color("142b35"))
			draw_arc(center,10,0,TAU,24,UI.RED,2,true)
			draw_line(center-Vector2(4,4),center+Vector2(4,4),UI.RED,2,true)
			draw_line(center+Vector2(-4,4),center+Vector2(4,-4),UI.RED,2,true)
			if not selected and game.zoom<65: _label(center+Vector2(12,-12),"× 已核实故障",UI.RED)
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
	# The priority card can suggest a connection using public topology, never a
	# hidden fault or a promised post-construction power outcome.
	if game.tool=="select" and not game.hud._focus_item.is_empty() and game.hud._focus_item.get("action","")=="connect":
		var target: Dictionary=game.sim.get_building(int(game.hud._focus_item.get("target_id",-1)))
		var nearest: Dictionary={}
		var distance := INF
		if not target.is_empty():
			for building in game.sim.buildings:
				if building.kind!="substation" or int(building.id)==int(target.id): continue
				var candidate: float=Vector2(building.cell).distance_to(Vector2(target.cell))
				if candidate<distance: nearest=building; distance=candidate
			if not nearest.is_empty():
				var start: Vector2=_screen(game._cell_position(nearest.cell)+Vector3.UP*.65)
				var finish: Vector2=_screen(game._cell_position(target.cell)+Vector3.UP*.65)
				draw_dashed_line(start,finish,UI.AMBER,2.5,8,true)
				draw_circle(start,5,UI.AMBER)
				draw_arc(finish,11,0,TAU,24,UI.AMBER,2,true)
				if game.zoom<65: _label(start.lerp(finish,.35)+Vector2(8,-36),"候选连接",UI.AMBER)
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
		if point.x < -24 or point.y < -24 or point.x > size.x+24 or point.y > size.y+24: continue
		var targeted: bool = id in [game.selected_id,game.connection_start,game._building_at(game.hover_cell)]
		var feedback: Dictionary=Presenter.customer_feedback(game.sim,id)
		if not feedback.is_empty() and not bool(feedback.powered) and (game.zoom<=60 or targeted):
			var ground: Vector2=_screen(game._cell_position(building.cell)+Vector3.UP*.12)
			draw_arc(ground,17,0,TAU,24,UI.AMBER,2.5,true)
			draw_circle(point,9,Color("112b35"))
			draw_string(get_theme_default_font(),point+Vector2(-3,5),"!",HORIZONTAL_ALIGNMENT_LEFT,-1,16,UI.AMBER)
			if not targeted and game.zoom<65: _label(point+Vector2(12,5),"用户报告停电",UI.AMBER)
		elif not feedback.is_empty() and building.kind=="hospital" and game.zoom<65 and not targeted and game.sim.storm_active:
			_label(point+Vector2(8,-4),"✚ 医院供电正常",UI.TEXT)
		if targeted:
			_label(point+Vector2(7,-5),"%02d · %s" % [id,building.name],UI.TEXT)
		elif game.zoom>60:
			var bucket := Vector2i(floori(point.x/64),floori(point.y/44))
			if not clusters.has(bucket): clusters[bucket] = {"point":Vector2(bucket)*Vector2(64,44)+Vector2(10,22),"count":0,"outages":0,"kind":str(building.kind)}
			clusters[bucket].count += 1
			if not feedback.is_empty() and not bool(feedback.powered): clusters[bucket].outages+=1
	for cluster in clusters.values():
		var point: Vector2 = cluster.point
		_draw_role(point,str(cluster.kind))
		_label(point+Vector2(9,5),("×%d · !%d" % [cluster.count,cluster.outages]) if cluster.outages>0 else "×%d" % cluster.count,UI.AMBER if cluster.outages>0 else UI.TEXT)
	_draw_lens_annotations()
	var show_legend: bool=not (game.tool=="build" and size.y<650)
	if electrical and show_legend:
		_label(Vector2(100,size.y-96),"实线已核实 · 虚线未知/断开 · 箭头潮流 · × 已知故障",UI.MUTED)
	elif game.overlay == "comm" and show_legend:
		_label(Vector2(100,size.y-96),"通信：实线光纤 · 虚线无线 · ✓可信 · ?待核实",Color("81c9ee"))
	elif game.hud.lens=="customers" and show_legend:
		_label(Vector2(100,size.y-96),"用户反馈 · ✚ 关键负荷 · ! 失供 · 聚合负荷点口径",UI.MUTED)
	elif game.hud.lens in ["assets","maintenance"] and show_legend:
		_label(Vector2(100,size.y-96),"已知健康 × 公开影响 · ? 未核实 · 不能推断精确故障",UI.MUTED)

func _draw_lens_annotations() -> void:
	var lens: String=game.hud.lens
	if lens in ["assets","maintenance"]:
		for row in game.hud.lens_snapshot.get("assets",[]):
			if row.get("target_type","facility")!="facility": continue
			var b: Dictionary=game.sim.get_building(int(row.get("target_id",row.get("id",-1))))
			if b.is_empty(): continue
			var point:=_screen(game._cell_position(b.cell)+Vector3.UP*2.1)
			if not Rect2(Vector2(0,135),Vector2(size.x,maxf(0,size.y-220))).has_point(point): continue
			var health: Variant=row.get("health")
			var historical: bool=row.get("confidence","")=="stale"
			var color: Color=UI.MUTED if health==null or historical else (UI.RED if float(health)<50 else (UI.AMBER if float(health)<75 else UI.TEAL))
			if health==null or float(health)<75 or float(row.get("criticality",0))>.8:
				_label(point,("? 当前健康未知" if health==null or historical else "健康 %.0f%%" % float(health))+(" · ✚ 高影响" if float(row.get("criticality",0))>.8 else ""),color)
	elif lens in ["customers","market","planning"]:
		for b in game.sim.buildings:
			var feedback: Dictionary=Presenter.customer_feedback(game.sim,int(b.id))
			var point:=_screen(game._cell_position(b.cell)+Vector3.UP*2.1)
			if not Rect2(Vector2(0,135),Vector2(size.x,maxf(0,size.y-220))).has_point(point): continue
			if lens=="customers" and not feedback.is_empty() and game.zoom<65:
				_label(point,("✚ " if b.kind=="hospital" else "")+str(b.name)+(" · 已供电" if feedback.powered else " · ! 报告失供"),UI.TEAL if feedback.powered else UI.AMBER)
			elif lens=="market" and game.sim.evolution.is_terminal(str(b.kind)):
				var observation: Dictionary=game.sim.facility_observation(int(b.id))
				_label(point,"交易入口 · "+("%+.1f MW" % float(observation.output) if observation.trusted else "? 功率待核实"),Color("81c9ee"))
			elif lens=="planning" and b.kind in ["home","factory","hospital"] and feedback.is_empty():
				_label(point,"◇ 待开通服务 · 规划接入",UI.MUTED)

func _draw_role(at: Vector2, kind: String) -> void:
	var category: String=Presenter.category_for(kind)
	draw_circle(at,9,UI.SURFACE)
	match category:
		"power": draw_polyline(PackedVector2Array([at+Vector2(0,-7),at+Vector2(7,6),at+Vector2(-7,6),at+Vector2(0,-7)]),UI.TEAL,2,true)
		"city": draw_circle(at,5,UI.AMBER)
		"storage":
			draw_rect(Rect2(at-Vector2(7,4),Vector2(14,9)),UI.AMBER,false,2)
			draw_line(at+Vector2(0,-2),at+Vector2(0,3),UI.AMBER,2)
		"grid": draw_polyline(PackedVector2Array([at+Vector2(0,-7),at+Vector2(7,0),at+Vector2(0,7),at+Vector2(-7,0),at+Vector2(0,-7)]),UI.TEXT,2,true)
		_: draw_rect(Rect2(at-Vector2(4,4),Vector2(8,8)),Color("81c9ee"),false,2)
