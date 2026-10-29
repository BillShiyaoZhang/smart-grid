extends Control
signal node_selected(id: int)
signal link_selected(id: int)
var sim: RefCounted
var selected_id := -1
const BLUE := Color("81c9ee")
const TEAL := Color("77dbc0")
const MUTED := Color("718b98")
const ORANGE := Color("efbb7d")
const RED := Color("f38a79")
func _ready() -> void:
	custom_minimum_size = Vector2(520,300)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)
func _position(cell: Vector2i) -> Vector2:
	var span := maxf(15,float(sim.map_size()-1)) if sim!=null else 15.0
	return Vector2(38,32)+Vector2(cell)/span*(size-Vector2(88,104))
func _draw() -> void:
	if sim == null or sim.get("digital") == null:
		return
	var font := get_theme_default_font()
	for i in range(1,8):
		var at := i/8.0
		draw_line(Vector2(16,at*(size.y-16)),Vector2(size.x-16,at*(size.y-16)),Color(0.5,0.7,0.8,.07))
	for link in sim.digital.links:
		var a: Dictionary = sim.get_building(int(link.a))
		var b: Dictionary = sim.get_building(int(link.b))
		if a.is_empty() or b.is_empty():
			continue
		var p := _position(a.cell)
		var q := _position(b.cell)
		var color := RED if link.get("fault",false) else (BLUE if link.get("online",true) else MUTED)
		if link.get("kind","fiber") == "wireless":
			draw_dashed_line(p,q,color,1.7,5,true)
		else:
			draw_line(p,q,color,2,true)
	for building in sim.buildings:
		var state: Dictionary = sim.communication_status(int(building.id))
		var p := _position(building.cell)
		var color := TEAL if state.get("trusted",false) else (ORANGE if state.get("reachable",false) else MUTED)
		if state.get("isolated",false):
			color = RED
		if int(building.id) == selected_id:
			draw_arc(p,11,0,TAU,24,Color("f2eddb"),1.6,true)
		if state.get("root",false):
			draw_rect(Rect2(p-Vector2(5,5),Vector2(10,10)),color)
		else:
			draw_circle(p,5,color)
		var caption := "%02d" % int(building.id)
		var offset:=Vector2(8,22) if int(building.id)%3==1 else Vector2(8,-12)
		draw_string(font,p+offset,caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)
	draw_string(font,Vector2(16,size.y-29),"实线 光纤 · 虚线 无线 · ■ 调度根",HORIZONTAL_ALIGNMENT_LEFT,-1,14,MUTED)
	draw_string(font,Vector2(16,size.y-9),"● 可信 · ● 失联 / 隔离 · 悬停查看设备",HORIZONTAL_ALIGNMENT_LEFT,-1,14,MUTED)

func _get_tooltip(at: Vector2) -> String:
	if sim==null:
		return ""
	for building in sim.buildings:
		if at.distance_to(_position(building.cell))<22:
			var state: Dictionary=sim.communication_status(int(building.id))
			return "%02d · %s\n%s" % [building.id,building.name,state.get("reason","")]
	return ""
func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT or sim == null:
		return
	var at: Vector2 = event.position
	for building in sim.buildings:
		if at.distance_to(_position(building.cell))<14:
			selected_id = int(building.id)
			node_selected.emit(selected_id)
			queue_redraw()
			return
	for link in sim.digital.links:
		var a: Dictionary = sim.get_building(int(link.a))
		var b: Dictionary = sim.get_building(int(link.b))
		if a.is_empty() or b.is_empty():
			continue
		if Geometry2D.get_closest_point_to_segment(at,_position(a.cell),_position(b.cell)).distance_to(at)<5:
			link_selected.emit(int(link.id))
			return
