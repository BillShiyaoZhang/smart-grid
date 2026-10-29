extends Control
## One zero-based quantity, with an explicit unknown state and optional draft marker.
## Values come from presentation snapshots; this control never reads or changes a simulation.
var caption := ""
var value := 0.0
var maximum := 1.0
var unit := ""
var accent := Color("77dbc0")
var known := true
var detail := ""
var ghost := -1.0
var compact := false
var remainder_color := Color("28434d")
var hatch_remainder := false
var show_value := true
const TEXT := Color("f2eddb")
const MUTED := Color("a4bbc0")

func _init() -> void:
	custom_minimum_size = Vector2(0,78)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	resized.connect(queue_redraw)
	theme_changed.connect(queue_redraw)

func configure(title: String, amount: float, limit: float, suffix: String="", color: Color=Color("77dbc0"), is_known: bool=true, note: String="") -> void:
	caption=title
	value=maxf(0.0,amount)
	maximum=maxf(.000001,limit)
	unit=suffix
	accent=color
	known=is_known
	detail=note
	tooltip_text=("%s · %.2f / %.2f %s" % [caption,value,maximum,unit] if known else caption+" · 待核实")+("\n"+detail if not detail.is_empty() else "")
	queue_redraw()

func sync_from(other: Control) -> void:
	for key in ["caption","value","maximum","unit","accent","known","detail","ghost","compact","remainder_color","hatch_remainder","show_value"]:
		set(key,other.get(key))
	tooltip_text=other.tooltip_text
	queue_redraw()

func ratio() -> float:
	return clampf(value/maximum,0,1) if known else -1.0

func _draw() -> void:
	var font: Font=get_theme_default_font()
	var label_size := 14
	var amount_size := 18 if compact else 22
	var bar_y := (0.0 if bool(get_meta("headerless",false)) else 26.0) if compact else 31.0
	var bar_height := 10.0 if compact else 14.0
	var track := Rect2(0,bar_y,maxf(1,size.x),bar_height)
	if not caption.is_empty(): draw_string(font,Vector2(0,17),caption,HORIZONTAL_ALIGNMENT_LEFT,maxf(1,size.x*.65),label_size,MUTED)
	if show_value:
		var text := ("%.1f %s" % [value,unit]).strip_edges() if known else "? 待核实"
		var width: float=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,amount_size).x
		draw_string(font,Vector2(maxf(0,size.x-width),21),text,HORIZONTAL_ALIGNMENT_LEFT,-1,amount_size,accent if known else MUTED)
	draw_style_box(_box(remainder_color,4),track)
	if known:
		var filled := Rect2(track.position,Vector2(track.size.x*ratio(),track.size.y))
		if filled.size.x>0: draw_style_box(_box(accent,4),filled)
		if hatch_remainder: _hatch(Rect2(Vector2(filled.end.x,track.position.y),Vector2(maxf(0,track.end.x-filled.end.x),track.size.y)),Color("f38a79"))
	else:
		_hatch(track,MUTED)
	if ghost>=0:
		var draft_x: float=track.position.x+clampf(ghost/maximum,0,1)*track.size.x
		draw_line(Vector2(draft_x,track.position.y-4),Vector2(draft_x,track.end.y+4),TEXT,2,true)
		draw_circle(Vector2(draft_x,track.position.y-4),3,TEXT)
	if not detail.is_empty(): draw_string(font,Vector2(0,track.end.y+21),detail,HORIZONTAL_ALIGNMENT_LEFT,maxf(1,size.x),14,MUTED)

func _hatch(area: Rect2, color: Color) -> void:
	if area.size.x<1: return
	for index in range(int(ceilf(area.size.x/8.0))+2):
		var start_x: float=area.position.x+index*8.0
		var finish_x: float=start_x-area.size.y
		var start := Vector2(minf(start_x,area.end.x),area.position.y+maxf(0,start_x-area.end.x))
		var finish := Vector2(maxf(finish_x,area.position.x),area.end.y-maxf(0,area.position.x-finish_x))
		if start.y<=area.end.y and finish.y>=area.position.y: draw_line(start,finish,Color(color,.65),1.2,true)

func _box(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color=color
	box.set_corner_radius_all(radius)
	return box
