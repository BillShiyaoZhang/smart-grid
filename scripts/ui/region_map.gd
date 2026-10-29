extends Control
## The regional overview uses town service feedback rather than remote line telemetry.
signal city_selected(id: int)
var sim: RefCounted
var selected_id := -1
const TEAL := Color("77dbc0")
const MUTED := Color("819ca6")
const ORANGE := Color("efbb7d")
const CREAM := Color("f2eddb")

func _ready() -> void:
	custom_minimum_size = Vector2(0, 270)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)

func refresh() -> void:
	queue_redraw()

func _position(cell: Vector2i) -> Vector2:
	var extent := maxi(1, int(sim.map_size()) - 1) if sim != null else 47
	return Vector2(35, 24) + Vector2(cell) / float(extent) * (size - Vector2(70, 86))

func _draw() -> void:
	if sim == null:
		return
	var font := get_theme_default_font()
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	for index in range(1, 6):
		var x := float(index) / 6.0 * size.x
		var y := float(index) / 6.0 * size.y
		draw_line(Vector2(x, 10), Vector2(x, size.y - 25), Color(0.5, 0.8, 0.8, 0.07))
		draw_line(Vector2(10, y), Vector2(size.x - 10, y), Color(0.5, 0.8, 0.8, 0.07))
	for line in sim.lines:
		var first: Dictionary = sim.get_building(int(line.a))
		var second: Dictionary = sim.get_building(int(line.b))
		if first.is_empty() or second.is_empty():
			continue
		# No exact flow/fault data is exposed on this demographic map.
		draw_line(_position(first.cell), _position(second.cell), Color(0.45, 0.65, 0.65, 0.25), 1.0, true)
	for building in sim.buildings:
		draw_circle(_position(building.cell), 1.7, Color(0.7, 0.8, 0.7, 0.5))
	if sim.get("region") == null or not sim.region.active:
		draw_string(font, Vector2(25, 40), "现有设施与电力连接", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, CREAM)
		draw_string(font, Vector2(16, size.y - 10), "登记城市后可查看人口与供电反馈", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)
		return
	for city in sim.region.cities:
		var at := _position(city.anchor)
		var active: bool=str(city.get("service_phase","active"))=="active"
		var color := (TEAL if float(city.service) >= 0.93 else ORANGE) if active else MUTED
		var radius := sqrt(maxf(0,float(city.population))/100.0)*1.7
		draw_circle(at, radius + 5, Color(color, 0.1))
		draw_circle(at, radius, color)
		if not active: draw_circle(at,maxf(0,radius-2),Color("12333d"))
		if int(city.id) == selected_id:
			draw_arc(at, radius + 5, 0, TAU, 32, CREAM, 1.5, true)
		var caption := str(city.name)
		var caption_width := font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		var caption_at := at+Vector2(14,-10 if int(city.id)%2==0 else 17)
		caption_at.x = clampf(caption_at.x,12,maxf(12,size.x-caption_width-12))
		draw_string(font,caption_at,caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14,CREAM)
	draw_string(font, Vector2(16, size.y - 45), "圆面积 ∝ 人口 · ○ 潜在市场 / ● 已服务", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)
	draw_circle(Vector2(24,size.y-22),sqrt(1000.0/100.0)*1.7,MUTED,false,1)
	draw_string(font, Vector2(38, size.y - 17), "1千人", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)
	draw_circle(Vector2(116,size.y-22),sqrt(5000.0/100.0)*1.7,MUTED,false,1)
	draw_string(font, Vector2(135, size.y - 17), "5千人 · 青绿 稳定 / 琥珀 改善", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)

func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("12333d")
	style.set_corner_radius_all(10)
	return style

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT or sim == null or sim.get("region") == null:
		return
	for city in sim.region.cities:
		if event.position.distance_to(_position(city.anchor)) < 18.0:
			selected_id = int(city.id)
			city_selected.emit(selected_id)
			queue_redraw()
			accept_event()
			return
