extends Control
## A nameplate and a current measurement share a scale, never a source of truth.
const UI = preload("res://scripts/ui/ui_kit.gd")
var snapshot: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(queue_redraw)
	theme_changed.connect(queue_redraw)

func set_snapshot(value: Dictionary) -> void:
	snapshot = value.duplicate(true)
	custom_minimum_size = Vector2(0, 166 if snapshot.get("storage", false) else (128 if snapshot.get("generator", false) else 76))
	queue_redraw()

func sync_from(other: Control) -> void:
	set_snapshot(other.snapshot)

func _number(key: String) -> float:
	var value: Variant = snapshot.get(key)
	return float(value) if value != null else 0.0

func _gauge(caption: String, value: Variant, limit: float, unit: String, at: float, color: Color, known: bool, footer: String="") -> void:
	var font := get_theme_default_font()
	var width := maxf(1, size.x - 4)
	draw_string(font, Vector2(0, at + 17), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.MUTED)
	var number := "%.1f %s" % [float(value), unit] if known and value != null else "? 待核实"
	var text_width := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string(font, Vector2(maxf(0, width - text_width), at + 19), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color if known else UI.MUTED)
	var track := Rect2(0, at + 29, width, 14)
	draw_style_box(UI.style(Color("0a202b"), 4, Color("34515b"), 0), track)
	if known and value != null:
		var filled := Rect2(track.position, Vector2(width * clampf(absf(float(value)) / maxf(0.001, limit), 0, 1), track.size.y))
		if filled.size.x > 0:
			draw_style_box(UI.style(color, 4, color, 0), filled)
	else:
		for x in range(0, int(width) - 10, 12):
			draw_line(Vector2(x, at + 41), Vector2(x + 8, at + 31), Color("58717b"), 1, true)
	var detail := footer if not footer.is_empty() else "额定 %.1f %s" % [limit, unit]
	draw_string(font, Vector2(0, at + 61), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.MUTED)

func _draw() -> void:
	if snapshot.is_empty(): return
	var known: bool = bool(snapshot.get("trusted", false))
	if bool(snapshot.get("storage", false)):
		_gauge("当前电量", snapshot.get("energy"), _number("energy_capacity"), "MWh", 0, UI.TEAL, known)
		var output: Variant = snapshot.get("output")
		var charging: Variant = snapshot.get("charging")
		var is_charging: bool = known and charging != null and float(charging) > 0.001
		_gauge("充电功率" if is_charging else "放电功率", charging if is_charging else output, _number("capacity"), "MW", 70, UI.AMBER, known)
		var duration: Variant=snapshot.get("duration_hours")
		var caption := "当前功率与时长待核实"
		if known:
			caption="按当前放电约 %.1f 小时" % float(duration) if duration != null else ("充电中 · 时长随运行变化" if is_charging else "当前未放电" if charging != null else "充电方向待核实")
		draw_string(get_theme_default_font(),Vector2(0,157),caption,HORIZONTAL_ALIGNMENT_LEFT,size.x,14,UI.MUTED)
	elif bool(snapshot.get("generator", false)):
		_gauge("实际输出", snapshot.get("output"), _number("capacity"), "MW", 0, UI.TEAL, known)
		_gauge("当前可用", snapshot.get("available"), _number("capacity"), "MW", 65, UI.AMBER, known)
	else:
		_gauge("实际供电", snapshot.get("served"), maxf(0.01, _number("demand")), "MW", 0, UI.TEAL, known, "当前需求 %.1f MW" % _number("demand") if known else "当前需求与供电读数待核实")

func _get_tooltip(_at: Vector2) -> String:
	return "斜纹与问号表示当前读数未知；不是零功率。额定为设备设计上限，当前可用与实际交付由观测决定。"
