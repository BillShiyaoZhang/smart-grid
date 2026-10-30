extends Control
const UI=preload("res://scripts/ui/ui_kit.gd")
var event: Dictionary={}
func _init() -> void:
	custom_minimum_size=Vector2(0,160)
func set_event(value: Dictionary) -> void:
	event=value.duplicate(true)
	queue_redraw()
func _draw() -> void:
	draw_style_box(UI.style(Color("102630")),Rect2(Vector2.ZERO,size))
	var font:=get_theme_default_font()
	draw_string(font,Vector2(12,23),"停电恢复过程 · 已供电比例",HORIZONTAL_ALIGNMENT_LEFT,-1,14,UI.TEXT)
	if event.is_empty():
		draw_string(font,Vector2(18,83),"尚无停电记录；实际失供后自动记录。",HORIZONTAL_ALIGNMENT_LEFT,-1,14,UI.MUTED)
		return
	var area:=Rect2(42,38,maxf(1,size.x-60),maxf(1,size.y-70))
	for i in 3:
		var y:=area.end.y-area.size.y*float(i)/2.0
		draw_line(Vector2(area.position.x,y),Vector2(area.end.x,y),Color(.6,.7,.8,.2))
		draw_string(font,Vector2(6,y+4),"%d%%" % (i*50),HORIZONTAL_ALIGNMENT_LEFT,-1,12,UI.MUTED)
	var points: Array=event.curve
	var start:=float(event.start)
	var finish:=float(points[-1].hour) if not points.is_empty() else start+.01
	var previous:=Vector2(area.position.x,area.end.y)
	for point in points:
		var at:=Vector2(area.position.x+(float(point.hour)-start)/maxf(.001,finish-start)*area.size.x,area.end.y-clampf(float(point.served_fraction),0,1)*area.size.y)
		draw_line(previous,Vector2(at.x,previous.y),UI.TEAL,2,true)
		draw_line(Vector2(at.x,previous.y),at,UI.TEAL,2,true)
		previous=at
	draw_string(font,Vector2(area.position.x,area.end.y+22),"%s · %.2f小时 · 失供 %.2f MWh · 补偿 ¥%.0f" % [event.name,event.duration,event.unserved_mwh,event.cost],HORIZONTAL_ALIGNMENT_LEFT,area.size.x,13,UI.MUTED)
