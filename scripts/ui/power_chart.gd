extends Control
## Presentation snapshots only: drawing and hovering never advance the simulation.
signal node_selected(id: int)
signal line_selected(id: int)
var history: Array[Vector2] = []
var sample_hours: Array[float] = []
var served_history: Array[float] = []
var mode: String = "chart"
var sim: RefCounted
var clock_offset := 8.0
const TEAL := Color("77dbc0")
const AMBER := Color("efbb7d")
const TEXT := Color("f2eddb")
const MUTED := Color("a4bbc0")
const RED := Color("f38a79")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
	theme_changed.connect(queue_redraw)

func reset_history() -> void:
	history.clear()
	sample_hours.clear()
	served_history.clear()
	queue_redraw()

func sample(demand: float, generation: float, elapsed_hours: float=-1.0, served: float=-1.0) -> void:
	if history.size() != sample_hours.size(): reset_history()
	if sim != null:
		clock_offset = float(sim.time_hours)+float(int(sim.day)-1)*24.0-float(sim.elapsed_hours)
	var hour: float = elapsed_hours
	if hour < 0:
		hour = float(sim.elapsed_hours) if sim != null else (sample_hours[-1]+1.0/12.0 if not sample_hours.is_empty() else 0.0)
	if not sample_hours.is_empty() and hour < sample_hours[-1]-0.00001: reset_history()
	var delivered: float = maxf(0.0,served) if served >= 0 else minf(demand,generation)
	# One latest-value snapshot per five game minutes keeps a full operating day
	# independent of frame rate and the selected simulation speed.
	if not sample_hours.is_empty() and floorf(hour*12.0)==floorf(sample_hours[-1]*12.0):
		history[-1] = Vector2(demand,generation)
		sample_hours[-1] = hour
		served_history[-1] = delivered
	else:
		history.append(Vector2(maxf(0,demand),maxf(0,generation)))
		sample_hours.append(hour)
		served_history.append(delivered)
	while history.size()>300 or (sample_hours.size()>2 and sample_hours[-1]-sample_hours[0]>24.0):
		history.pop_front()
		sample_hours.pop_front()
		served_history.pop_front()
	queue_redraw()

func _plot_rect() -> Rect2:
	return Rect2(44,26,maxf(1,size.x-56),maxf(1,size.y-54))

func _time_label(hour: float) -> String:
	var clock_hour: float = fposmod(hour+clock_offset,24.0)
	return "D%d %02d:%02d" % [int(floorf((hour+clock_offset)/24.0))+1,int(clock_hour),int(fposmod(clock_hour,1.0)*60.0)]

func _draw() -> void:
	if mode == "topology":
		_draw_topology()
		return
	var font: Font = get_theme_default_font()
	var area := _plot_rect()
	if history.size()<2 or history.size()!=sample_hours.size():
		draw_string(font,Vector2(8,24),"等待时间推进 · 尚无供需趋势",HORIZONTAL_ALIGNMENT_LEFT,-1,14,MUTED)
		return
	var maximum := 1.0
	for values in history: maximum = maxf(maximum,maxf(values.x,values.y)*1.12)
	var first: float = sample_hours[0]
	var span: float = maxf(0.00001,sample_hours[-1]-first)
	for i in range(3):
		var ratio: float = i/2.0
		var y: float = area.end.y-ratio*area.size.y
		draw_line(Vector2(area.position.x,y),Vector2(area.end.x,y),Color(0.5,0.7,0.8,0.18))
		draw_string(font,Vector2(0,y+4),"%.0f" % (maximum*ratio),HORIZONTAL_ALIGNMENT_LEFT,-1,14,MUTED)
		var caption: String = _time_label(first+span*ratio)
		var caption_width: float = font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		var caption_x: float = clampf(area.position.x+ratio*area.size.x-caption_width*0.5,0,maxf(0,size.x-caption_width))
		draw_string(font,Vector2(caption_x,area.end.y+20),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14,MUTED)
	draw_string(font,Vector2(0,15),"MW",HORIZONTAL_ALIGNMENT_LEFT,-1,14,MUTED)
	var demand_points := PackedVector2Array()
	var generation_points := PackedVector2Array()
	var served_points := PackedVector2Array()
	for i in range(history.size()):
		var x: float = area.position.x+(sample_hours[i]-first)/span*area.size.x
		demand_points.append(Vector2(x,area.end.y-history[i].x/maximum*area.size.y))
		generation_points.append(Vector2(x,area.end.y-history[i].y/maximum*area.size.y))
		served_points.append(Vector2(x,area.end.y-served_history[i]/maximum*area.size.y))
		if i>0 and (served_history[i]<history[i].x-0.001 or served_history[i-1]<history[i-1].x-0.001):
			draw_colored_polygon(PackedVector2Array([demand_points[i-1],demand_points[i],served_points[i],served_points[i-1]]),Color(RED,0.28))
	draw_polyline(demand_points,AMBER,2.0,true)
	draw_polyline(generation_points,TEAL,2.0,true)
	for i in range(1,served_points.size()):
		draw_dashed_line(served_points[i-1],served_points[i],TEXT,1.3,3.0,true)
	draw_string(font,Vector2(46,15),"供 %.1f  需 %.1f  已供 %.1f" % [history[-1].y,history[-1].x,served_history[-1]],HORIZONTAL_ALIGNMENT_LEFT,-1,14,TEXT)

func _node_position(cell: Vector2i) -> Vector2:
	var low := Vector2(10000,10000)
	var high := Vector2(-10000,-10000)
	for building in sim.buildings:
		low = low.min(Vector2(building.cell))
		high = high.max(Vector2(building.cell))
	var extent := (high-low).max(Vector2(1,1))
	return Vector2(14,12)+(Vector2(cell)-low)/extent*Vector2(maxf(1,size.x-28),maxf(1,size.y-36))

func _role(kind: String) -> String:
	if kind in ["home","factory","hospital","academy","cooling"]: return "load"
	if kind in ["battery","pumped_storage","flow_battery","community_battery","hydrogen","thermal_storage"]: return "storage"
	if kind in ["substation","intertie","hvdc","condenser"]: return "grid"
	if kind in ["sensor","control","relay","soc"]: return "digital"
	return "source"

func _draw_topology() -> void:
	if sim == null: return
	for line in sim.lines:
		var a: Dictionary = sim.get_building(line.a)
		var b: Dictionary = sim.get_building(line.b)
		if a.is_empty() or b.is_empty(): continue
		var p := _node_position(a.cell)
		var q := _node_position(b.cell)
		var observation: Dictionary = sim.line_observation(int(line.id))
		var trusted: bool = observation.get("visibility","") in ["verified","patrol"]
		var faulted: bool = trusted and observation.get("fault_known",false) and observation.get("fault",false)
		if not trusted or not observation.get("closed",true): draw_dashed_line(p,q,MUTED,1.6,4,true)
		else: draw_line(p,q,RED if faulted else TEAL,2,true)
		if faulted:
			var midpoint := p.lerp(q,0.5)
			draw_line(midpoint-Vector2(4,4),midpoint+Vector2(4,4),RED,2,true)
			draw_line(midpoint+Vector2(-4,4),midpoint+Vector2(4,-4),RED,2,true)
	for building in sim.buildings:
		var p := _node_position(building.cell)
		match _role(str(building.kind)):
			"source": draw_colored_polygon(PackedVector2Array([p+Vector2(0,-6),p+Vector2(6,5),p+Vector2(-6,5)]),TEAL)
			"load": draw_circle(p,5,AMBER)
			"storage": draw_rect(Rect2(p-Vector2(6,4),Vector2(12,8)),TEXT,false,2)
			"grid": draw_colored_polygon(PackedVector2Array([p+Vector2(0,-6),p+Vector2(6,0),p+Vector2(0,6),p+Vector2(-6,0)]),TEXT)
			_: draw_rect(Rect2(p-Vector2(4,4),Vector2(8,8)),MUTED)
	draw_string(get_theme_default_font(),Vector2(4,size.y-2),"△电源  ○负荷  ▭储能  ◇输电 · 点击定位",HORIZONTAL_ALIGNMENT_LEFT,-1,14,MUTED)

func _get_tooltip(at: Vector2) -> String:
	if mode != "topology": return "实线：供给 / 需求；白虚线：已供电；红色区域：未满足需求。横轴为当前情景的真实游戏日期与时刻，保留最近24游戏小时。"
	if sim == null: return ""
	for building in sim.buildings:
		if at.distance_to(_node_position(building.cell))<13: return "%02d · %s · 点击定位" % [building.id,building.name]
	return "虚线代表未核实或断开的线路，不能据此推断故障。"

func _gui_input(event: InputEvent) -> void:
	if mode != "topology" or sim == null or not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT: return
	for building in sim.buildings:
		if event.position.distance_to(_node_position(building.cell))<13:
			node_selected.emit(int(building.id))
			accept_event()
			return
	for line in sim.lines:
		var a: Dictionary = sim.get_building(line.a)
		var b: Dictionary = sim.get_building(line.b)
		if a.is_empty() or b.is_empty(): continue
		if Geometry2D.get_closest_point_to_segment(event.position,_node_position(a.cell),_node_position(b.cell)).distance_to(event.position)<6:
			line_selected.emit(int(line.id))
			accept_event()
			return
