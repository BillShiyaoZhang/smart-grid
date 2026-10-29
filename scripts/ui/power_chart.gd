extends Control

var history: Array[Vector2] = []
var mode: String = "chart"
var sim: RefCounted

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func sample(demand: float, generation: float) -> void:
	history.append(Vector2(demand, generation))
	if history.size() > 70:
		history.pop_front()
	queue_redraw()

func _draw() -> void:
	if mode == "topology":
		_draw_topology()
		return
	var area := Rect2(0, 0, size.x, size.y - 4)
	for i in range(4):
		var y := area.size.y * float(i) / 3.0
		draw_line(Vector2(0,y), Vector2(size.x,y), Color(0.4,0.6,0.65,0.13))
	if history.size() < 2:
		return
	var maximum := 12.0
	for v in history:
		maximum = maxf(maximum, maxf(v.x,v.y)*1.12)
	for channel in range(2):
		var points := PackedVector2Array()
		for i in range(history.size()):
			points.append(Vector2(float(i)/69.0*size.x,area.size.y*(1.0-history[i][channel]/maximum)))
		draw_polyline(points, Color("70d9c0") if channel == 1 else Color("f5bc7c"), 2.2, true)

func _draw_topology() -> void:
	if sim == null:
		return
	for line in sim.lines:
		var a: Dictionary = sim.get_building(line.a)
		var b: Dictionary = sim.get_building(line.b)
		if a.is_empty() or b.is_empty():
			continue
		var p := Vector2(a.cell) / float(sim.map_size()) * size
		var q := Vector2(b.cell) / float(sim.map_size()) * size
		var color := Color("64ccba")
		var observation: Dictionary=sim.line_observation(int(line.id))
		var trusted: bool=observation.get("visibility","") in ["verified","patrol"]
		if trusted and observation.get("fault_known",false) and observation.get("fault",false):
			color = Color("f48478")
		elif not trusted or not observation.get("closed",true):
			color = Color("526a74")
		draw_line(p,q,color,1.6,true)
	for b in sim.buildings:
		var color := Color("f2e8d4") if b.get("powered",false) else Color("e88c76")
		draw_circle(Vector2(b.cell)/float(sim.map_size())*size,3.6,color)
