extends Control

## Presentation-only forecast chart. Values are read from the supplied snapshot.
var points: Array[Dictionary] = []
var _hovered := -1
var threshold_lines: Array = []

const INK := Color("102c38")
const MINT := Color("77dbc0")
const ORANGE := Color("efbb7d")
const TEXT := Color("b6cbd0")
const GRID := Color(0.55, 0.72, 0.76, 0.14)
const FONT_SIZE := 14

func _init() -> void:
	custom_minimum_size = Vector2(0, 144)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	resized.connect(queue_redraw)
	theme_changed.connect(queue_redraw)
	mouse_exited.connect(_clear_hover)

func set_points(value: Array) -> void:
	var next_points: Array[Dictionary] = []
	for item in value:
		if item is Dictionary:
			next_points.append(item.duplicate())
	if points == next_points:
		return
	points = next_points
	_hovered = -1
	tooltip_text = ""
	queue_redraw()

func _plot_rect() -> Rect2:
	return Rect2(Vector2(54, 38), Vector2(maxf(1, size.x - 70), maxf(1, size.y - 66)))

func _maximum() -> float:
	var maximum := 100.0
	for point in points:
		maximum = maxf(maximum, maxf(float(point.get("spot", 0)), float(point.get("retail", 0))))
	for line in threshold_lines: maximum=maxf(maximum,float(line.get("value",0)))
	return ceilf(maximum / 100.0) * 100.0

func set_thresholds(value: Array) -> void:
	threshold_lines=value.duplicate(true)
	queue_redraw()

func _x(index: int, area: Rect2) -> float:
	return area.position.x + area.size.x * float(index) / maxf(1, points.size() - 1)

func _position(index: int, channel: String, area: Rect2, maximum: float) -> Vector2:
	var value := clampf(float(points[index].get(channel, 0)), 0, maximum)
	return Vector2(_x(index, area), area.end.y - value / maximum * area.size.y)

func _draw() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(INK, 0.68)
	background.set_corner_radius_all(8)
	draw_style_box(background, Rect2(Vector2.ZERO, size))
	var font := get_theme_default_font()
	var area := _plot_rect()
	var maximum := _maximum()
	# Legend and unit are part of the chart, so it remains understandable alone.
	draw_line(Vector2(13, 17), Vector2(30, 17), MINT, 2.2, true)
	draw_string(font, Vector2(36, 21), "现货电价", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, MINT)
	draw_line(Vector2(116, 17), Vector2(133, 17), ORANGE, 2.2, true)
	draw_string(font, Vector2(139, 21), "零售电价", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, ORANGE)
	var unit := "¥ / MWh"
	var unit_width := font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_string(font, Vector2(maxf(240, size.x - unit_width - 14), 21), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
	# A point represents the beginning of an hourly interval.
	if points.size() > 1:
		var interval := area.size.x / float(points.size() - 1)
		for i in range(points.size()):
			var hour := int(points[i].get("hour", i)) % 24
			if hour >= 17 and hour < 21:
				var left := _x(i, area)
				var width := minf(interval, area.end.x - left)
				draw_rect(Rect2(left, area.position.y, width, area.size.y), Color(ORANGE, 0.075))
	for i in range(4):
		var fraction := float(i) / 3.0
		var y := area.end.y - fraction * area.size.y
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), GRID, 1, true)
		var label := "%d" % roundi(maximum * fraction)
		var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		draw_string(font, Vector2(area.position.x - width - 8, y + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
	if points.is_empty():
		draw_string(font, area.position + Vector2(12, 30), "等待市场预测", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
		return
	var first_day := int(points[0].get("day", 1))
	var last_day := first_day
	for i in range(points.size()):
		var hour := int(points[i].get("hour", i)) % 24
		var day := int(points[i].get("day", first_day))
		var x := _x(i, area)
		if day > last_day:
			draw_dashed_line(Vector2(x, area.position.y), Vector2(x, area.end.y), Color(TEXT, 0.35), 1, 3, true)
			draw_string(font, Vector2(minf(x + 4, area.end.x - 31), area.position.y + 12), "D+%d" % (day - first_day), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
		last_day = day
		var label_stride := 6 if area.size.x < 340 else 4
		if i % label_stride == 0:
			var label := "现在" if i == 0 else "%02d:00" % hour
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			draw_string(font, Vector2(clampf(x - width * 0.5, area.position.x - 6, size.x - width - 5), area.end.y + 18), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT)
	for channel in ["retail", "spot"]:
		var color := MINT if channel == "spot" else ORANGE
		var line := PackedVector2Array()
		for i in range(points.size()):
			line.append(_position(i, channel, area, maximum))
		if line.size() > 1:
			draw_polyline(line, color, 2.0, true)
		else:
			draw_circle(line[0], 2.5, color)
	for threshold in threshold_lines:
		var value: float=float(threshold.get("value",0))
		var y: float=area.end.y-clampf(value/maximum,0,1)*area.size.y
		var color: Color=threshold.get("color",MINT)
		var draft: bool=bool(threshold.get("draft",false))
		if draft: draw_dashed_line(Vector2(area.position.x,y),Vector2(area.end.x,y),color,1.5,5,true)
		else: draw_line(Vector2(area.position.x,y),Vector2(area.end.x,y),Color(color,.65),1,true)
		draw_string(font,Vector2(area.position.x+8,clampf(y-4,area.position.y+14,area.end.y-4)),str(threshold.get("label","阈值"))+" %.0f" % value+(" · 草案" if draft else " · 生效"),HORIZONTAL_ALIGNMENT_LEFT,area.size.x-8,14,color)
	if _hovered >= 0 and _hovered < points.size():
		var x := _x(_hovered, area)
		draw_dashed_line(Vector2(x, area.position.y), Vector2(x, area.end.y), Color(TEXT, 0.60), 1, 3, true)
		for channel in ["spot", "retail"]:
			var at := _position(_hovered, channel, area, maximum)
			var color := MINT if channel == "spot" else ORANGE
			draw_circle(at, 4.2, INK)
			draw_circle(at, 2.7, color)

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return
	var area := _plot_rect()
	var at := get_local_mouse_position()
	if points.is_empty() or not area.has_point(at):
		_clear_hover()
		return
	var index := clampi(roundi((at.x - area.position.x) / area.size.x * (points.size() - 1)), 0, points.size() - 1)
	if index == _hovered:
		return
	_hovered = index
	var point := points[index]
	tooltip_text = "第 %d 天  %02d:00\n现货电价  ¥%.0f / MWh\n零售电价  ¥%.0f / MWh" % [int(point.get("day", 1)), int(point.get("hour", index)) % 24, float(point.get("spot", 0)), float(point.get("retail", 0))]
	queue_redraw()

func _clear_hover() -> void:
	if _hovered >= 0:
		_hovered = -1
		tooltip_text = ""
		queue_redraw()
